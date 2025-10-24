pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {LiquidityManagerETH} from "../contracts/pol/LiquidityManagerETH.sol";
import {LiquidityManagerProxy} from "../contracts/proxies/LiquidityManagerProxy.sol";
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

    int24 internal centerTick;
    uint160 internal sqrtPriceX96;
    uint160 internal sqrtPriceX96ATH;
    uint160 internal sqrtPriceX96ATL;
    uint256[2] internal initialAmounts;

    // Contract addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address[] internal TOKENS = [OLAS, WETH];
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

    uint256 public constant OLAS_ETH_ATH_PRICE = 0.003624094951 ether;
    uint256 public constant OLAS_ETH_ATL_PRICE = 0.000020255298 ether;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy V2 oracle
        oracleV2 = new UniswapPriceOracle(WETH, uint256(maxSlippage / 100), PAIR_V2);

        // Deploy neighborhood scanner
        neighborhoodScanner = new NeighborhoodScanner();

        // Deploy LiquidityManagerETH implementation
        LiquidityManagerETH liquidityManagerImplementation = new LiquidityManagerETH(OLAS, TIMELOCK, POSITION_MANAGER_V3,
            address(neighborhoodScanner), observationCardinality, address(oracleV2), ROUTER_V2);

        // Deploy LiquidityManagerProxy
        bytes memory initPayload = abi.encodeWithSignature("initialize(uint16)", maxSlippage);
        LiquidityManagerProxy liquidityManagerProxy =
            new LiquidityManagerProxy(address(liquidityManagerImplementation), initPayload);

        // Wrap proxy into implementation
        liquidityManager = LiquidityManagerETH(address(liquidityManagerProxy));

        // Get V2 pool balance
        uint256 v2Liquidity = IToken(PAIR_V2).balanceOf(TREASURY);

        // Transfer V2 pool liquidity to LiquidityManager
        vm.prank(TIMELOCK);
        ITreasury(TREASURY).withdraw(address(liquidityManager), v2Liquidity, PAIR_V2);

        (initialAmounts[0], initialAmounts[1], ) = IUniswapV2Pair(PAIR_V2).getReserves();
        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
        uint256 price = FixedPointMathLib.divWadDown(initialAmounts[1], initialAmounts[0]);

        // Calculate the square root of the price ratio in X96 format
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Get center tick
        centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        // Create V3 pool
        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(OLAS, WETH, uint24(FEE_TIER), sqrtPriceX96);

        // Get V2 initial amounts on LiquidityManager
        uint256 totalSupply = IToken(PAIR_V2).totalSupply();
        initialAmounts[0] = (v2Liquidity * initialAmounts[0]) / totalSupply;
        initialAmounts[1] = (v2Liquidity * initialAmounts[1]) / totalSupply;

        // Get sqrt prices for OLAS ATH and ATL
        sqrtPriceX96ATH = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATH_PRICE) * (1 << 96)) / 1e9);
        sqrtPriceX96ATL = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATL_PRICE) * (1 << 96)) / 1e9);
    }
}

