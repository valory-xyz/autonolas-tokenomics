// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {Bridge2BurnerOptimism} from "../contracts/utils/Bridge2BurnerOptimism.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";
import {LiquidityManagerBalancerUniV3} from "../contracts/pol/LiquidityManagerBalancerUniV3.sol";
import {LiquidityManagerProxy} from "../contracts/proxies/LiquidityManagerProxy.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {Test, console} from "forge-std/Test.sol";

// Balancer vault (source)
interface IBalancer {
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

// Uniswap V3 factory (target)
interface IUniV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

// Uniswap V3 NonfungiblePositionManager (target) — fee-tier indexed
interface INPMMint {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    function balanceOf(address owner) external view returns (uint256);
}

// Uniswap V3 SwapRouter (target)
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

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title LiquidityManagerBalancerUniV3 — Base fork test (Balancer V2 source -> Uniswap V3 target)
/// @dev Proves the new composition end-to-end on a Base fork: it withdraws protocol-owned liquidity from the
///      real OLAS/WETH Balancer pool (the Balancer-source mixin, already fork-proven on Base) and mints it into
///      a canonical Uniswap V3 position (the UniV3-target mixin, already fork-proven on ETH). Only the two
///      halves running together in one convertToV3 is new. Self-skips off a Base fork (chainid != 8453).
contract LiquidityManagerBalancerUniV3BaseTest is Test {
    BalancerPriceOracle internal oracleV2;
    Bridge2BurnerOptimism internal bridge2Burner;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerBalancerUniV3 internal liquidityManager;

    uint160 internal sqrtPriceX96;
    uint256[2] internal initialAmounts;

    address internal constant OLAS = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address[] internal TOKENS = [WETH, OLAS];
    address internal constant TIMELOCK = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant L2_TOKEN_RELAYER = 0x4200000000000000000000000000000000000010;
    // Real OLAS/WETH Balancer pool on Base (source)
    address internal constant POOL_V2 = 0x2da6e67C45aF2aaA539294D9FA27ea50CE4e2C5f;
    bytes32 internal constant POOL_V2_BYTES32 = 0x2da6e67c45af2aaa539294d9fa27ea50ce4e2c5f0002000000000000000001a3;
    address internal constant BPT_HOLDER = 0x4eDB5dd988b78B40E1b38592A4761F694E05ef05;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // Canonical Uniswap V3 on Base (target)
    address internal constant FACTORY_V3 = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address internal constant POSITION_MANAGER_V3 = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant ROUTER_V3 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    uint16 internal constant observationCardinality = 60;
    uint256 internal constant maxSlippageBps = 5000;
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 900;
    // Uniswap V3 fee tier 3000 -> tick spacing 60
    int24 internal constant FEE_TIER = 3000;
    int24 internal constant TICK_SPACING = 60;

    function setUp() public {
        // Only run on a Base mainnet fork
        if (block.chainid != 8453) {
            return;
        }

        // Deploy the Balancer-source TWAP oracle and warm it (two observations)
        oracleV2 = new BalancerPriceOracle(
            BALANCER_VAULT, POOL_V2_BYTES32, OLAS, minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds
        );
        oracleV2.updatePrice();
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracleV2.updatePrice();

        bridge2Burner = new Bridge2BurnerOptimism(OLAS, L2_TOKEN_RELAYER);
        neighborhoodScanner = new NeighborhoodScanner();

        // Deploy the new Balancer -> UniV3 manager behind the proxy
        LiquidityManagerBalancerUniV3 impl = new LiquidityManagerBalancerUniV3(
            OLAS, TIMELOCK, POSITION_MANAGER_V3, address(neighborhoodScanner), observationCardinality,
            BALANCER_VAULT, address(bridge2Burner)
        );
        bytes memory initPayload = abi.encodeWithSignature("initialize(uint16)", maxSlippageBps);
        LiquidityManagerProxy proxy = new LiquidityManagerProxy(address(impl), initPayload);
        liquidityManager = LiquidityManagerBalancerUniV3(address(proxy));

        // Move the real BPT into the manager (source liquidity for the convert under test)
        uint256 v2Liquidity = IToken(POOL_V2).balanceOf(BPT_HOLDER);
        vm.prank(BPT_HOLDER);
        IToken(POOL_V2).transfer(address(liquidityManager), v2Liquidity);

        // Price for the fresh UniV3 pool: token1/token0 from the Balancer pool balances (token0 = WETH < OLAS)
        (, uint256[] memory amounts,) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_V2_BYTES32);
        initialAmounts[0] = amounts[0];
        initialAmounts[1] = amounts[1];
        uint256 price = FixedPointMathLib.divWadDown(initialAmounts[1], initialAmounts[0]);
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Create + initialize the target UniV3 pool at that price
        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(WETH, OLAS, uint24(FEE_TIER), sqrtPriceX96);

        // Pre-warm so the fail-closed guard has a verifiable TWAP at convert time
        address pool = IUniV3Factory(FACTORY_V3).getPool(WETH, OLAS, uint24(FEE_TIER));
        _warmUpV3Pool(pool);
    }

