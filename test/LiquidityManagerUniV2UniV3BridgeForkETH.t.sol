// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV2Pair} from "../contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";
import {LiquidityManagerUniV2UniV3Bridge} from "../contracts/pol/LiquidityManagerUniV2UniV3Bridge.sol";
import {LiquidityManagerProxy} from "../contracts/proxies/LiquidityManagerProxy.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";

interface ITreasury {
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success);
}

interface IFactory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

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
        external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function balanceOf(address owner) external view returns (uint256);
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
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title LiquidityManagerUniV2UniV3Bridge — ETH fork test (Uniswap V2 source -> Uniswap V3 target, L2-burn variant)
/// @dev Proves the new composition end-to-end: it withdraws the real OLAS/WETH Uniswap V2 POL and mints it into
///      a Uniswap V3 position via convertToV3, and — unlike LiquidityManagerUniV2UniV3 (L1 direct burn) — routes
///      the burned OLAS to a Bridge2Burner (the BurnViaBridge mixin). Both halves are already fork-proven
///      (UniV2->UniV3 on ETH, BurnViaBridge on Base via Slipstream); only the three-mixin composition is new.
///      Forks ETH mainnet (its real OLAS/WETH V2 pair) as a convenient stand-in for the eventual L2 (Celo)
///      deployment — the composition is chain-agnostic. Self-skips off a mainnet fork.
contract LiquidityManagerUniV2UniV3BridgeForkETHTest is Test {
    UniswapPriceOracle internal oracleV2;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerUniV2UniV3Bridge internal liquidityManager;

    int24 internal centerTick;
    uint160 internal sqrtPriceX96;

    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address[] internal TOKENS = [OLAS, WETH];
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant PAIR_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    bytes32 internal constant PAIR_V2_BYTES32 = 0x00000000000000000000000009D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant ROUTER_V3 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant FACTORY_V3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant POSITION_MANAGER_V3 = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    // Stand-in Bridge2Burner: the L2 variant just transfers OLAS here; any non-zero sink proves the path.
    address internal constant BRIDGE_2_BURNER = 0x000000000000000000000000000000000000B2B2;

    uint16 internal constant observationCardinality = 60;
    uint256 internal constant maxSlippageBps = 5000;
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 86400;
    int24 internal constant FEE_TIER = 3000;
    int24 internal constant TICK_SPACING = 60;

    function setUp() public {
        if (block.chainid != 1) {
            return;
        }

        oracleV2 = new UniswapPriceOracle(PAIR_V2, OLAS, minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds);
        oracleV2.updatePrice();
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracleV2.updatePrice();

        neighborhoodScanner = new NeighborhoodScanner();

        // Deploy the new UniV2 -> UniV3 L2-burn manager behind the proxy (treasury = TIMELOCK on this fork)
        LiquidityManagerUniV2UniV3Bridge impl = new LiquidityManagerUniV2UniV3Bridge(
            OLAS, TIMELOCK, POSITION_MANAGER_V3, address(neighborhoodScanner), observationCardinality,
            ROUTER_V2, BRIDGE_2_BURNER
        );
        bytes memory initPayload = abi.encodeWithSignature("initialize(uint16)", maxSlippageBps);
        LiquidityManagerProxy proxy = new LiquidityManagerProxy(address(impl), initPayload);
        liquidityManager = LiquidityManagerUniV2UniV3Bridge(address(proxy));

        // Move the real V2 LP into the manager (source liquidity)
        uint256 v2Liquidity = IToken(PAIR_V2).balanceOf(TREASURY);
        vm.prank(TIMELOCK);
        ITreasury(TREASURY).withdraw(address(liquidityManager), v2Liquidity, PAIR_V2);

        // Price for the fresh UniV3 pool from the V2 reserves (token0 = OLAS < WETH by address)
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(PAIR_V2).getReserves();
        uint256 price = FixedPointMathLib.divWadDown(uint256(r1), uint256(r0));
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);
        centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(OLAS, WETH, uint24(FEE_TIER), sqrtPriceX96);
        _warmUpV3Pool(IFactory(FACTORY_V3).getPool(OLAS, WETH, uint24(FEE_TIER)));
    }

    /// @dev Same pre-warm as the UniV2UniV3 ETH suite: bump cardinality, seed wide-range liquidity, write two
    ///      observations spanning > SECONDS_AGO via tick-crossing round trips so the fail-closed guard passes.
    function _warmUpV3Pool(address pool) internal {
        IUniswapV3(pool).increaseObservationCardinalityNext(observationCardinality);

        int24 lower = ((centerTick - 30000) / TICK_SPACING) * TICK_SPACING;
        int24 upper = ((centerTick + 30000) / TICK_SPACING) * TICK_SPACING;
        uint256 seedOlas = 100_000 ether;
        uint256 seedWeth = 20 ether;
        deal(OLAS, address(this), seedOlas);
        deal(WETH, address(this), seedWeth);
        IToken(OLAS).approve(POSITION_MANAGER_V3, seedOlas);
        IToken(WETH).approve(POSITION_MANAGER_V3, seedWeth);
        INPMMint(POSITION_MANAGER_V3).mint(
            INPMMint.MintParams({
                token0: OLAS,
                token1: WETH,
                fee: uint24(FEE_TIER),
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: seedOlas,
                amount1Desired: seedWeth,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        vm.warp(block.timestamp + 1);
        _roundTrip();
        vm.warp(block.timestamp + 1801);
        _roundTrip();

        liquidityManager.checkPoolAndGetCenterPrice(pool);
    }

    function _roundTrip() internal {
        uint256 wethOut = _swap(OLAS, WETH, 1000 ether);
        vm.warp(block.timestamp + 1);
        _swap(WETH, OLAS, wethOut);
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

    /// @dev End-to-end: withdraw the UniV2 POL, mint into a UniV3 position, and burn leftover OLAS to the
    ///      bridge (not locally) — proving SourceUniV2 + TargetUniV3 + BurnViaBridge compose in one tx.
    function test_convertToV3_univ2ToUniV3_viaBridge() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        assertGt(IToken(PAIR_V2).balanceOf(address(liquidityManager)), 0, "manager should hold V2 LP pre-convert");
        assertEq(INPMMint(POSITION_MANAGER_V3).balanceOf(address(liquidityManager)), 0, "no position pre-convert");
        uint256 bridgeBefore = IToken(OLAS).balanceOf(BRIDGE_2_BURNER);

        // Convert with a 10% OLAS "utilization" rate so the BurnViaBridge path is exercised: 10% of the
        // removed OLAS is routed to the bridge burner (not OLAS.burn()) and the remaining 90% is minted.
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;
        (uint256 positionId, uint256 liquidity, uint256[] memory amounts) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 1000, true);

        assertEq(IToken(PAIR_V2).balanceOf(address(liquidityManager)), 0, "V2 LP should be fully removed");
        assertGt(positionId, 0, "position id");
        assertGt(liquidity, 0, "position liquidity");
        assertGt(amounts[0] + amounts[1], 0, "position amounts");
        assertEq(INPMMint(POSITION_MANAGER_V3).balanceOf(address(liquidityManager)), 1, "one UniV3 position held");

        // The L2-burn path sent leftover OLAS to the bridge burner (BurnViaBridge), not to OLAS.burn().
        assertGt(IToken(OLAS).balanceOf(BRIDGE_2_BURNER), bridgeBefore, "leftover OLAS bridged to the burner");
    }
}
