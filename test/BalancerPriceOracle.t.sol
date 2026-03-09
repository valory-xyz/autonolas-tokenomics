// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";

/// @dev Mock Balancer Vault with configurable pool tokens and balances.
contract MockBalancerVault {
    struct PoolData {
        address[] tokens;
        uint256[] balances;
    }

    mapping(bytes32 => PoolData) private pools;

    function setPool(bytes32 poolId, address[] memory tokens, uint256[] memory balances) external {
        pools[poolId] = PoolData({tokens: tokens, balances: balances});
    }

    function setBalances(bytes32 poolId, uint256[] memory balances) external {
        pools[poolId].balances = balances;
    }

    function getPoolTokens(bytes32 poolId) external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    ) {
        PoolData storage data = pools[poolId];
        return (data.tokens, data.balances, block.number);
    }
}

contract BalancerOracleBaseSetup is Test {
    Utils internal utils;
    MockBalancerVault internal vault;
    BalancerPriceOracle internal oracle;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    address internal olas;
    address internal weth;
    bytes32 internal poolId = keccak256("test-pool");

    uint256 internal minTwapWindow = 900; // 15 minutes
    uint256 internal minUpdateInterval = 900; // 15 minutes
    uint256 internal maxStaleness = 1800; // 30 minutes

    // Default pool balances: 10000 WETH, 10000 OLAS (1:1 ratio)
    uint256 internal balanceWETH = 10_000 ether;
    uint256 internal balanceOLAS = 10_000 ether;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Use deterministic addresses for tokens
        olas = address(0x1111);
        weth = address(0x2222);

        // Deploy mock vault
        vault = new MockBalancerVault();

        // Setup pool: [weth, olas] with balances
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = olas;
        uint256[] memory balances = new uint256[](2);
        balances[0] = balanceWETH;
        balances[1] = balanceOLAS;
        vault.setPool(poolId, tokens, balances);

        // Deploy oracle (olas is tokens[1], so direction = 0)
        oracle = new BalancerPriceOracle(
            address(vault), poolId, olas,
            minTwapWindow, minUpdateInterval, maxStaleness
        );
    }

    /// @dev Helper to update vault balances.
    function _setBalances(uint256 wethBal, uint256 olasBal) internal {
        uint256[] memory balances = new uint256[](2);
        balances[0] = wethBal;
        balances[1] = olasBal;
        vault.setBalances(poolId, balances);
    }
}

contract BalancerPriceOracleConstructorTest is Test {
    MockBalancerVault internal vault;
    address internal olas = address(0x1111);
    address internal weth = address(0x2222);
    address internal other = address(0x3333);
    bytes32 internal poolId = keccak256("test-pool");

    function setUp() public {
        vault = new MockBalancerVault();

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = olas;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 10_000 ether;
        balances[1] = 10_000 ether;
        vault.setPool(poolId, tokens, balances);
    }

    /// @dev Reverts when vault address is zero.
    function testConstructorZeroAddress() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(0), poolId, olas, 900, 900, 1800);
    }

    /// @dev Reverts when minTwapWindow is zero.
    function testConstructorZeroMinTwapWindow() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 0, 300, 1800);
    }

    /// @dev Reverts when minUpdateInterval is zero.
    function testConstructorZeroMinUpdateInterval() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 900, 0, 1800);
    }

    /// @dev Reverts when minTwapWindow > minUpdateInterval.
    function testConstructorMinTwapExceedsUpdateInterval() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 1000, 500, 1800);
    }

    /// @dev Reverts when minTwapWindow > maxStaleness.
    function testConstructorStalenessOverflow() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 1000, 1000, 500);
    }

    /// @dev Reverts when pool doesn't contain OLAS.
    function testConstructorWrongPoolNoOlas() public {
        // Set up pool with no OLAS
        bytes32 badPoolId = keccak256("bad-pool");
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = other;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000 ether;
        balances[1] = 1000 ether;
        vault.setPool(badPoolId, tokens, balances);

        vm.expectRevert();
        new BalancerPriceOracle(address(vault), badPoolId, olas, 900, 900, 1800);
    }

    /// @dev Reverts when pool has wrong number of tokens.
    function testConstructorWrongPoolTokenCount() public {
        bytes32 triPoolId = keccak256("tri-pool");
        address[] memory tokens = new address[](3);
        tokens[0] = weth;
        tokens[1] = olas;
        tokens[2] = other;
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1000 ether;
        balances[1] = 1000 ether;
        balances[2] = 1000 ether;
        vault.setPool(triPoolId, tokens, balances);

        vm.expectRevert();
        new BalancerPriceOracle(address(vault), triPoolId, olas, 900, 900, 1800);
    }

    /// @dev Direction is 0 when OLAS is tokens[1].
    function testConstructorDirection0() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 900, 900, 1800);
        // weth is tokens[0], olas is tokens[1] => direction = 0
        assertEq(o.direction(), 0);
    }

    /// @dev Direction is 1 when OLAS is tokens[0].
    function testConstructorDirection1() public {
        // Set up pool with OLAS first
        bytes32 reversePoolId = keccak256("reverse-pool");
        address[] memory tokens = new address[](2);
        tokens[0] = olas;
        tokens[1] = weth;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 10_000 ether;
        balances[1] = 10_000 ether;
        vault.setPool(reversePoolId, tokens, balances);

        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), reversePoolId, olas, 900, 900, 1800);
        assertEq(o.direction(), 1);
    }

    /// @dev Immutable values are stored correctly.
    function testConstructorImmutables() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 900, 900, 1800);
        assertEq(o.minTwapWindow(), 900);
        assertEq(o.minUpdateInterval(), 900);
        assertEq(o.maxStaleness(), 1800);
        assertEq(o.balancerVault(), address(vault));
        assertEq(o.balancerPoolId(), poolId);
    }

    /// @dev Observations are initialized to zero at construction time.
    function testConstructorBootstrapsObservations() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 900, 900, 1800);
        (uint256 prevCum, uint256 prevTs) = o.prevObservation();
        (uint256 lastCum, uint256 lastTs) = o.lastObservation();
        assertEq(prevCum, 0);
        assertEq(prevTs, 0);
        assertEq(lastCum, 0);
        assertEq(lastTs, 0);
    }
}

