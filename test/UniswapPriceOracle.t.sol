// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ZuniswapV2Factory} from "zuniswapv2/ZuniswapV2Factory.sol";
import {ZuniswapV2Router} from "zuniswapv2/ZuniswapV2Router.sol";
import {ZuniswapV2Pair} from "zuniswapv2/ZuniswapV2Pair.sol";
import {MockERC20} from "../lib/zuniswapv2/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";

contract UniswapOracleBaseSetup is Test {
    Utils internal utils;
    MockERC20 internal olas;
    MockERC20 internal dai;
    MockERC20 internal weth;
    ZuniswapV2Factory internal factory;
    ZuniswapV2Router internal router;
    UniswapPriceOracle internal oracle;

    address payable[] internal users;
    address internal deployer;
    address internal dev;
    address internal pair;
    address internal pairNoOlas;

    uint256 internal constant Q112 = 2 ** 112;
    uint256 internal initialMint = 100_000 ether;
    uint256 internal largeApproval = 1_000_000 ether;
    uint256 internal amountOLAS = 5_000 ether;
    uint256 internal amountDAI = 5_000 ether;

    uint256 internal maxSlippageBps = 500; // 5%
    uint256 internal minTwapWindow = 900; // 15 minutes
    uint256 internal minUpdateInterval = 900; // 15 minutes

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy tokens
        olas = new MockERC20("OLAS Token", "OLAS", 18);
        olas.mint(address(this), initialMint);
        dai = new MockERC20("DAI Token", "DAI", 18);
        dai.mint(address(this), initialMint);
        weth = new MockERC20("WETH Token", "WETH", 18);
        weth.mint(address(this), initialMint);

        // Deploy Uniswap
        factory = new ZuniswapV2Factory();
        router = new ZuniswapV2Router(address(factory));

        // Create OLAS-DAI pair and add liquidity
        olas.approve(address(router), largeApproval);
        dai.approve(address(router), largeApproval);
        router.addLiquidity(
            address(olas), address(dai),
            amountOLAS, amountDAI,
            amountOLAS, amountDAI,
            address(this)
        );
        pair = factory.pairs(address(olas), address(dai));

        // Create non-OLAS pair for wrong pool tests
        weth.approve(address(router), largeApproval);
        router.addLiquidity(
            address(dai), address(weth),
            1000 ether, 1000 ether,
            1000 ether, 1000 ether,
            address(this)
        );
        pairNoOlas = factory.pairs(address(dai), address(weth));

        // Deploy oracle
        oracle = new UniswapPriceOracle(pair, address(olas), maxSlippageBps, minTwapWindow, minUpdateInterval);
    }
}