contract LiquidityManagerETHTest is BaseSetup {
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
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

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
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        uint256 wethAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - wethAmount;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        uint256 dust = initialAmounts[1] - amountsOut[1];
        wethAmount += dust;
        require(IToken(WETH).balanceOf(TIMELOCK) == wethAmount, "WETH transfer was not complete");
    }

    /// @dev Converts V2 pool into V3 with 50% amount (50% of OLAS burn, 50% of WETH transferred) and optimized ticks scan.
    function testConvertToV3Conversion50Scan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 5000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        uint256 wethAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - wethAmount;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        uint256 dust = initialAmounts[1] - amountsOut[1];
        wethAmount += dust;
        require(IToken(WETH).balanceOf(TIMELOCK) == wethAmount, "WETH transfer was not complete");
    }

    /// @dev Converts V2 pool into V3 with 50% amount and optimized ticks scan with tick shifts to OLAS ATH and ATL.
    function testConvertToV3Conversion50ScanATHATL() public {
        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        uint256 wethAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - wethAmount;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        uint256 dust = initialAmounts[1] - amountsOut[1];
        wethAmount += dust;
        require(IToken(WETH).balanceOf(TIMELOCK) == wethAmount, "WETH transfer was not complete");
    }

    /// @dev Converts V2 pool into V3 with 50% amount and optimized ticks scan with tick shifts to OLAS ATH / 2 and ATL / 2.
    function testConvertToV3Conversion50ScanATHATLDiv2() public {
        // Adjust sqrt prices with ATH / 2 and ATL / 2
        sqrtPriceX96ATH = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATH_PRICE / 2) * (1 << 96)) / 1e9);
        sqrtPriceX96ATL = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATL_PRICE / 2) * (1 << 96)) / 1e9);

        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        uint256 wethAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - wethAmount;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        uint256 dust = initialAmounts[1] - amountsOut[1];
        wethAmount += dust;
        require(IToken(WETH).balanceOf(TIMELOCK) == wethAmount, "WETH transfer was not complete");
    }

    /// @dev Converts V2 pool into V3 with 50% amount and optimized ticks scan with tick shifts to OLAS ATH / 2 and ATL * 2.
    function testConvertToV3Conversion50ScanATHDiv2ATLMul2() public {
        // Adjust sqrt prices with ATH / 2 and ATL / 2
        sqrtPriceX96ATH = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATH_PRICE / 2) * (1 << 96)) / 1e9);
        sqrtPriceX96ATL = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATL_PRICE * 2) * (1 << 96)) / 1e9);

        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        uint256 wethAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - wethAmount;

        (, , uint256[] memory amountsOut) =
                            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        uint256 dust = initialAmounts[1] - amountsOut[1];
        wethAmount += dust;
        require(IToken(WETH).balanceOf(TIMELOCK) == wethAmount, "WETH transfer was not complete");
    }

    /// @dev Converts V2 pool into V3 with 50% amount WITHOUT optimized ticks scan with tick shifts to OLAS ATH and ATL.
    function testConvertToV3Conversion50NoScanATHATL() public {
        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = false;

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);
    }

    /// @dev Converts V2 pool into V3 with 50% amount WITHOUT optimized ticks scan with tick shifts to OLAS ATH / 2 and ATL / 2.
    function testConvertToV3Conversion50NoScanATHATLDiv2() public {
        // Adjust sqrt prices with ATH / 2 and ATL / 2
        sqrtPriceX96ATH = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATH_PRICE / 2) * (1 << 96)) / 1e9);
        sqrtPriceX96ATL = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATL_PRICE / 2) * (1 << 96)) / 1e9);

        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = false;

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);
    }

    /// @dev Converts V2 pool into V3 with 50% amount WITHOUT optimized ticks scan with tick shifts to OLAS ATH / 2 and ATL * 2.
    function testConvertToV3Conversion50NoScanATHDiv2ATLMul2() public {
        // Adjust sqrt prices with ATH / 2 and ATL / 2
        sqrtPriceX96ATH = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATH_PRICE / 2) * (1 << 96)) / 1e9);
        sqrtPriceX96ATL = uint160((FixedPointMathLib.sqrt(OLAS_ETH_ATL_PRICE * 2) * (1 << 96)) / 1e9);

        int24 atlTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATL);
        require(centerTick > atlTick, "Center tick must be lower than ATL tick");

        int24 athTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96ATH);
        require(athTick > centerTick, "ATH tick must be lower than center tick");

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = atlTick - centerTick;
        tickShifts[1] = athTick - centerTick;

        uint16 olasBurnRate = 5000;
        bool scan = false;

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and NO optimized ticks scan.
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
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);


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
            liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, decreaseRate, olasBurnRate);
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
        (newPositionId, , amountsOut) = liquidityManager.changeRanges(TOKENS, FEE_TIER, tickShifts, scan);
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
        uint256 wethOut = IRouterV3(ROUTER_V3).exactInputSingle(params);
        vm.stopPrank();

        // Collect fees
        amountsOut = liquidityManager.collectFees(TOKENS, FEE_TIER);
        // OLAS collected fee must be > 0
        require(amountsOut[0] > 0);

        // Fund LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Convert to V3 again without a pair
        (, , amountsOut) =
            liquidityManager.convertToV3(TOKENS, 0, FEE_TIER, tickShifts, olasBurnRate, scan);

        // Fund more LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Increase liquidity
        (, , amountsOut) = liquidityManager.increaseLiquidity(TOKENS, FEE_TIER, olasBurnRate);
    }

    /// @dev 1% existing pool with wrong sqrtP that calculates center price as MIN_TICK - extreme boundary case.
    function testConvertToV3Full10kPool() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = false;
        int24 feeTier = 10_000;

        // Liquidity will be zero
        vm.expectRevert(bytes("ZeroValue()"));
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, feeTier, tickShifts, olasBurnRate, scan);

        scan = true;

        // Same wiht scan argument
        vm.expectRevert(bytes("ZeroValue()"));
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, feeTier, tickShifts, olasBurnRate, scan);
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan, transfers position.
    function testConvertToV3FullScanTransferPosition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        liquidityManager.transferPositionId(TOKENS, FEE_TIER, TIMELOCK);
    }

    /// @dev Error scenarios.
    function testConvertToV3Errors() public {
        int24[] memory tickShifts = new int24[](2);
        uint16 olasBurnRate = 0;
        bool scan = true;

        // Tick shifts cause same entry prices
        vm.expectRevert();
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

        tickShifts[0] = -27000;
        tickShifts[1] = 17000;

        // No tokens are available
        vm.expectRevert();
        liquidityManager.convertToV3(TOKENS, 0, FEE_TIER, tickShifts, olasBurnRate, scan);

        // OLAS burn rate is too high
        vm.expectRevert();
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 10_001, scan);

        // Pool does not exist
        vm.expectRevert();
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, 10, tickShifts, olasBurnRate, scan);

        // Decrease rate is zero
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, 0, olasBurnRate);

        // Decrease rate is too big
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, 10_001, olasBurnRate);

        uint16 decreaseRate = 1_000;
        // OLAS burn rate is too big
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, decreaseRate, 10_001);

        // Pool does not exist
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, 10, decreaseRate, olasBurnRate);

        // No position to work with
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, decreaseRate, olasBurnRate);

        // OLAS burn rate is too big
        vm.expectRevert();
        liquidityManager.increaseLiquidity(TOKENS, FEE_TIER, 10_001);

        // No available amounts
        vm.expectRevert();
        liquidityManager.increaseLiquidity(TOKENS, FEE_TIER, olasBurnRate);

        // Fund LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), initialAmounts[0]);
        deal(WETH, address(liquidityManager), initialAmounts[1]);

        // Pool is not found
        vm.expectRevert();
        liquidityManager.increaseLiquidity(TOKENS, 10, olasBurnRate);

        // Position does not exist
        vm.expectRevert();
        liquidityManager.increaseLiquidity(TOKENS, FEE_TIER, olasBurnRate);

        // Position does not exist
        vm.expectRevert();
        liquidityManager.increaseLiquidity(TOKENS, FEE_TIER, olasBurnRate);

        // Pool does not exist
        vm.expectRevert();
        liquidityManager.changeRanges(TOKENS, 10, tickShifts, scan);

        // Position does not exist
        vm.expectRevert();
        liquidityManager.changeRanges(TOKENS, FEE_TIER, tickShifts, scan);

        // No position available
        vm.expectRevert();
        liquidityManager.transferPositionId(TOKENS, FEE_TIER, TIMELOCK);

        // No token available
        vm.expectRevert();
        liquidityManager.transferToken(OLAS, TIMELOCK, initialAmounts[0] + 1);
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
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);

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

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, olasBurnRate, scan);
    }
}
