pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LiquidityManagerETH} from "../contracts/pol/LiquidityManagerETH.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV2Pair} from "../contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";

interface ITreasury {
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success);
}

interface IRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract BaseSetup is Test {
    Utils internal utils;
    UniswapPriceOracle internal oracleV2;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerETH internal liquidityManager;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    uint256[2] internal initialAmounts;

    // Contract addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address[] internal TOKENS = [0x0001A500A6B18995B03f44bb040A5fFc28E45CB0, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2];
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant PAIR_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    bytes32 internal constant PAIR_V2_BYTES32 = 0x00000000000000000000000009D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant ROUTER_V3 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant POSITION_MANAGER_V3 = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint16 internal constant observationCardinality = 60;
    uint16 internal constant maxSlippage = 5000;
    int24 internal constant FEE_TIER = 3000;
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

        oracleV2 = new UniswapPriceOracle(WETH, uint256(maxSlippage / 100), PAIR_V2);
        neighborhoodScanner = new NeighborhoodScanner();
        liquidityManager = new LiquidityManagerETH(OLAS, TIMELOCK, POSITION_MANAGER_V3, address(neighborhoodScanner),
            observationCardinality, maxSlippage, address(oracleV2), ROUTER_V2);

        // Get V2 pool balance
        uint256 v2Liquidity = IToken(PAIR_V2).balanceOf(TREASURY);

        // Transfer V2 pool liquidity to LiquidityManager
        vm.prank(TIMELOCK);
        ITreasury(TREASURY).withdraw(address(liquidityManager), v2Liquidity, PAIR_V2);

        (initialAmounts[0], initialAmounts[1], ) = IUniswapV2Pair(PAIR_V2).getReserves();
        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
        uint256 price = FixedPointMathLib.divWadDown(initialAmounts[1], initialAmounts[0]);

        // Calculate the square root of the price ratio in X96 format
        uint160 sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Create V3 pool
        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(OLAS, WETH, uint24(FEE_TIER), sqrtPriceX96);
    }
}

contract LiquidityManagerETHTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testConvertToV3FullScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    function testConvertToV3Conversion95Scan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 500;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    function testConvertToV3FullNoScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = false;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // No scan = ticks are not optimized, deviation might not respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            // Increase DELTA by a factor of 50
            require(deviation <= DELTA * 50, "Price deviation too high");
        }
    }

    function testConvertToV3Conversion95ScanDecreaseLiquidityReposition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 1000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        console.log("Initial amounts[0]", initialAmounts[0]);
        console.log("Initial amounts[1]", initialAmounts[1]);

        // Convert V2 to V3
        (uint256 positionId, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);


        // Decrease liquidity
        olasBurnRate = 500;
        uint16 decreaseRate = 1000;
        uint256[] memory decreaseAmounts = new uint256[](2);
        // Since we decreased - decreaseAmountsOut must be <= decreaseAmounts
        decreaseAmounts[0] = (amountsOut[0] * decreaseRate) / MAX_BPS;
        decreaseAmounts[1] = (amountsOut[1] * decreaseRate) / MAX_BPS;
        console.log("Initial DECREASE amounts[0]", decreaseAmounts[0]);
        console.log("Initial DECREASE amounts[1]", decreaseAmounts[1]);

        (, uint256[] memory decreaseAmountsOut) =
            liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, decreaseRate, olasBurnRate);
        console.log("DECREASE amountsOut[0]", decreaseAmountsOut[0]);
        console.log("DECREASE amountsOut[1]", decreaseAmountsOut[1]);

        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((decreaseAmounts[i] - decreaseAmountsOut[i]), decreaseAmountsOut[i]);
            console.log(deviation);
            console.log(DELTA);
            require(deviation <= DELTA, "Price deviation too high");
        }


        // Change ranges
        initialAmounts[0] -= decreaseAmounts[0];
        initialAmounts[1] -= decreaseAmounts[1];

        tickShifts[0] = -40000;
        tickShifts[1] = 35000;
        uint256 newPositionId;
        (newPositionId, , amountsOut) = liquidityManager.changeRanges(TOKENS, FEE_TIER, tickShifts, scan);
        require(newPositionId != positionId, "Positions must be different");

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            console.log(deviation);
            console.log(DELTA);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

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
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        uint256 olasAmountToSwap = initialAmounts[0] / 10;
        // Fund deployer with OLAS
        deal(OLAS, deployer, olasAmountToSwap);

        // Approve tokens
        vm.startPrank(deployer);
        IToken(OLAS).approve(ROUTER_V3, olasAmountToSwap);

        IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: OLAS,
            tokenOut: WETH,
            fee: uint24(FEE_TIER),
            recipient: deployer,
            amountIn: olasAmountToSwap,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        IRouterV3(ROUTER_V3).exactInputSingle(params);
        vm.stopPrank();

        // Collect fees
        amountsOut = liquidityManager.collectFees(TOKENS, FEE_TIER);
        // OLAS collected fee must be > 0
        require(amountsOut[0] > 0);
    }
}
