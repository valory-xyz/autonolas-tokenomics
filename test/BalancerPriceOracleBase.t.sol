// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

// Balancer interface
interface IBalancer {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /// @dev Swaps tokens on Balancer.
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
    external payable returns (uint256);

    function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );
}

/// @dev Fork tests for BalancerPriceOracle on Base.
///      Run: forge test -f $FORK_NODE_URL --match-contract BalancerPriceOracleBase -vvv
contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracle;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Base mainnet addresses
    address internal constant OLAS = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal constant POOL_ID = 0x2da6e67c45af2aaa539294d9fa27ea50ce4e2c5f0002000000000000000001a3;

    // Oracle parameters (matching production deployment)
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 900;

    // Timestamp anchor set during setUp
    uint256 internal tSetup;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy fresh oracle pointing to real Balancer pool
        oracle = new BalancerPriceOracle(
            BALANCER_VAULT, POOL_ID, OLAS,
            minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds
        );

        // Record anchor and advance time so first updatePrice can succeed
        tSetup = block.timestamp;
        vm.warp(tSetup + minUpdateIntervalSeconds);
    }
}

contract BalancerPriceOracleBase is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Oracle deploys successfully with real Balancer pool.
    function testDeployWithRealPool() public view {
        assertEq(oracle.balancerVault(), BALANCER_VAULT);
        assertEq(oracle.balancerPoolId(), POOL_ID);
        assertEq(oracle.minTwapWindow(), minTwapWindowSeconds);
        assertEq(oracle.minUpdateInterval(), minUpdateIntervalSeconds);
        assertEq(oracle.maxStaleness(), maxStalenessSeconds);
    }

    /// @dev Direction is set correctly based on OLAS position in pool.
    function testDirection() public view {
        (address[] memory tokens,,) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_ID);
        if (tokens[0] == OLAS) {
            assertEq(oracle.direction(), 1);
        } else {
            assertEq(oracle.direction(), 0);
        }
        console.log("Direction:", oracle.direction());
        console.log("Token0:", tokens[0]);
        console.log("Token1:", tokens[1]);
    }

    /// @dev getPrice returns a non-zero, reasonable price from real balances.
    function testGetPriceReal() public view {
        uint256 price = oracle.getPrice();
        assertGt(price, 0);
        console.log("Spot price (1e18):", price);

        // Verify against raw balances
        (, uint256[] memory balances,) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_ID);
        console.log("Balance0:", balances[0]);
        console.log("Balance1:", balances[1]);
    }

    /// @dev updatePrice succeeds after minUpdateInterval from construction.
    function testUpdatePrice() public {
        bool success = oracle.updatePrice();
        assertTrue(success);

        (uint256 cumulative, uint256 ts) = oracle.lastObservation();
        assertEq(ts, block.timestamp);
        assertGt(cumulative, 0);
        console.log("Cumulative price:", cumulative);
        console.log("Observation timestamp:", ts);
    }

    /// @dev updatePrice is rate-limited after first call.
    function testUpdatePriceRateLimited() public {
        oracle.updatePrice();

        // Immediate second call fails
        bool success = oracle.updatePrice();
        assertFalse(success);
    }

    /// @dev updatePrice succeeds after interval.
    function testUpdatePriceAfterInterval() public {
        oracle.updatePrice();

        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        bool success = oracle.updatePrice();
        assertTrue(success);
    }

    /// @dev Rolling window: prev becomes old last after second update.
    function testUpdatePriceRollingWindow() public {
        oracle.updatePrice();
        (uint256 lastCum1, uint256 lastTs1) = oracle.lastObservation();

        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracle.updatePrice();

        // prev should now be the first update's observation
        (uint256 prevCum, uint256 prevTs) = oracle.prevObservation();
        assertEq(prevTs, lastTs1);
        assertEq(prevCum, lastCum1);
    }

    /// @dev Test multiple update cycles building TWAP history.
    function testMultipleUpdateCycles() public {
        // Use explicit absolute timestamps to avoid viaIR block.timestamp caching
        uint256 t0 = block.timestamp;

        // Cycle 1
        oracle.updatePrice();
        (uint256 cum1, uint256 ts1) = oracle.lastObservation();
        console.log("Cycle 1 - cumulative:", cum1, "ts:", ts1);
        assertEq(ts1, t0);

        // Cycle 2
        vm.warp(t0 + minUpdateIntervalSeconds);
        oracle.updatePrice();
        (uint256 cum2, uint256 ts2) = oracle.lastObservation();
        console.log("Cycle 2 - cumulative:", cum2, "ts:", ts2);
        assertGt(cum2, cum1);
        assertEq(ts2 - ts1, minUpdateIntervalSeconds);

        // Cycle 3
        vm.warp(t0 + 2 * minUpdateIntervalSeconds);
        oracle.updatePrice();
        (uint256 cum3, uint256 ts3) = oracle.lastObservation();
        console.log("Cycle 3 - cumulative:", cum3, "ts:", ts3);
        assertGt(cum3, cum2);
    }

    /// @dev Cumulative price accumulates correctly with known price.
    function testCumulativeAccumulation() public {
        uint256 spot = oracle.getPrice();
        console.log("Current spot price:", spot);

        uint256 t0 = block.timestamp;
        oracle.updatePrice();
        (uint256 cum1,) = oracle.lastObservation();

        vm.warp(t0 + minUpdateIntervalSeconds);
        oracle.updatePrice();
        (uint256 cum2,) = oracle.lastObservation();

        // Delta should be exactly spot * dt
        uint256 cumDelta = cum2 - cum1;
        uint256 expected = spot * minUpdateIntervalSeconds;
        console.log("Cumulative delta:", cumDelta);
        console.log("Expected (spot * dt):", expected);
        assertEq(cumDelta, expected);
    }

    /// @dev Validate that the fresh oracle and direct vault query return same price.
    function testOraclePriceMatchesVault() public view {
        uint256 oraclePrice = oracle.getPrice();

        (, uint256[] memory balances,) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_ID);
        uint256 dir = oracle.direction();
        uint256 balanceIn = balances[dir];
        uint256 balanceOut = balances[(dir + 1) % 2];
        uint256 manualPrice = (balanceOut * 1e18) / balanceIn;

        assertEq(oraclePrice, manualPrice);
        console.log("Oracle price:", oraclePrice);
        console.log("Manual price:", manualPrice);
    }
}