contract BalancerPriceOracleGetPriceTest is BalancerOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Returns 1e18 for equal balances (1:1 ratio).
    function testGetPriceEqualBalances() public view {
        uint256 price = oracle.getPrice();
        // direction=0: balanceIn = balances[0] = weth, balanceOut = balances[1] = olas
        // price = olas * 1e18 / weth = 10000e18 * 1e18 / 10000e18 = 1e18
        assertEq(price, 1e18);
    }

    /// @dev Returns correct price for 2:1 ratio.
    function testGetPriceUnequalBalances() public {
        // Set balances: 5000 WETH, 10000 OLAS
        _setBalances(5000 ether, 10_000 ether);
        uint256 price = oracle.getPrice();
        // price = 10000e18 * 1e18 / 5000e18 = 2e18
        assertEq(price, 2e18);
    }

    /// @dev Returns correct price for 1:2 ratio.
    function testGetPriceHalfPrice() public {
        // Set balances: 10000 WETH, 5000 OLAS
        _setBalances(10_000 ether, 5000 ether);
        uint256 price = oracle.getPrice();
        // price = 5000e18 * 1e18 / 10000e18 = 0.5e18
        assertEq(price, 0.5e18);
    }

    /// @dev Reverts when balanceIn is zero.
    function testGetPriceZeroBalanceIn() public {
        _setBalances(0, 10_000 ether);
        vm.expectRevert();
        oracle.getPrice();
    }

    /// @dev Reverts when balanceOut is zero.
    function testGetPriceZeroBalanceOut() public {
        _setBalances(10_000 ether, 0);
        vm.expectRevert();
        oracle.getPrice();
    }

    /// @dev Reverts when both balances are zero.
    function testGetPriceZeroBothBalances() public {
        _setBalances(0, 0);
        vm.expectRevert();
        oracle.getPrice();
    }

    /// @dev Direction 1: OLAS is tokens[0], secondToken is tokens[1].
    function testGetPriceDirection1() public {
        // Create oracle with reversed pool
        bytes32 reversePoolId = keccak256("reverse-pool-price");
        address[] memory tokens = new address[](2);
        tokens[0] = olas;
        tokens[1] = weth;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 10_000 ether; // OLAS
        balances[1] = 5000 ether;   // WETH
        vault.setPool(reversePoolId, tokens, balances);

        BalancerPriceOracle oracleReverse = new BalancerPriceOracle(
            address(vault), reversePoolId, olas,
            minTwapWindow, minUpdateInterval, maxStaleness
        );

        // direction=1: balanceIn = balances[1] = weth = 5000, balanceOut = balances[0] = olas = 10000
        // price = 10000e18 * 1e18 / 5000e18 = 2e18
        assertEq(oracleReverse.getPrice(), 2e18);
    }
}