    /// @dev Same pre-warm as the Slipstream Base suite, but against a canonical UniV3 pool: bump cardinality,
    ///      seed wide-range liquidity, write two observations spanning > SECONDS_AGO via tick-crossing round
    ///      trips, and interleave the Balancer oracle's updatePrice() so it does not go stale across the warp.
    function _warmUpV3Pool(address pool) internal {
        IUniswapV3(pool).increaseObservationCardinalityNext(observationCardinality);

        int24 centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 lower = ((centerTick - 30000) / TICK_SPACING) * TICK_SPACING;
        int24 upper = ((centerTick + 30000) / TICK_SPACING) * TICK_SPACING;
        uint256 seedWeth = 20 ether;
        uint256 seedOlas = 500_000 ether;
        deal(WETH, address(this), seedWeth);
        deal(OLAS, address(this), seedOlas);
        IToken(WETH).approve(POSITION_MANAGER_V3, seedWeth);
        IToken(OLAS).approve(POSITION_MANAGER_V3, seedOlas);
        (uint256 seedId, uint128 seedLiq,,) = INPMMint(POSITION_MANAGER_V3).mint(
            INPMMint.MintParams({
                token0: WETH,
                token1: OLAS,
                fee: uint24(FEE_TIER),
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: seedWeth,
                amount1Desired: seedOlas,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        vm.warp(block.timestamp + 1);
        _roundTrip();

        vm.warp(block.timestamp + 900);
        oracleV2.updatePrice();
        vm.warp(block.timestamp + 900);
        oracleV2.updatePrice();

        vm.warp(block.timestamp + 1);
        _roundTrip();

        // Remove the warm-up seed (observations persist at pool level, so the guard stays satisfiable)
        INPMMint(POSITION_MANAGER_V3).decreaseLiquidity(
            INPMMint.DecreaseLiquidityParams({
                tokenId: seedId,
                liquidity: seedLiq,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
        INPMMint(POSITION_MANAGER_V3).collect(
            INPMMint.CollectParams({
                tokenId: seedId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Sanity: both guards are satisfiable now
        liquidityManager.checkPoolAndGetCenterPrice(pool);
        oracleV2.getTWAP();
    }

    function _roundTrip() internal {
        uint256 olasOut = _swap(WETH, OLAS, 0.01 ether);
        vm.warp(block.timestamp + 1);
        _swap(OLAS, WETH, olasOut);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        deal(tokenIn, address(this), amountIn);
        IToken(tokenIn).approve(ROUTER_V3, amountIn);
        amountOut = IRouterV3(ROUTER_V3).exactInputSingle(
            IRouterV3.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: uint24(FEE_TIER),
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @dev End-to-end composition: withdraw the Balancer POL and mint it into a Uniswap V3 position, in one tx.
    function test_convertToV3_balancerToUniV3() public {
        if (block.chainid != 8453) {
            vm.skip(true);
            return;
        }

        address pool = IUniV3Factory(FACTORY_V3).getPool(WETH, OLAS, uint24(FEE_TIER));

        // Precondition: the manager holds the BPT (source) and no UniV3 position (target) yet
        assertGt(IToken(POOL_V2).balanceOf(address(liquidityManager)), 0, "manager should hold BPT pre-convert");
        assertEq(INPMMint(POSITION_MANAGER_V3).balanceOf(address(liquidityManager)), 0, "no position pre-convert");

        // Full-range-ish convert with the scanner enabled (feeTier selects UniV3 fee/tick spacing)
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;
        (uint256 positionId, uint256 liquidity, uint256[] memory amounts) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, FEE_TIER, tickShifts, 0, true);

        // The Balancer BPT was consumed (exited) and a UniV3 position was minted with real liquidity
        assertEq(IToken(POOL_V2).balanceOf(address(liquidityManager)), 0, "BPT should be fully exited");
        assertGt(positionId, 0, "position id");
        assertGt(liquidity, 0, "position liquidity");
        assertGt(amounts[0] + amounts[1], 0, "position amounts");
        assertEq(INPMMint(POSITION_MANAGER_V3).balanceOf(address(liquidityManager)), 1, "one UniV3 position held");

        // The minted position lives in the canonical UniV3 pool for this fee tier
        assertTrue(pool != address(0), "target pool exists");
    }
}
