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

    uint256 internal maxSlippageBps = 500; // 5%
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
            maxSlippageBps, minTwapWindow, minUpdateInterval, maxStaleness
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
        new BalancerPriceOracle(address(0), poolId, olas, 500, 900, 900, 1800);
    }

    /// @dev Reverts when maxSlippageBps exceeds MAX_BPS.
    function testConstructorOverflowSlippage() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 10_001, 900, 300, 1800);
    }

    /// @dev Succeeds at MAX_BPS boundary.
    function testConstructorMaxSlippage() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 10_000, 900, 900, 1800);
        assertEq(o.maxSlippageBps(), 10_000);
    }

    /// @dev Reverts when minTwapWindow is zero.
    function testConstructorZeroMinTwapWindow() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 500, 0, 300, 1800);
    }

    /// @dev Reverts when minUpdateInterval is zero.
    function testConstructorZeroMinUpdateInterval() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 500, 900, 0, 1800);
    }

    /// @dev Reverts when minTwapWindow > minUpdateInterval.
    function testConstructorMinTwapExceedsUpdateInterval() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 500, 1000, 500, 1800);
    }

    /// @dev Reverts when minTwapWindow > maxStaleness.
    function testConstructorStalenessOverflow() public {
        vm.expectRevert();
        new BalancerPriceOracle(address(vault), poolId, olas, 500, 1000, 1000, 500);
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
        new BalancerPriceOracle(address(vault), badPoolId, olas, 500, 900, 900, 1800);
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
        new BalancerPriceOracle(address(vault), triPoolId, olas, 500, 900, 900, 1800);
    }

    /// @dev Direction is 0 when OLAS is tokens[1].
    function testConstructorDirection0() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 500, 900, 900, 1800);
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

        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), reversePoolId, olas, 500, 900, 900, 1800);
        assertEq(o.direction(), 1);
    }

    /// @dev Immutable values are stored correctly.
    function testConstructorImmutables() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 500, 900, 900, 1800);
        assertEq(o.maxSlippageBps(), 500);
        assertEq(o.minTwapWindow(), 900);
        assertEq(o.minUpdateInterval(), 900);
        assertEq(o.maxStaleness(), 1800);
        assertEq(o.balancerVault(), address(vault));
        assertEq(o.balancerPoolId(), poolId);
    }

    /// @dev Observations are initialized to zero at construction time.
    function testConstructorBootstrapsObservations() public {
        BalancerPriceOracle o = new BalancerPriceOracle(address(vault), poolId, olas, 500, 900, 900, 1800);
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
            maxSlippageBps, minTwapWindow, minUpdateInterval, maxStaleness
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

contract BalancerPriceOracleValidatePriceTest is BalancerOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Reverts when slippage exceeds maxSlippageBps.
    function testValidatePriceSlippageOverflow() public {
        vm.expectRevert();
        oracle.validatePrice(maxSlippageBps + 1);
    }

    /// @dev Reverts when last observation is too stale.
    function testValidatePriceStaleness() public {
        // Do one update to create a real observation
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Warp past maxStaleness
        vm.warp(block.timestamp + maxStaleness + 1);

        vm.expectRevert();
        oracle.validatePrice(maxSlippageBps);
    }

    /// @dev Reverts when only one observation exists (prev.timestamp == 0).
    function testValidatePriceNotFullyInitialized() public {
        // After one update, prev.timestamp is still 0 (from constructor default)
        oracle.updatePrice();

        // validatePrice reverts with ZeroValue because prev.timestamp == 0
        vm.expectRevert();
        oracle.validatePrice(maxSlippageBps);
    }

    /// @dev Validates successfully with constant price.
    function testValidatePriceConstantPrice() public {
        // First update
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Warp to get enough TWAP window from prevObservation (construction time)
        // Total elapsed from construction: minUpdateInterval + more
        vm.warp(block.timestamp + minTwapWindow);
        // Second update to keep observation fresh
        oracle.updatePrice();

        // Now validate - spot == twap since price never changed
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Validates with zero slippage when price is constant.
    function testValidatePriceZeroSlippageConstant() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        bool valid = oracle.validatePrice(0);
        assertTrue(valid);
    }

    /// @dev Validates within tolerance after small price change.
    function testValidatePriceSmallChangeWithinSlippage() public {
        // First update at price 1e18
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Second update still at price 1e18 to establish TWAP baseline
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Small price change: 10000 WETH, 10200 OLAS => price = 1.02e18 (2% change)
        _setBalances(10_000 ether, 10_200 ether);

        // Validate immediately (within maxStaleness)
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Fails validation after large price change.
    function testValidatePriceLargeChangeExceedsSlippage() public {
        // Build up TWAP at price 1e18
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Large price change: 5000 WETH, 10000 OLAS => price = 2e18 (100% change)
        _setBalances(5000 ether, 10_000 ether);

        // With 5% max slippage, a 100% change vs recent TWAP should fail
        // TWAP is weighted avg over window, most of it at price 1e18
        // So spot=2e18 diverges from twap significantly
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertFalse(valid);
    }

    /// @dev Passes with high slippage tolerance after price change.
    function testValidatePriceLargeChangeHighSlippage() public {
        // Deploy oracle with high max slippage
        BalancerPriceOracle highSlippageOracle = new BalancerPriceOracle(
            address(vault), poolId, olas,
            10_000, // 100% max slippage
            minTwapWindow, minUpdateInterval, maxStaleness
        );

        vm.warp(block.timestamp + minUpdateInterval);
        highSlippageOracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        highSlippageOracle.updatePrice();

        // Large price change
        _setBalances(5000 ether, 10_000 ether);

        bool valid = highSlippageOracle.validatePrice(10_000);
        assertTrue(valid);
    }

    /// @dev Rolling window adapts: TWAP tracks price changes over time.
    function testValidatePriceRollingWindowAdaptation() public {
        // First update at price 1e18
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        // Change price to 2e18
        _setBalances(5000 ether, 10_000 ether);

        // Multiple updates at new price to shift TWAP
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Now TWAP should have adapted significantly toward 2e18
        // With 5% slippage, it should now pass
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Fuzz: any valid slippage works with constant price.
    function testFuzzValidatePriceConstant(uint256 slippage) public {
        slippage = bound(slippage, 0, maxSlippageBps);

        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        bool valid = oracle.validatePrice(slippage);
        assertTrue(valid);
    }

    /// @dev Fuzz: slippage > maxSlippageBps always reverts.
    function testFuzzValidatePriceSlippageOverflow(uint256 slippage) public {
        slippage = bound(slippage, maxSlippageBps + 1, type(uint256).max);

        vm.expectRevert();
        oracle.validatePrice(slippage);
    }

    /// @dev Validates right at maxStaleness boundary.
    function testValidatePriceAtStalenessLimit() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        // Warp to exact maxStaleness boundary
        vm.warp(block.timestamp + maxStaleness);
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Reverts at one second past maxStaleness.
    function testValidatePriceJustPastStaleness() public {
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();

        vm.warp(block.timestamp + minTwapWindow);
        oracle.updatePrice();

        vm.warp(block.timestamp + maxStaleness + 1);
        vm.expectRevert();
        oracle.validatePrice(maxSlippageBps);
    }

    /// @dev Tests that prevObservation and lastObservation correctly participate in TWAP.
    function testValidatePriceTwapCalculation() public {
        // Observations start at (0, 0)
        uint256 dt = minUpdateInterval;

        // First update (bypasses rate limit since lastObservation.timestamp == 0)
        oracle.updatePrice();
        // prev=(0,0), last=(1e18*block.timestamp, block.timestamp)

        // Warp past minUpdateInterval for second update
        vm.warp(block.timestamp + dt);

        // Change price to 2e18
        _setBalances(5000 ether, 10_000 ether);

        // Second update at price 2e18
        oracle.updatePrice();

        // Third update to ensure fresh observation for validation
        vm.warp(block.timestamp + dt);
        oracle.updatePrice();

        // Validate — spot = 2e18, TWAP should converge toward 2e18 over time
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }
}