contract BalancerPriceOracleUpdatePriceTest is BalancerOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev First updatePrice call succeeds (lastObservation.timestamp is zero, bypasses rate limit).
    function testUpdatePriceImmediatelyAfterDeploy() public {
        // Constructor leaves lastObservation.timestamp = 0, so first call always succeeds
        bool success = oracle.updatePrice();
        assertTrue(success);
    }

    /// @dev First real updatePrice succeeds after minUpdateInterval.
    function testUpdatePriceFirstRealCall() public {
        vm.warp(block.timestamp + minUpdateInterval);
        bool success = oracle.updatePrice();
        assertTrue(success);
    }

    /// @dev Rate-limited: second call too soon returns false.
    function testUpdatePriceRateLimited() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Immediately try again
        bool success = oracle.updatePrice();
        assertFalse(success);

        // Just before interval
        vm.warp(block.timestamp + minUpdateInterval - 1);
        success = oracle.updatePrice();
        assertFalse(success);
    }

    /// @dev Second update succeeds after interval.
    function testUpdatePriceAfterInterval() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minUpdateInterval);
        bool success = oracle.updatePrice();
        assertTrue(success);
    }

    /// @dev Rolling window: prev becomes old last, last becomes new.
    function testUpdatePriceRollingWindow() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        (, uint256 lastTs1) = oracle.lastObservation();

        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // After second update, prev should be the first update's observation
        (, uint256 prevTs) = oracle.prevObservation();
        assertEq(prevTs, lastTs1);
    }

    /// @dev Emits ObservationUpdated event.
    function testUpdatePriceEmitsEvent() public {
        vm.warp(block.timestamp + minUpdateInterval);

        vm.expectEmit(true, false, false, false);
        emit BalancerPriceOracle.ObservationUpdated(address(this), 0, 0);
        oracle.updatePrice();
    }

    /// @dev Cumulative price accumulates correctly.
    function testUpdatePriceCumulativeValues() public {
        uint256 dt = minUpdateInterval;
        vm.warp(block.timestamp + dt);
        oracle.updatePrice();

        (uint256 lastCum,) = oracle.lastObservation();
        // spot = 1e18, elapsed from timestamp 0 to block.timestamp
        // cumulative = 0 + 1e18 * block.timestamp
        assertEq(lastCum, 1e18 * block.timestamp);
    }

    /// @dev Cumulative price updates correctly across multiple calls.
    function testUpdatePriceMultipleCumulative() public {
        uint256 dt = minUpdateInterval;

        // First update
        vm.warp(block.timestamp + dt);
        uint256 ts1 = block.timestamp;
        oracle.updatePrice();
        (uint256 cum1,) = oracle.lastObservation();
        // cumulative from timestamp 0 to ts1
        assertEq(cum1, 1e18 * ts1);

        // Second update (price still 1e18)
        vm.warp(block.timestamp + dt);
        oracle.updatePrice();
        (uint256 cum2,) = oracle.lastObservation();
        // cumulative = cum1 + 1e18 * dt
        assertEq(cum2, cum1 + 1e18 * dt);
    }

    /// @dev Cumulative reflects price change between updates.
    function testUpdatePriceCumulativeAfterPriceChange() public {
        uint256 dt = minUpdateInterval;

        // First update at price 1e18
        vm.warp(block.timestamp + dt);
        oracle.updatePrice();
        (uint256 cum1,) = oracle.lastObservation();

        // Change price to 2e18 (double OLAS)
        _setBalances(5000 ether, 10_000 ether);
        assertEq(oracle.getPrice(), 2e18);

        // Second update at price 2e18
        vm.warp(block.timestamp + dt);
        oracle.updatePrice();
        (uint256 cum2,) = oracle.lastObservation();

        // cum2 = cum1 + 2e18 * dt
        assertEq(cum2, cum1 + 2e18 * dt);
    }
}

contract BalancerPriceOracleGetTWAPTest is BalancerOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Reverts when not initialized (no observations).
    function testGetTWAPNotInitialized() public {
        vm.expectRevert();
        oracle.getTWAP();
    }

    /// @dev Reverts when only one observation exists (prev.timestamp == 0).
    function testGetTWAPNotFullyInitialized() public {
        oracle.updatePrice();

        vm.expectRevert();
        oracle.getTWAP();
    }

    /// @dev Reverts when last observation is stale.
    function testGetTWAPStale() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Warp past maxStaleness
        vm.warp(block.timestamp + maxStaleness + 1);

        vm.expectRevert();
        oracle.getTWAP();
    }

    /// @dev Returns correct TWAP with constant price.
    function testGetTWAPConstantPrice() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        uint256 twap = oracle.getTWAP();
        // With equal balances, price = 1e18, TWAP should also be 1e18
        assertEq(twap, 1e18);
    }

    /// @dev TWAP reflects price change over time.
    function testGetTWAPAfterPriceChange() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Change price to 2e18
        _setBalances(5000 ether, 10_000 ether);

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        uint256 twap = oracle.getTWAP();
        // TWAP should be between 1e18 and 2e18, converging toward 2e18
        assertGt(twap, 1e18);
        assertLe(twap, 2e18);
    }

    /// @dev TWAP is non-zero for valid state.
    function testGetTWAPNonZero() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        uint256 twap = oracle.getTWAP();
        assertGt(twap, 0);
    }

    /// @dev TWAP works at exact maxStaleness boundary.
    function testGetTWAPAtStalenessLimit() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Warp to exact maxStaleness boundary
        vm.warp(block.timestamp + maxStaleness);
        uint256 twap = oracle.getTWAP();
        assertEq(twap, 1e18);
    }
}
