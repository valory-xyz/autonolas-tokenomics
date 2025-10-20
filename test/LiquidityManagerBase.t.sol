pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LiquidityManagerOptimism} from "../contracts/pol/LiquidityManagerOptimism.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
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

interface ISlipstream {
    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param tickSpacing The desired tick spacing for the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool, as a Q64.96
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. The call will
    /// revert if the pool already exists, the tick spacing is invalid, or the token arguments are invalid
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
    external
    returns (address pool);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracleV2;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerOptimism internal liquidityManager;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    uint256[2] internal initialAmounts;
    uint160 internal sqrtPriceX96;
    address internal constant OLAS = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address[] internal TOKENS = [WETH, OLAS];
    address internal constant TIMELOCK = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant POOL_V2 = 0x2da6e67C45aF2aaA539294D9FA27ea50CE4e2C5f;
    bytes32 internal constant POOL_V2_BYTES32 = 0x2da6e67c45af2aaa539294d9fa27ea50ce4e2c5f0002000000000000000001a3;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant ROUTER_V3 = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address internal constant FACTORY_V3 = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address internal constant POSITION_MANAGER_V3 = 0x827922686190790b37229fd06084350E74485b72;
    uint16 internal constant observationCardinality = 60;
    uint16 internal constant maxSlippage = 5000;
    uint256 internal constant minUpdateTimePeriod = 900;
    int24 internal constant TICK_SPACING = 100;
    // Allowed rounding delta in 1e18 = 1%
    uint256 internal constant DELTA = 1e16;
    // Max bps value
    uint16 public constant MAX_BPS = 10_000;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        oracleV2 = new BalancerPriceOracle(OLAS, WETH, uint256(maxSlippage / 100), minUpdateTimePeriod, BALANCER_VAULT,
            POOL_V2_BYTES32);

        // Advance some time such that oracle has a time difference between last updated price
        vm.warp(block.timestamp + 100);

        neighborhoodScanner = new NeighborhoodScanner();
        liquidityManager = new LiquidityManagerOptimism(OLAS, TIMELOCK, POSITION_MANAGER_V3, address(neighborhoodScanner),
            observationCardinality, maxSlippage, address(oracleV2), BALANCER_VAULT, TIMELOCK);

        // Get pool total supply
        uint256 totalSupply = IToken(POOL_V2).totalSupply();

        // Mock liquidity transfer
        uint256 v2Liquidity = IToken(POOL_V2).balanceOf(0x4eDB5dd988b78B40E1b38592A4761F694E05ef05);
        vm.prank(0x4eDB5dd988b78B40E1b38592A4761F694E05ef05);
        IToken(POOL_V2).transfer(address(liquidityManager), v2Liquidity);

        (, uint256[] memory amounts, ) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_V2_BYTES32);
        initialAmounts[0] = amounts[0];
        initialAmounts[1] = amounts[1];
        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
        uint256 price = FixedPointMathLib.divWadDown(initialAmounts[1], initialAmounts[0]);

        // Calculate the square root of the price ratio in X96 format
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Create V3 pool
        ISlipstream(FACTORY_V3).createPool(WETH, OLAS, TICK_SPACING, sqrtPriceX96);

        // TODO Note that initial amount is smaller due to Balancer protocol fee
        // ProtocolFeesCollector::getSwapFeePercentage() ← [Return] 500000000000000000 [5e17]
        // Get V2 initial amounts on LiquidityManager
        initialAmounts[0] = (v2Liquidity * initialAmounts[0]) / totalSupply;
        initialAmounts[1] = (v2Liquidity * initialAmounts[1]) / totalSupply;
    }
}

