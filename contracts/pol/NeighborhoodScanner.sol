// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {FullMath} from "../libraries/FullMath.sol";

/**
 * @title NeighborhoodScanner
 * @notice Binary-search helpers to pick Uniswap V3 ranges that minimize residuals ("dust")
 *         by preferring *narrowing* toward the current price:
 *         - pickHiPreferNarrow:   fix lo, find minimal hi
 *         - pickLoPreferNarrow:   fix hi, find maximal lo
 *
 * Theory (inside-range case, sa < sp < sb):
 *   amounts[0](L) = L * (sb - sp) / (sp * sb)
 *   amounts[1](L) = L * (sp - sa)
 * For a fixed L, amounts[0] is increasing in sb; amounts[1] is decreasing in sa.
 *
 * The routines below use that monotonicity to run a robust binary search on the
 * tick grid, privileging *narrower* ranges whenever multiple choices consume balances.
 *
 * Notes:
 * - These functions only do math (preview), they DO NOT mint liquidity.
 * - Caller should compare candidate solutions by a single numeraire (e.g., token1),
 *   e.g. value_used / value_total where value0_in_1 = amounts[0] * (sqrtP^2 / 2^192).
 */

/// @title Neighborhood Scanner - Smart contract for scanning neighborhood ticks to better fit liquidity
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract NeighborhoodScanner {
    enum Mode { HiPreferNarrow, LoPreferNarrow }

    // Max bps value
    uint16 public constant MAX_BPS = 10_000;
    // TODO Calculate steps - linear gas spending dependency
    uint8 public constant MAX_NUM_STEPS = 32;

    // ------------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------------

    /**
     * @notice Fix lo; find the MINIMAL hi (on the tick grid) such that the position
     *         can consume (approximately) the available token0, given L is limited by token1.
     *
     *         Preference: *narrowing from above* (closest-to-price hi that still works).
     *
     * Pre-conditions:
     *   - Inside-range mode: sqrtP > sa (price above lo).
     *   - 'maxUpTicks' bounds the search corridor above the current tick to avoid unbounded scans.
     *
     * @param tickSpacing   pool tick spacing
     * @param sqrtP         current sqrtPriceX96 (Q64.96)
     * @param loCandidate   lower tick candidate (will be snapped down to the grid)
     * @param amounts[0]       available token0 (b0)
     * @param amounts[1]       available token1 (b1)
     * @param maxUpTicks    corridor upwards from current tick (search cap)
     * @param tolAbs0       absolute tolerance in token0 (e.g., 1..10 wei)
     *
     * @return loBest   chosen lower tick (grid-aligned)
     * @return hiBest   chosen upper tick (grid-aligned)
     * @return Lbest    final liquidity (capped by b0/b1 due to rounding)
     * @return used0    preview amounts[0] actually consumed by Lbest in [loBest, hiBest]
     * @return used1    preview amounts[1] actually consumed by Lbest in [loBest, hiBest]
     */
    function pickHiPreferNarrow(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 loCandidate,
        uint256[] memory amounts,
        int24 maxUpTicks,
        uint256 tolAbs0
    )
    public
    pure
    returns (int24 loBest, int24 hiBest, uint128 Lbest, uint256 used0, uint256 used1)
    {
        require(amounts[0] > 0 || amounts[1] > 0, "NSB: zero balances");

        // Snap lo to grid and compute sa
        int24 lo = _roundDownToSpacing(loCandidate, tickSpacing);
        uint160 sa = TickMath.getSqrtRatioAtTick(lo);

        // Must be inside-range (price above lo)
        require(sqrtP > sa, "NSB: price <= lo");

        // Compute hi search corridor
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtP);

        // Minimal hi: one grid step above the price
        int24 hiMin = _roundUpToSpacing(currentTick + 1, tickSpacing);
        if (hiMin <= lo) hiMin = lo + tickSpacing;

        // Maximal hi: bounded upwards and clamped to MAX_TICK
        int24 hiMax = currentTick + maxUpTicks;
        if (hiMax > TickMath.MAX_TICK) hiMax = TickMath.MAX_TICK;
        hiMax = _roundDownToSpacing(hiMax, tickSpacing);
        if (hiMax <= hiMin) hiMax = hiMin + tickSpacing;

        uint160 sbMin = TickMath.getSqrtRatioAtTick(hiMin);
        uint160 sbMax = TickMath.getSqrtRatioAtTick(hiMax);

        // Liquidity limited by token1 in (sa, sqrtP): L1 = getLiquidityForAmount1(sa, sqrtP, b1)
        uint128 L1 = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
        if (L1 == 0) {
            // No token1 -> cannot place inside-range liquidity with fixed lo
            return (lo, hiMin, 0, 0, 0);
        }

        // need0 at corridor extremes with fixed L1
        (uint256 need0_min, /*uint256 need1_const*/) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMin, L1);
        (uint256 need0_max, /*uint256 _*/          ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMax, L1);

        // Case A: even at the *narrowest* hiMin, we already require too much token0 -> token0-limited.
        // Stick to the narrow edge (hiMin) and cap L by b0 as well.
        if (need0_min > amounts[0] + tolAbs0) {
            uint128 Lcap0_narrow = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbMin, amounts[0]);
            uint128 Lfin_narrow  = _min128(Lcap0_narrow, L1);
            if (Lfin_narrow == 0) return (lo, hiMin, 0, 0, 0);

            (uint256 u0n, uint256 u1n) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMin, Lfin_narrow);
            return (lo, hiMin, Lfin_narrow, u0n, u1n);
        }

        // Case B: even at the *widest* hiMax, token0 requirement is still below b0 -> token1-limited.
        // Prefer *narrowest* hi that works => pick hiMin.
        if (need0_max + tolAbs0 < amounts[0]) {
            uint128 Lcap0_narrow2 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbMin, amounts[0]);
            uint128 Lfin_narrow2  = _min128(Lcap0_narrow2, L1);
            (uint256 u0n2, uint256 u1n2) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMin, Lfin_narrow2);
            return (lo, hiMin, Lfin_narrow2, u0n2, u1n2);
        }

        // Case C: bracketed — run binary search for the MINIMAL hi such that need0(hi; L1) <= b0 (+ tol)
        int24 left  = hiMin; // valid: need0(left)  <= b0 + tol
        int24 right = hiMax; // valid: need0(right) >= b0 - tol

        uint8 it = 0;
        while (left < right && it++ < MAX_NUM_STEPS) {
            int24 mid = _midTickGridFloor(left, right, tickSpacing); // floor to grid
            if (mid <= left) break; // converged

            uint160 sbMid = TickMath.getSqrtRatioAtTick(mid);
            (uint256 need0_mid, ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMid, L1);

            if (need0_mid > amounts[0] + tolAbs0) {
                // need too much token0 -> range still too narrow -> move hi downward (closer to price)
                // In terms of ticks: we must *decrease* hi; hi lives in (left..mid-1]
                right = mid - tickSpacing;
            } else {
                // token0 fits -> try to narrow further
                left = mid;
            }
        }

        int24 hiFinal = left; // minimal hi that satisfies token0 budget
        uint160 sbFinal = TickMath.getSqrtRatioAtTick(hiFinal);

        // Cap liquidity by b0 as well (to absorb rounding)
        uint128 Lcap0 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbFinal, amounts[0]);
        uint128 Lfin  = _min128(Lcap0, L1);
        if (Lfin == 0) return (lo, hiFinal, 0, 0, 0);

        (uint256 u0, uint256 u1) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbFinal, Lfin);
        return (lo, hiFinal, Lfin, u0, u1);
    }

    /**
     * @notice Fix hi; find the MAXIMAL lo (on the tick grid) such that the position
     *         can consume (approximately) the available token1, given L is limited by token0.
     *
     *         Preference: *narrowing from below* (closest-to-price lo that still works).
     *
     * Pre-conditions:
     *   - Inside-range mode: sqrtP < sb (price below hi).
     *   - 'maxDownTicks' bounds the search corridor below the current tick to avoid unbounded scans.
     *
     * @param tickSpacing   pool tick spacing
     * @param sqrtP         current sqrtPriceX96 (Q64.96)
     * @param hiCandidate   upper tick candidate (will be snapped down to the grid)
     * @param amounts[0]       available token0 (b0)
     * @param amounts[1]       available token1 (b1)
     * @param maxDownTicks  corridor downwards from current tick (search cap)
     * @param tolAbs1       absolute tolerance in token1 (e.g., 1..10 wei)
     *
     * @return loBest   chosen lower tick (grid-aligned)
     * @return hiBest   chosen upper tick (grid-aligned)
     * @return Lbest    final liquidity (capped by b0/b1 due to rounding)
     * @return used0    preview amounts[0] actually consumed by Lbest in [loBest, hiBest]
     * @return used1    preview amounts[1] actually consumed by Lbest in [loBest, hiBest]
     */
    function pickLoPreferNarrow(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 hiCandidate,
        uint256[] memory amounts,
        int24 maxDownTicks,
        uint256 tolAbs1
    )
    public
    pure
    returns (int24 loBest, int24 hiBest, uint128 Lbest, uint256 used0, uint256 used1)
    {
        require(amounts[0] > 0 || amounts[1] > 0, "NSB: zero balances");

        // Snap hi to grid and compute sb
        int24 hi = _roundDownToSpacing(hiCandidate, tickSpacing);
        uint160 sb = TickMath.getSqrtRatioAtTick(hi);

        // Must be inside-range (price below hi)
        require(sqrtP < sb, "NSB: price >= hi");

        // Compute lo search corridor
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtP);

        // Maximal lo (closest below price): one grid step below the price
        int24 loMax = _roundDownToSpacing(currentTick - 1, tickSpacing);
        if (loMax >= hi) loMax = hi - tickSpacing;

        // Minimal lo: bounded downwards and clamped to MIN_TICK
        int24 loMin = currentTick - maxDownTicks;
        if (loMin < TickMath.MIN_TICK) loMin = TickMath.MIN_TICK;
        loMin = _roundDownToSpacing(loMin, tickSpacing);
        if (loMin >= loMax) loMin = loMax - tickSpacing;

        uint160 saMin = TickMath.getSqrtRatioAtTick(loMin);
        uint160 saMax = TickMath.getSqrtRatioAtTick(loMax);

        // Liquidity limited by token0 in (sqrtP, sb): L0 = getLiquidityForAmount0(sqrtP, sb, b0)
        uint128 L0 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
        if (L0 == 0) {
            // No token0 -> cannot place inside-range liquidity with fixed hi
            return (loMax, hi, 0, 0, 0);
        }

        // need1 at corridor extremes with fixed L0
        (/*uint256 need0_const*/, uint256 need1_max) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMin, sb, L0);
        (/*uint256 _        */,   uint256 need1_min) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMax, sb, L0);
        // Note: with fixed L0, amounts[0] inside-range is constant (= b0); amounts[1] decreases as sa increases.

        // Case A: even at the *narrowest* loMax, we require too much token1 -> token1-limited.
        // Stick to the narrow edge (loMax) and cap L by b1 as well.
        if (need1_min > amounts[1] + tolAbs1) {
            uint128 Lcap1_narrow = LiquidityAmounts.getLiquidityForAmount1(saMax, sqrtP, amounts[1]);
            uint128 Lfin_narrow  = _min128(Lcap1_narrow, L0);
            if (Lfin_narrow == 0) return (loMax, hi, 0, 0, 0);

            (uint256 u0n, uint256 u1n) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMax, sb, Lfin_narrow);
            return (loMax, hi, Lfin_narrow, u0n, u1n);
        }

        // Case B: even at the *widest* loMin, token1 requirement is still below b1 -> token0-limited.
        // Prefer *narrowest* lo that works => pick loMax.
        if (need1_max + tolAbs1 < amounts[1]) {
            uint128 Lcap1_narrow2 = LiquidityAmounts.getLiquidityForAmount1(saMax, sqrtP, amounts[1]);
            uint128 Lfin_narrow2  = _min128(Lcap1_narrow2, L0);
            (uint256 u0n2, uint256 u1n2) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMax, sb, Lfin_narrow2);
            return (loMax, hi, Lfin_narrow2, u0n2, u1n2);
        }

        // Case C: bracketed — run binary search for the MAXIMAL lo such that need1(lo; L0) <= b1 (+ tol)
        int24 left  = loMin; // valid: need1(left)  >= b1 - tol
        int24 right = loMax; // valid: need1(right) <= b1 + tol

        uint8 it = 0;
        while (left < right && it++ < MAX_NUM_STEPS) {
            int24 mid = _midTickGridCeil(left, right, tickSpacing); // ceil to grid
            if (mid >= right) break; // converged

            uint160 saMid = TickMath.getSqrtRatioAtTick(mid);
            (, uint256 need1_mid) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMid, sb, L0);

            if (need1_mid > amounts[1] + tolAbs1) {
                // need too much token1 -> lo too close to price (too narrow from below)
                // We must *decrease* lo; lo lives in [left..mid - spacing]
                right = mid - tickSpacing;
            } else {
                // token1 fits -> try to narrow further (increase lo)
                left = mid;
            }
        }

        int24 loFinal = left; // maximal lo that satisfies token1 budget
        uint160 saFinal = TickMath.getSqrtRatioAtTick(loFinal);

        // Cap liquidity by b1 as well (to absorb rounding)
        uint128 Lcap1 = LiquidityAmounts.getLiquidityForAmount1(saFinal, sqrtP, amounts[1]);
        uint128 Lfin  = _min128(Lcap1, L0);
        if (Lfin == 0) return (loFinal, hi, 0, 0, 0);

        (uint256 u0, uint256 u1) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saFinal, sb, Lfin);
        return (loFinal, hi, Lfin, u0, u1);
    }

    // ------------------------------------------------------------------------
    // Optional helper: dust valuation in token1 units (for external scoring)
    // ------------------------------------------------------------------------

    /**
     * @notice Convert leftover (d0, d1) into token1 units: d0 * P + d1, where P = (sqrtP^2) / 2^192.
     * @dev Not used internally by the search; handy to score solutions in a single numeraire.
     */
    function dustInToken1Units(uint256 d0, uint256 d1, uint160 sqrtP) internal pure returns (uint256) {
        if (d0 == 0) return d1;
        unchecked {
            uint256 num = uint256(sqrtP) * uint256(sqrtP); // sqrtP^2
            uint256 d0In1 = FullMath.mulDiv(d0, num, 1 << 192);
            return d0In1 + d1;
        }
    }

    // ------------------------------------------------------------------------
    // Internal utils
    // ------------------------------------------------------------------------

    /// @dev Snap down to tick grid.
    function _roundDownToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 r = tick % spacing;
        return r == 0 ? tick : (tick - r);
    }

    /// @dev Snap up to tick grid.
    function _roundUpToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 r = tick % spacing;
        return r == 0 ? tick : (tick - r + spacing);
    }

    /// @dev Midpoint on grid, rounded *down* (used when searching minimal hi).
    function _midTickGridFloor(int24 a, int24 b, int24 spacing) private pure returns (int24) {
        // a < b
        int24 m = a + ((b - a) / 2);
        int24 r = m % spacing;
        if (r != 0) m = m - r; // round down to grid
        if (m <= a) m = a;     // guard to avoid infinite loop
        return m;
    }

    /// @dev Midpoint on grid, rounded *up* (used when searching maximal lo).
    function _midTickGridCeil(int24 a, int24 b, int24 spacing) private pure returns (int24) {
        // a < b
        int24 m = a + ((b - a) / 2);
        int24 r = m % spacing;
        if (r != 0) m = m - r + spacing; // round up to grid
        if (m >= b) m = b;               // guard to avoid infinite loop
        return m;
    }

    function _min128(uint128 x, uint128 y) private pure returns (uint128) {
        return x < y ? x : y;
    }

    /// @notice Стоимость amount в token1-номинации: amount * P, где P=(sqrtP^2)/2^192
    function value0InToken1(uint256 amount, uint160 sqrtP) internal pure returns (uint256) {
        if (amount == 0) return 0;
        unchecked {
            uint256 num = uint256(sqrtP) * uint256(sqrtP);           // sqrtP^2 (до 256 бит)
            return FullMath.mulDiv(amount, num, 1 << 192);
        }
    }

    /// @notice Общая стоимость (amount0, amount1) в token1-номинации
    function valueInToken1(uint256 amount0, uint256 amount1, uint160 sqrtP) internal pure returns (uint256) {
        return value0InToken1(amount0, sqrtP) + amount1;
    }

    /// @notice Метрика утилизации (0..1e18) с учётом ценности токенов (в token1-номинации)
    function utilization1e18(
        uint256 used0,
        uint256 used1,
        uint256 b0,
        uint256 b1,
        uint160 sqrtP
    ) internal pure returns (uint256) {
        uint256 valUsed  = valueInToken1(used0, used1, sqrtP);
        uint256 valTotal = valueInToken1(b0,   b1,   sqrtP);
        if (valTotal == 0) return 0;
        return FullMath.mulDiv(valUsed, 1e18, valTotal);
    }

    /// @notice Решение направления оптимизации по относительной «ценности» балансов
    /// @param epsilonBps зона индифферентности в б.п. (например, 200 = 2%)
    function chooseMode(
        uint160 sqrtP,
        uint256 b0,
        uint256 b1,
        uint16 epsilonBps
    ) internal pure returns (Mode) {
        // Считаем V0 ~ b0*P и сравниваем с V1 ~ b1
        uint256 V0 = value0InToken1(b0, sqrtP);
        uint256 V1 = b1;

        // V1 vs V0 с гистерезисом
        // Если V1 значительно меньше V0 → дефицитен token1 → двигаем HI (фиксируем lo) → HiPreferNarrow
        // Если V0 значительно меньше V1 → дефицитен token0 → двигаем LO (фиксируем hi) → LoPreferNarrow
        // Иначе — можно выбрать по умолчанию (например, предпочесть более узкий сверху)
        if (V1 * 10_000 + (uint256(epsilonBps) * V1) < V0 * 10_000) {
            return Mode.HiPreferNarrow;
        } else if (V0 * 10_000 + (uint256(epsilonBps) * V0) < V1 * 10_000) {
            return Mode.LoPreferNarrow;
        } else {
            // default: пусть будет верх сужаем
            return Mode.HiPreferNarrow;
        }
    }

    /// @notice Автовыбор и запуск бинарника, возвращает ещё и метрику утилизации 1e18
    /// @dev loCandidate используется для HiPreferNarrow, hiCandidate — для LoPreferNarrow
    function autoPickPreferNarrow(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 loCandidate,
        int24 hiCandidate,
        uint256[] memory amounts,
        int24 corridorTicks, //  например 100_000
        uint256 tolAbs0,     // 1..10 wei
        uint256 tolAbs1,     // 1..10 wei
        uint16 epsilonBps    // 200
    )
    external
    pure
    returns (
        int24 loBest,
        int24 hiBest,
        uint128 Lbest,
        uint256 used0,
        uint256 used1
    )
    {
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(loCandidate);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(hiCandidate);

        uint256 utilization1e18Before;
        uint256[] memory amountsMin = new uint256[](2);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, sqrtAB[0], sqrtAB[1], amounts[0], amounts[1]);
        // Check for zero value
        if (liquidity > 0) {
            (amountsMin[0], amountsMin[1]) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);
            amountsMin[0] = amountsMin[0] * 9_000 / MAX_BPS;//(MAX_BPS - maxSlippage) / MAX_BPS;
            amountsMin[1] = amountsMin[1] * 9_000 / MAX_BPS;//(MAX_BPS - maxSlippage) / MAX_BPS;

            utilization1e18Before = utilization1e18(used0, used1, amounts[0], amounts[1], sqrtP);
        }

        Mode modeChosen = chooseMode(sqrtP, amounts[0], amounts[1], epsilonBps);

        if (modeChosen == Mode.HiPreferNarrow) {
            (loBest, hiBest, Lbest, used0, used1) =
            pickHiPreferNarrow(
                tickSpacing,
                sqrtP,
                loCandidate,
                amounts,
                corridorTicks,        // maxUpTicks
                tolAbs0
            );
        } else {
            (loBest, hiBest, Lbest, used0, used1) =
            pickLoPreferNarrow(
                tickSpacing,
                sqrtP,
                hiCandidate,
                amounts,
                corridorTicks,        // maxDownTicks
                tolAbs1
            );
        }

        uint256 utilization1e18After = utilization1e18(used0, used1, amounts[0], amounts[1], sqrtP);

        // Check for best outcome
        return (utilization1e18Before > utilization1e18After) ?
            (loCandidate, hiCandidate, liquidity, amountsMin[0], amountsMin[1]) : (loBest, hiBest, Lbest, used0, used1);
    }
}
