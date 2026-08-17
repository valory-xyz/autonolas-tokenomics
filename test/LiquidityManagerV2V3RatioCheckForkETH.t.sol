// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV2Pair} from "../contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";
import {LiquidityManagerUniV2UniV3} from "../contracts/pol/LiquidityManagerUniV2UniV3.sol";
import {RatioDeviation} from "../contracts/pol/LiquidityManagerCore.sol";
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

interface IRouterV2 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @title LiquidityManager source-side ratio cross-check — ETH fork integration test (issue #324)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @dev Exercises the PRODUCTION cross-check that replaces the source-side TWAP oracle: `convertToV3` compares the
///      ratio of the V2-removed tokens against the gate-verified V3 slot0 price and reverts (RatioDeviation) when
///      the source pool was manipulated. Runs the real deployed path — deploy the (oracle-free) LiquidityManager
///      behind its proxy, seed/warm the OLAS/WETH V3 pool at the live V2 price, move the real V2 POL in, then:
///        • test_honestConvert_passes            — an un-manipulated convert mints a V3 position (ratio ~0 bps off).
///        • test_manipulatedV2_reverts           — a real front-run swap on the V2 pair skews the removed ratio and
///                                                  the convert reverts with RatioDeviation.
///        • test_toleranceBoundary_measured      — sweeps manipulation sizes and logs the divergence, showing the
///                                                  5% (500 bps) tolerance cleanly separates honest flow from a
///                                                  meaningful sandwich (honest 0 bps; ~7+ WETH swaps exceed 500).
///
/// TOLERANCE CHOICE (`maxSlippage = 500` bps). There is no live OLAS V2↔V3 basis to measure (OLAS is not seeded on
/// a V3 pool anywhere — that is what POL migration creates), so the tolerance is set from first principles and
/// demonstrated here on a fork-seeded pool. Ceiling on the honest V2↔V3 gap: the V3 slot0 is gate-guaranteed within
/// 2% of the V3 TWAP (MAX_ALLOWED_DEVIATION), and an honest V2 spot sits within ~1% of the true price (arb/fee
/// band), so an honest removal diverges at most ~3% from the V3 reference. 5% clears that with margin while
/// rejecting any manipulation that moves the ratio >5%. Sub-5% residual manipulation is value-safe regardless
/// (constant-product convexity: a proportional removal is worth ≥ fair value at the true price). Self-skips off an
/// ETH mainnet fork.
contract LiquidityManagerV2V3RatioCheckForkETHTest is Test {
    NeighborhoodScanner internal scanner;
    LiquidityManagerUniV2UniV3 internal liquidityManager;

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

    uint16 internal constant observationCardinality = 60;
    // The proposed production tolerance under evaluation in #324.
    uint16 internal constant maxSlippageBps = 500;
    int24 internal constant FEE_TIER = 3000;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    function setUp() public {
        if (block.chainid != 1) {
            return;
        }

        scanner = new NeighborhoodScanner();

        // Deploy the oracle-free LiquidityManager behind its proxy, initialized with the proposed 5% tolerance.
        LiquidityManagerUniV2UniV3 impl = new LiquidityManagerUniV2UniV3(
            OLAS, TIMELOCK, POSITION_MANAGER_V3, address(scanner), observationCardinality, ROUTER_V2
        );
        bytes memory initPayload = abi.encodeWithSignature("initialize(uint16)", maxSlippageBps);
        LiquidityManagerProxy proxy = new LiquidityManagerProxy(address(impl), initPayload);
        liquidityManager = LiquidityManagerUniV2UniV3(address(proxy));

        // Move the real V2 LP into the manager (source liquidity).
        uint256 v2Liquidity = IToken(PAIR_V2).balanceOf(TREASURY);
        vm.prank(TIMELOCK);
        ITreasury(TREASURY).withdraw(address(liquidityManager), v2Liquidity, PAIR_V2);

        // Seed + warm the V3 pool at the live V2 price (token0 = OLAS < WETH by address).
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(PAIR_V2).getReserves();
        uint256 price = FixedPointMathLib.divWadDown(uint256(r1), uint256(r0));
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);
        centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(OLAS, WETH, uint24(FEE_TIER), sqrtPriceX96);
        _warmUpV3Pool(IFactory(FACTORY_V3).getPool(OLAS, WETH, uint24(FEE_TIER)));
    }

    // ── honest convert: removed ratio ~= V3 price, passes the cross-check ──
    function test_honestConvert_passes() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;
        (uint256 positionId, uint256 liquidity,) =
            liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 1000, true);

        assertGt(positionId, 0, "honest convert should mint a position");
        assertGt(liquidity, 0, "honest convert should add liquidity");
        assertEq(IToken(PAIR_V2).balanceOf(address(liquidityManager)), 0, "V2 LP fully removed");
        assertEq(INPMMint(POSITION_MANAGER_V3).balanceOf(address(liquidityManager)), 1, "one V3 position held");
    }

    // ── manipulated V2: a real front-run swap skews the removed ratio, convert reverts RatioDeviation ──
    function test_manipulatedV2_reverts() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        // Front-run: dump 30 WETH into the V2 pair (~272 WETH pool) — a large but plausible sandwich that moves
        // the spot far past the 5% tolerance. The V3 pool is untouched, so its gate-verified slot0 still reflects
        // the true price; the removed ratio no longer matches it.
        _swapV2(WETH, OLAS, 30 ether);

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;

        vm.expectPartialRevert(RatioDeviation.selector);
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 1000, true);
    }

    // ── measurement: where the 5% tolerance draws the line between honest flow and manipulation ──
    function test_toleranceBoundary_measured() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        uint160 v3Sqrt = _v3Slot0Sqrt();
        (uint256 r0, uint256 r1) = _v2Reserves();
        emit log_named_uint("honest removed-ratio vs V3 (bps)", _divergenceBps(r0, r1, v3Sqrt));

        uint256[4] memory swaps = [uint256(5 ether), 10 ether, 20 ether, 40 ether];
        for (uint256 i = 0; i < swaps.length; ++i) {
            uint256 snap = vm.snapshot();
            _swapV2(WETH, OLAS, swaps[i]);
            (uint256 sr0, uint256 sr1) = _v2Reserves();
            uint256 div = _divergenceBps(sr0, sr1, v3Sqrt);
            emit log_named_uint("WETH swapped into V2 (ether)", swaps[i] / 1 ether);
            emit log_named_uint("  -> removed-ratio vs V3 (bps)", div);
            emit log_named_uint("  -> rejected by 500 bps?", div > maxSlippageBps ? 1 : 0);
            vm.revertTo(snap);
        }

        // Honest flow is ~0 bps; a meaningful sandwich blows past the 500 bps tolerance.
        assertLt(_divergenceBps(r0, r1, v3Sqrt), 100, "honest basis should be tiny");
        uint256 snapBig = vm.snapshot();
        _swapV2(WETH, OLAS, 40 ether);
        (uint256 br0, uint256 br1) = _v2Reserves();
        assertGt(_divergenceBps(br0, br1, v3Sqrt), maxSlippageBps, "large sandwich must exceed the tolerance");
        vm.revertTo(snapBig);
    }

    // ───────────────────────────── helpers ─────────────────────────────

    /// @dev Same pre-warm as the other ETH suites: bump cardinality, seed wide-range liquidity, write two
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
        _roundTripV3();
        vm.warp(block.timestamp + 1801);
        _roundTripV3();

        liquidityManager.checkPoolAndGetCenterPrice(pool);
    }

    function _roundTripV3() internal {
        uint256 wethOut = _swapV3(OLAS, WETH, 1000 ether);
        vm.warp(block.timestamp + 1);
        _swapV3(WETH, OLAS, wethOut);
    }

    function _swapV3(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
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

    function _swapV2(address tokenIn, address tokenOut, uint256 amountIn) internal {
        deal(tokenIn, address(this), amountIn);
        IToken(tokenIn).approve(ROUTER_V2, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        IRouterV2(ROUTER_V2).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
    }

    function _v2Reserves() internal view returns (uint256 r0, uint256 r1) {
        (uint112 a, uint112 b,) = IUniswapV2Pair(PAIR_V2).getReserves();
        (r0, r1) = (uint256(a), uint256(b));
    }

    function _v3Slot0Sqrt() internal view returns (uint160 sqrtP) {
        (sqrtP,,,,,,) = IUniswapV3(IFactory(FACTORY_V3).getPool(OLAS, WETH, uint24(FEE_TIER))).slot0();
    }

    /// @dev Mirrors the contract's `_checkRemovedRatioAgainstV3`: divergence (bps) between the V2-removed ratio
    ///      (reserve-proportional == V2 spot) and the V3 slot0 price. Both are token1 per token0.
    function _divergenceBps(uint256 r0, uint256 r1, uint160 sqrtP) internal pure returns (uint256) {
        uint256 pV3 = FixedPointMathLib.mulDivDown(
            FixedPointMathLib.mulDivDown(uint256(sqrtP), uint256(sqrtP), Q96), 1e18, Q96);
        uint256 pV2 = FixedPointMathLib.mulDivDown(r1, 1e18, r0);
        uint256 diff = pV2 > pV3 ? pV2 - pV3 : pV3 - pV2;
        return (diff * 10000) / pV3;
    }
}