contract LiquidityManagerBaseTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan.
    function testConvertToV3FullScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with 95% amount (5% of OLAS burn, 5% of WETH transferred) and optimized ticks scan.
    function testConvertToV3Conversion95Scan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 500;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        uint256 wethAmount = (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[0] = initialAmounts[0] - wethAmount;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and NO optimized ticks scan.
    function testConvertToV3FullNoScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = false;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // No scan = ticks are not optimized, deviation might not respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            // Increase DELTA by a factor of 50
            require(deviation <= DELTA * 50, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with 95% amount (5% of OLAS burn, 5% of WETH transferred) and optimized ticks scan,
    ///      then decrease liquidity and reposition to new ticks.
    function testConvertToV3Conversion95ScanDecreaseLiquidityReposition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 1000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        //console.log("Initial amounts[0]", initialAmounts[0]);
        //console.log("Initial amounts[1]", initialAmounts[1]);

        // Convert V2 to V3
        (uint256 positionId, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);


        // Decrease liquidity
        olasBurnRate = 500;
        uint16 decreaseRate = 1000;
        uint256[] memory decreaseAmounts = new uint256[](2);
        // Since we decreased - decreaseAmountsOut must be <= decreaseAmounts
        decreaseAmounts[0] = (amountsOut[0] * decreaseRate) / MAX_BPS;
        decreaseAmounts[1] = (amountsOut[1] * decreaseRate) / MAX_BPS;
        //console.log("Initial DECREASE amounts[0]", decreaseAmounts[0]);
        //console.log("Initial DECREASE amounts[1]", decreaseAmounts[1]);

        (, , uint256[] memory decreaseAmountsOut) =
            liquidityManager.decreaseLiquidity(TOKENS, TICK_SPACING, decreaseRate, olasBurnRate);
        //console.log("DECREASE amountsOut[0]", decreaseAmountsOut[0]);
        //console.log("DECREASE amountsOut[1]", decreaseAmountsOut[1]);

        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((decreaseAmounts[i] - decreaseAmountsOut[i]), decreaseAmountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }


        // Change ranges
        initialAmounts[0] -= decreaseAmounts[0];
        initialAmounts[1] -= decreaseAmounts[1];

        tickShifts[0] = -40000;
        tickShifts[1] = 35000;
        uint256 newPositionId;
        (newPositionId, , amountsOut) = liquidityManager.changeRanges(TOKENS, TICK_SPACING, tickShifts, scan);
        require(newPositionId != positionId, "Positions must be different");

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with 95% amount and optimized ticks scan, collect fees, swap, add again
    function testConvertToV3Conversion95ScanCollectFees() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 500;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        // Convert V2 to V3
        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        uint256 olasAmountToSwap = initialAmounts[0] / 10;
        // Fund deployer with OLAS
        deal(OLAS, deployer, olasAmountToSwap);

        // Approve tokens
        vm.startPrank(deployer);
        IToken(OLAS).approve(ROUTER_V3, olasAmountToSwap);

        ISlipstream.ExactInputSingleParams memory params = ISlipstream.ExactInputSingleParams({
            tokenIn: OLAS,
            tokenOut: WETH,
            tickSpacing: TICK_SPACING,
            recipient: deployer,
            deadline: block.timestamp + 1000,
            amountIn: olasAmountToSwap,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        uint256 wethOut = ISlipstream(ROUTER_V3).exactInputSingle(params);
        vm.stopPrank();

        // Collect fees
        amountsOut = liquidityManager.collectFees(TOKENS, TICK_SPACING);
        // OLAS collected fee must be > 0
        require(amountsOut[1] > 0);

        // Fund LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Convert to V3 again without a pair
        (, , amountsOut) =
            liquidityManager.convertToV3(TOKENS, 0, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // Fund more LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Increase liquidity
        (, , amountsOut) = liquidityManager.increaseLiquidity(TOKENS, TICK_SPACING, olasBurnRate);
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan, transfers position.
    function testConvertToV3FullScanTransferPosition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        liquidityManager.transferPositionId(TOKENS, TICK_SPACING, TIMELOCK);
    }

    /// @dev Fuzz: converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan,
    ///      safe tick shifts for deviation calculation.
    function testConvertToV3FullScanFuzz(uint24 lowerTickShift, uint24 upperTickShift) public {
        // Tick shifts: tick ± [5000, MAX_TICK]
        lowerTickShift = uint24(bound(lowerTickShift, 5000, 887272));
        upperTickShift = uint24(bound(upperTickShift, 5000, 887272));

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -int24(lowerTickShift);
        tickShifts[1] = int24(upperTickShift);
        uint16 olasBurnRate = 0;
        bool scan = true;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Fuzz: converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan,
    ///     any possible tick shifts without measuring deviation.
    function testConvertToV3FullScanFuzzAllRange(uint24 lowerTickShift, uint24 upperTickShift) public {
        // Tick shifts: tick ± [1, MAX_TICK]
        lowerTickShift = uint24(bound(lowerTickShift, 1, 887272));
        upperTickShift = uint24(bound(upperTickShift, 1, 887272));

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -int24(lowerTickShift);
        tickShifts[1] = int24(upperTickShift);

        uint16 olasBurnRate = 0;
        bool scan = true;

        liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);
    }
}
