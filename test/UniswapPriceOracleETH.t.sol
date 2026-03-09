// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV2Pair} from "../contracts/interfaces/IUniswapV2Pair.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @dev Fork tests for UniswapPriceOracle on Ethereum mainnet.
///      Run: forge test -f $FORK_NODE_URL --match-contract UniswapPriceOracleETH -vvv
contract BaseSetup is Test {
    Utils internal utils;
    UniswapPriceOracle internal oracle;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Ethereum mainnet addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant PAIR_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Oracle parameters (matching production deployment)
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;

    uint256 internal constant Q112 = 2 ** 112;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy fresh oracle pointing to real OLAS/WETH pair (WETH as reference token, matching production)
        oracle = new UniswapPriceOracle(PAIR_V2, WETH, minTwapWindowSeconds, minUpdateIntervalSeconds);
    }
}

contract UniswapPriceOracleETH is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Oracle deploys successfully with real pair.
    function testDeployWithRealPair() public view {
        assertEq(oracle.pair(), PAIR_V2);
        assertEq(oracle.minTwapWindow(), minTwapWindowSeconds);
        assertEq(oracle.minUpdateInterval(), minUpdateIntervalSeconds);
    }

    /// @dev Direction is set correctly based on WETH position in pair.
    function testDirection() public view {
        address token0 = IUniswapV2Pair(PAIR_V2).token0();
        if (token0 == WETH) {
            assertEq(oracle.direction(), 1);
        } else {
            assertEq(oracle.direction(), 0);
        }
    }

    /// @dev getPrice returns a non-zero, reasonable price from real reserves.
    function testGetPriceReal() public view {
        uint256 price = oracle.getPrice();
        assertGt(price, 0);
        console.log("Spot price (UQ112x112):", price);

        // Verify against raw reserves
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(PAIR_V2).getReserves();
        assertGt(r0, 0);
        assertGt(r1, 0);
        console.log("Reserve0:", r0);
        console.log("Reserve1:", r1);
    }

    /// @dev updatePrice succeeds and records correct observation.
    function testUpdatePrice() public {
        bool success = oracle.updatePrice();
        assertTrue(success);

        (uint256 cumulative, uint256 ts) = oracle.lastObservation();
        assertEq(ts, block.timestamp);
        assertGt(cumulative, 0);
        console.log("Cumulative price:", cumulative);
        console.log("Observation timestamp:", ts);
    }

    /// @dev updatePrice is rate-limited.
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
}