contract UniswapPriceOracleConstructorTest is Test {
    MockERC20 internal olas;
    MockERC20 internal dai;
    MockERC20 internal weth;
    ZuniswapV2Factory internal factory;
    ZuniswapV2Router internal router;
    address internal pair;
    address internal pairNoOlas;

    function setUp() public {
        olas = new MockERC20("OLAS Token", "OLAS", 18);
        olas.mint(address(this), 100_000 ether);
        dai = new MockERC20("DAI Token", "DAI", 18);
        dai.mint(address(this), 100_000 ether);
        weth = new MockERC20("WETH Token", "WETH", 18);
        weth.mint(address(this), 100_000 ether);

        factory = new ZuniswapV2Factory();
        router = new ZuniswapV2Router(address(factory));

        olas.approve(address(router), type(uint256).max);
        dai.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);

        router.addLiquidity(address(olas), address(dai), 5000 ether, 5000 ether, 5000 ether, 5000 ether, address(this));
        pair = factory.pairs(address(olas), address(dai));

        router.addLiquidity(address(dai), address(weth), 1000 ether, 1000 ether, 1000 ether, 1000 ether, address(this));
        pairNoOlas = factory.pairs(address(dai), address(weth));
    }

    /// @dev Reverts when pair address is zero.
    function testConstructorZeroAddress() public {
        vm.expectRevert();
        new UniswapPriceOracle(address(0), address(olas), 500, 900, 900);
    }

    /// @dev Reverts when maxSlippageBps exceeds MAX_BPS.
    function testConstructorOverflowSlippage() public {
        vm.expectRevert();
        new UniswapPriceOracle(pair, address(olas), 10_001, 900, 900);
    }

    /// @dev Reverts when pair does not contain OLAS.
    function testConstructorWrongPool() public {
        vm.expectRevert();
        new UniswapPriceOracle(pairNoOlas, address(olas), 500, 900, 900);
    }

    /// @dev Succeeds with valid parameters and maxSlippageBps at boundary (MAX_BPS).
    function testConstructorMaxSlippage() public {
        UniswapPriceOracle o = new UniswapPriceOracle(pair, address(olas), 10_000, 900, 900);
        assertEq(o.maxSlippageBps(), 10_000);
    }

    /// @dev Reverts when minTwapWindow is zero.
    function testConstructorZeroMinTwapWindow() public {
        vm.expectRevert();
        new UniswapPriceOracle(pair, address(olas), 500, 0, 300);
    }

    /// @dev Reverts when minUpdateInterval is zero.
    function testConstructorZeroMinUpdateInterval() public {
        vm.expectRevert();
        new UniswapPriceOracle(pair, address(olas), 500, 900, 0);
    }

    /// @dev Reverts when minTwapWindow exceeds minUpdateInterval.
    function testConstructorMinTwapExceedsUpdateInterval() public {
        vm.expectRevert();
        new UniswapPriceOracle(pair, address(olas), 500, 900, 300);
    }

    /// @dev Direction is set correctly based on OLAS position in pair.
    function testConstructorDirection() public {
        UniswapPriceOracle o = new UniswapPriceOracle(pair, address(olas), 500, 900, 900);
        address token0 = ZuniswapV2Pair(pair).token0();
        if (token0 == address(olas)) {
            assertEq(o.direction(), 1);
        } else {
            assertEq(o.direction(), 0);
        }
    }

    /// @dev Immutable values are stored correctly.
    function testConstructorImmutables() public {
        UniswapPriceOracle o = new UniswapPriceOracle(pair, address(olas), 500, 900, 900);
        assertEq(o.pair(), pair);
        assertEq(o.maxSlippageBps(), 500);
        assertEq(o.minTwapWindow(), 900);
        assertEq(o.minUpdateInterval(), 900);
    }
}

contract UniswapPriceOracleGetPriceTest is UniswapOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Returns Q112 for equal reserves (1:1 price).
    function testGetPriceEqualReserves() public view {
        uint256 price = oracle.getPrice();
        assertEq(price, Q112);
    }

    /// @dev Price changes after a swap.
    function testGetPriceAfterSwap() public {
        uint256 priceBefore = oracle.getPrice();

        // Warp time so the pair can update cumulative prices
        vm.warp(block.timestamp + 100);

        // Swap DAI for OLAS to change reserves
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(olas);
        router.swapExactTokensForTokens(500 ether, 0, path, address(this));

        uint256 priceAfter = oracle.getPrice();
        // After buying OLAS with DAI: OLAS reserve decreases, DAI reserve increases
        // Price of DAI in OLAS terms (OLAS/DAI) should decrease
        assertLt(priceAfter, priceBefore);
    }
}

contract UniswapPriceOracleUpdatePriceTest is UniswapOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev First updatePrice call succeeds (no prior observation).
    function testUpdatePriceFirstCall() public {
        // Warp so there's a time diff from pair deployment for non-zero cumulative
        vm.warp(block.timestamp + 100);

        bool success = oracle.updatePrice();
        assertTrue(success);

        (uint256 cumulative, uint256 ts) = oracle.lastObservation();
        assertEq(ts, block.timestamp);
        assertGt(cumulative, 0);
    }

    /// @dev Second call within minUpdateInterval returns false.
    function testUpdatePriceRateLimited() public {
        oracle.updatePrice();

        // Try again immediately
        bool success = oracle.updatePrice();
        assertFalse(success);

        // Try again just before interval expires
        vm.warp(block.timestamp + minUpdateInterval - 1);
        success = oracle.updatePrice();
        assertFalse(success);
    }

    /// @dev Second call after minUpdateInterval succeeds.
    function testUpdatePriceAfterInterval() public {
        oracle.updatePrice();

        vm.warp(block.timestamp + minUpdateInterval);
        bool success = oracle.updatePrice();
        assertTrue(success);
    }

    /// @dev Emits ObservationUpdated event.
    function testUpdatePriceEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit UniswapPriceOracle.ObservationUpdated(address(this), 0, 0);
        oracle.updatePrice();
    }

    /// @dev Observation stores correct cumulative price from pair.
    function testUpdatePriceObservationValues() public {
        // Warp to create time difference from pair deployment
        uint256 warpTime = 1000;
        vm.warp(block.timestamp + warpTime);

        oracle.updatePrice();

        (uint256 cumulative, uint256 ts) = oracle.lastObservation();
        assertEq(ts, block.timestamp);
        // With equal reserves, cumulative should be Q112 * elapsed since pair's blockTimestampLast
        assertGt(cumulative, 0);
    }

    /// @dev Multiple updates correctly update the observation.
    function testUpdatePriceMultipleUpdates() public {
        oracle.updatePrice();
        (uint256 cumulative1, uint256 ts1) = oracle.lastObservation();

        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        (uint256 cumulative2, uint256 ts2) = oracle.lastObservation();

        assertGt(ts2, ts1);
        assertGt(cumulative2, cumulative1);
    }
}

