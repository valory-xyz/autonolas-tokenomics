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
    // Epsilon bps value
    uint16 public constant EPSILON_BPS = 200;
    // Absolute tolerance in tokens (wei)
    uint256 public constant ABSOLUT_TOL = 10;

    function _iterateRight(int24[] memory loHiBest, int24 tickSpacing, uint160 sqrtP, uint160 sa, uint128 Lbest, uint256 amount)
    internal pure returns (int24) {
        // Case C: bracketed — run binary search for the MINIMAL hi such that need0(hi; Lbest) <= b0 (+ tol)
        int24 left  = loHiBest[0]; // valid: need0(left)  <= b0 + tol
        int24 right = loHiBest[1]; // valid: need0(right) >= b0 - tol

        uint8 it = 0;
        while (left < right && it++ < MAX_NUM_STEPS) {
            int24 mid = _midTickGridFloor(left, right, tickSpacing); // floor to grid
            if (mid <= left) break; // converged

            uint160 sbMid = TickMath.getSqrtRatioAtTick(mid);
            (uint256 need0_mid, ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMid, Lbest);

            if (need0_mid > amount + ABSOLUT_TOL) {
                // need too much token0 -> range still too narrow -> move hi downward (closer to price)
                // In terms of ticks: we must *decrease* hi; hi lives in (left..mid-1]
                right = mid - tickSpacing;
            } else {
                // token0 fits -> try to narrow further
                left = mid;
            }
        }

        return right;
    }

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
     *
     * @return loHiBest   chosen lower and upper ticks (grid-aligned)
     * @return Lbest    final liquidity (capped by b0/b1 due to rounding)
     * @return used     preview amounts actually consumed by Lbest in [loHiBest[0], loHiBest[1]]
     */
    function pickHiPreferNarrow(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 loCandidate,
        uint256[] memory amounts,
        int24 maxUpTicks
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 Lbest, uint256[] memory used)
    {
        require(amounts[0] > 0 || amounts[1] > 0, "NSB: zero balances");

        loHiBest = new int24[](2);
        used = new uint256[](2);

        // Snap loCandidate to grid and compute sa
        loCandidate = _roundDownToSpacing(loCandidate, tickSpacing);
        uint160 sa = TickMath.getSqrtRatioAtTick(loCandidate);

        // Must be inside-range (price above loCandidate)
        require(sqrtP > sa, "NSB: price <= loCandidate");

        // Compute hi search corridor
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtP);

        // Minimal hi: one grid step above the price
        loHiBest[0] = _roundUpToSpacing(currentTick + 1, tickSpacing);
        if (loHiBest[0] <= loCandidate) loHiBest[0] = loCandidate + tickSpacing;

        // Maximal hi: bounded upwards and clamped to MAX_TICK
        loHiBest[1] = currentTick + maxUpTicks;
        if (loHiBest[1] > TickMath.MAX_TICK) loHiBest[1] = TickMath.MAX_TICK;
        loHiBest[1] = _roundDownToSpacing(loHiBest[1], tickSpacing);
        if (loHiBest[1] <= loHiBest[0]) loHiBest[1] = loHiBest[0] + tickSpacing;

        uint160[] memory sbMinMax = new uint160[](2);
        sbMinMax[0] = TickMath.getSqrtRatioAtTick(loHiBest[0]);
        sbMinMax[1] = TickMath.getSqrtRatioAtTick(loHiBest[1]);

        loHiBest[1] = loHiBest[0];
        loHiBest[0] = loCandidate;

        // Liquidity limited by token1 in (sa, sqrtP): Lbest = getLiquidityForAmount1(sa, sqrtP, b1)
        Lbest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
        if (Lbest == 0) {
            // No token1 -> cannot place inside-range liquidity with fixed loCandidate
            return (loHiBest, Lbest, used);
        }

        // need0 at corridor extremes with fixed Lbest
        (used[0], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMinMax[0], Lbest);
        (used[1], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMinMax[1], Lbest);

        uint128 Lfin;
        // Case A: even at the *narrowest* loHiBest[0], we already require too much token0 -> token0-limited.
        // Stick to the narrow edge (loHiBest[0]) and cap L by b0 as well.
        if (used[0] > amounts[0] + ABSOLUT_TOL) {
            Lfin = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbMinMax[0], amounts[0]);
            Lbest  = _min128(Lfin, Lbest);
            if (Lbest == 0) {
                return (loHiBest, Lbest, used);
            }

            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMinMax[0], Lbest);
            return (loHiBest, Lbest, used);
        }

        // Case B: even at the *widest* loHiBest[1], token0 requirement is still below b0 -> token1-limited.
        // Prefer *narrowest* hi that works => pick loHiBest[0].
        if (used[1] + ABSOLUT_TOL < amounts[0]) {
            Lfin = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbMinMax[0], amounts[0]);
            Lbest  = _min128(Lfin, Lbest);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMinMax[0], Lbest);
            return (loHiBest, Lbest, used);
        }

        // minimal hi that satisfies token0 budget
        loHiBest[1] = _iterateRight(loHiBest, tickSpacing, sqrtP, sa, Lbest, amounts[0]);
        uint160 sbFinal = TickMath.getSqrtRatioAtTick(loHiBest[1]);

        // Cap liquidity by b0 as well (to absorb rounding)
        Lfin = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sbFinal, amounts[0]);
        Lbest = _min128(Lfin, Lbest);
        if (Lbest == 0) {
            used[0] = 0;
            used[1] = 0;
            return (loHiBest, Lbest, used);
        }

        (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbFinal, Lbest);
        return (loHiBest, Lfin, used);
    }

    function _iterateLeft(int24[] memory loHiBest, int24 tickSpacing, uint160 sqrtP, uint160 sb, uint128 Lbest, uint256 amount)
    internal pure returns (int24) {
        // Case C: bracketed — run binary search for the MAXIMAL lo such that need1(lo; Lbest) <= b1 (+ tol)
        int24 left  = loHiBest[0]; // valid: need1(left)  >= b1 - tol
        int24 right = loHiBest[1]; // valid: need1(right) <= b1 + tol

        uint8 it = 0;
        while (left < right && it++ < MAX_NUM_STEPS) {
            int24 mid = _midTickGridCeil(left, right, tickSpacing); // ceil to grid
            if (mid >= right) break; // converged

            uint160 saMid = TickMath.getSqrtRatioAtTick(mid);
            (, uint256 need1_mid) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMid, sb, Lbest);

            if (need1_mid > amount + ABSOLUT_TOL) {
                // need too much token1 -> lo too close to price (too narrow from below)
                // We must *decrease* lo; lo lives in [left..mid - spacing]
                right = mid - tickSpacing;
            } else {
                // token1 fits -> try to narrow further (increase lo)
                left = mid;
            }
        }

        return left;
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
     *
     * @return loHiBest   chosen lower and upper ticks (grid-aligned)
     * @return Lbest    final liquidity (capped by b0/b1 due to rounding)
     * @return used     preview amounts actually consumed by Lbest in [loHiBest[0], loHiBest[1]]
     */
    function pickLoPreferNarrow(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 hiCandidate,
        uint256[] memory amounts,
        int24 maxDownTicks
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 Lbest, uint256[] memory used)
    {
        require(amounts[0] > 0 || amounts[1] > 0, "NSB: zero balances");

        loHiBest = new int24[](2);
        used = new uint256[](2);

        // Snap hiCandidate to grid and compute sb
        hiCandidate = _roundDownToSpacing(hiCandidate, tickSpacing);
        uint160 sb = TickMath.getSqrtRatioAtTick(hiCandidate);

        // Must be inside-range (price below hiCandidate)
        require(sqrtP < sb, "NSB: price >= hiCandidate");

        // Compute lo search corridor
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtP);

        // Maximal lo (closest below price): one grid step below the price
        loHiBest[1] = _roundDownToSpacing(currentTick - 1, tickSpacing);
        if (loHiBest[1] >= hiCandidate) loHiBest[1] = hiCandidate - tickSpacing;

        // Minimal lo: bounded downwards and clamped to MIN_TICK
        loHiBest[0] = currentTick - maxDownTicks;
        if (loHiBest[0] < TickMath.MIN_TICK) loHiBest[0] = TickMath.MIN_TICK;
        loHiBest[0] = _roundDownToSpacing(loHiBest[0], tickSpacing);
        if (loHiBest[0] >= loHiBest[1]) loHiBest[0] = loHiBest[1] - tickSpacing;


        uint160[] memory saMinMax = new uint160[](2);
        saMinMax[0] = TickMath.getSqrtRatioAtTick(loHiBest[0]);
        saMinMax[1] = TickMath.getSqrtRatioAtTick(loHiBest[1]);

        loHiBest[0] = loHiBest[1];
        loHiBest[1] = hiCandidate;

        // Liquidity limited by token0 in (sqrtP, sb): Lbest = getLiquidityForAmount0(sqrtP, sb, b0)
        Lbest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
        if (Lbest == 0) {
            // No token0 -> cannot place inside-range liquidity with fixed hiCandidate
            return (loHiBest, Lbest, used);
        }

        // need1 at corridor extremes with fixed Lbest
        (, used[0]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMinMax[0], sb, Lbest);
        (, used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMinMax[1], sb, Lbest);
        // Note: with fixed Lbest, amounts[0] inside-range is constant (= b0); amounts[1] decreases as sa increases.

        uint128 Lfin;
        // Case A: even at the *narrowest* loHiBest[1], we require too much token1 -> token1-limited.
        // Stick to the narrow edge (loHiBest[1]) and cap L by b1 as well.
        if (used[1] > amounts[1] + ABSOLUT_TOL) {
            Lfin = LiquidityAmounts.getLiquidityForAmount1(saMinMax[1], sqrtP, amounts[1]);
            Lbest = _min128(Lfin, Lbest);

            if (Lbest == 0) {
                return (loHiBest, Lbest, used);
            }

            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMinMax[1], sb, Lbest);
            return (loHiBest, Lbest, used);
        }

        // Case B: even at the *widest* loHiBest[0], token1 requirement is still below b1 -> token0-limited.
        // Prefer *narrowest* lo that works => pick loHiBest[1].
        if (used[0] + ABSOLUT_TOL < amounts[1]) {
            Lfin = LiquidityAmounts.getLiquidityForAmount1(saMinMax[1], sqrtP, amounts[1]);
            Lbest  = _min128(Lfin, Lbest);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMinMax[1], sb, Lbest);
            return (loHiBest, Lbest, used);
        }

        // maximal lo that satisfies token1 budget
        loHiBest[0] = _iterateLeft(loHiBest, tickSpacing, sqrtP, sb, Lbest, amounts[1]);
        saMinMax[0] = TickMath.getSqrtRatioAtTick(loHiBest[0]);

        // Cap liquidity by b1 as well (to absorb rounding)
        Lfin = LiquidityAmounts.getLiquidityForAmount1(saMinMax[0], sqrtP, amounts[1]);
        Lbest = _min128(Lfin, Lbest);
        if (Lbest == 0) {
            used[0] = 0;
            used[1] = 0;
            return (loHiBest, Lbest, used);
        }

        (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMinMax[0], sb, Lbest);
        return (loHiBest, Lbest, used);
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
        uint256[] memory used,
        uint256[] memory balances,
        uint160 sqrtP
    ) internal pure returns (uint256) {
        uint256 valUsed  = valueInToken1(used[0], used[1], sqrtP);
        uint256 valTotal = valueInToken1(balances[0], balances[1], sqrtP);
        if (valTotal == 0) return 0;
        return FullMath.mulDiv(valUsed, 1e18, valTotal);
    }

    /// @notice Решение направления оптимизации по относительной «ценности» балансов
    function chooseMode(
        uint160 sqrtP,
        uint256[] memory balances
    ) internal pure returns (Mode) {
        // Считаем V0 ~ b0*P и сравниваем с V1 ~ b1
        uint256 V0 = value0InToken1(balances[0], sqrtP);
        uint256 V1 = balances[1];

        // V1 vs V0 с гистерезисом
        // Если V1 значительно меньше V0 → дефицитен token1 → двигаем HI (фиксируем lo) → HiPreferNarrow
        // Если V0 значительно меньше V1 → дефицитен token0 → двигаем LO (фиксируем hi) → LoPreferNarrow
        // Иначе — можно выбрать по умолчанию (например, предпочесть более узкий сверху)
        if (V1 * 10_000 + (uint256(EPSILON_BPS) * V1) < V0 * 10_000) {
            return Mode.HiPreferNarrow;
        } else if (V0 * 10_000 + (uint256(EPSILON_BPS) * V0) < V1 * 10_000) {
            return Mode.LoPreferNarrow;
        } else {
            // default: пусть будет верх сужаем
            return Mode.HiPreferNarrow;
        }
    }

    /// @notice Автовыбор и запуск бинарника, возвращает ещё и метрику утилизации 1e18
    /// @dev loCandidate используется для HiPreferNarrow, hiCandidate — для LoPreferNarrow
    function scanNeighborhood(
        int24 tickSpacing,
        uint160 sqrtP,
        int24[] memory loHiCandidates,
        uint256[] memory amounts
    )
    external
    pure
    returns (
        int24[] memory loHiBest,
        uint128 Lbest,
        uint256[] memory used
    )
    {
        // TODO
        //  for example 100_000
        int24 corridorTicks = 100_000;

        loHiBest = new int24[](2);

        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(loHiCandidates[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(loHiCandidates[1]);

        uint256[] memory utilization1e18BeforeAfter = new uint256[](2);
        uint256[] memory amountsMin = new uint256[](2);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, sqrtAB[0], sqrtAB[1], amounts[0], amounts[1]);
        // Check for zero value
        if (liquidity > 0) {
            (amountsMin[0], amountsMin[1]) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);

            utilization1e18BeforeAfter[0] = utilization1e18(amountsMin, amounts, sqrtP);
        }

        Mode modeChosen = chooseMode(sqrtP, amounts);

        if (modeChosen == Mode.HiPreferNarrow) {
            (loHiBest, Lbest, used) =
            pickHiPreferNarrow(
                tickSpacing,
                sqrtP,
                loHiCandidates[0],
                amounts,
                corridorTicks
            );
        } else {
            (loHiBest, Lbest, used) =
            pickLoPreferNarrow(
                tickSpacing,
                sqrtP,
                loHiCandidates[1],
                amounts,
                corridorTicks
            );
        }

        utilization1e18BeforeAfter[1] = utilization1e18(used, amounts, sqrtP);

        // Check for best outcome
        if (utilization1e18BeforeAfter[0] > utilization1e18BeforeAfter[1]) {
            loHiBest[0] = loHiCandidates[0];
            loHiBest[1] = loHiCandidates[1];
            return (loHiBest, liquidity, amountsMin);
        } else {
            return (loHiBest, Lbest, used);
        }
    }
}