contract UniswapPriceOracleValidatePriceTest is UniswapOracleBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Returns false when no observation has been recorded.
    function testValidatePriceNotInitialized() public view {
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertFalse(valid);
    }

    /// @dev Reverts when requested slippage exceeds maxSlippageBps.
    function testValidatePriceSlippageOverflow() public {
        vm.expectRevert();
        oracle.validatePrice(maxSlippageBps + 1);
    }

    /// @dev Returns false when TWAP window is too small.
    function testValidatePriceWindowTooSmall() public {
        oracle.updatePrice();

        // Warp less than minTwapWindow
        vm.warp(block.timestamp + minTwapWindow - 1);
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertFalse(valid);
    }

    /// @dev Validates successfully when price hasn't changed (constant price).
    function testValidatePriceConstantPrice() public {
        oracle.updatePrice();

        // Warp past the TWAP window
        vm.warp(block.timestamp + minTwapWindow + 1);

        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Validates with zero slippage when price hasn't changed.
    function testValidatePriceZeroSlippageConstant() public {
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        bool valid = oracle.validatePrice(0);
        assertTrue(valid);
    }

    /// @dev Validates with small swap (price within slippage tolerance).
    function testValidatePriceSmallSwapWithinSlippage() public {
        // Record observation at current price
        oracle.updatePrice();

        // Warp and do a small swap
        vm.warp(block.timestamp + minUpdateInterval);

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(olas);
        // Small swap: 50 DAI out of 5000 = 1%
        router.swapExactTokensForTokens(50 ether, 0, path, address(this));

        // Warp past TWAP window from initial observation
        vm.warp(block.timestamp + minTwapWindow);

        // With a tiny swap and TWAP smoothing, should still be within 5% slippage
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Fails validation after a large swap (price outside slippage tolerance).
    function testValidatePriceLargeSwapExceedsSlippage() public {
        // Record observation at current price
        oracle.updatePrice();

        // Warp past update interval and do a large swap
        vm.warp(block.timestamp + minUpdateInterval);

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(olas);
        // Large swap: 2000 DAI out of 5000 = 40% — will move the price significantly
        router.swapExactTokensForTokens(2000 ether, 0, path, address(this));

        // Update observation after swap to record the new cumulative price
        oracle.updatePrice();

        // Warp past TWAP window
        vm.warp(block.timestamp + minTwapWindow + 1);

        // Do another large swap in opposite direction to move spot away from TWAP
        path[0] = address(olas);
        path[1] = address(dai);
        olas.approve(address(router), largeApproval);
        router.swapExactTokensForTokens(1500 ether, 0, path, address(this));

        // Now spot price diverges significantly from the TWAP
        // With only 5% slippage tolerance, this should fail
        bool valid = oracle.validatePrice(maxSlippageBps);
        assertFalse(valid);
    }

    /// @dev Validates correctly at exact TWAP window boundary.
    function testValidatePriceExactWindowBoundary() public {
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow);

        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Validates with maximum allowed slippage.
    function testValidatePriceMaxSlippage() public {
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        bool valid = oracle.validatePrice(maxSlippageBps);
        assertTrue(valid);
    }

    /// @dev Fuzz test: any slippage in [0, maxSlippageBps] works with constant price.
    function testFuzzValidatePriceConstant(uint256 slippage) public {
        slippage = bound(slippage, 0, maxSlippageBps);

        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        bool valid = oracle.validatePrice(slippage);
        assertTrue(valid);
    }

    /// @dev Fuzz test: slippage > maxSlippageBps always reverts.
    function testFuzzValidatePriceSlippageOverflow(uint256 slippage) public {
        slippage = bound(slippage, maxSlippageBps + 1, type(uint256).max);

        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        vm.expectRevert();
        oracle.validatePrice(slippage);
    }
}
