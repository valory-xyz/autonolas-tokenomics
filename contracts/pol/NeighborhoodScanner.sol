// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TickMath} from "../libraries/TickMath.sol";
import {FixedPoint96, LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {FullMath} from "../libraries/FullMath.sol";

/**
 * Tiny max-util range pickers for Uniswap V3.
 * - pickHiMaxUtil: fix lo, find the LARGEST hi (on grid) such that need0(hi; L1) <= b0.
 *   L1 = getLiquidityForAmount1(sa, sp, b1) (token1-limited).
 * - pickLoMaxUtil: fix hi, find the SMALLEST lo (on grid) such that need1(lo; L0) <= b1.
 *   L0 = getLiquidityForAmount0(sp, sb, b0) (token0-limited).
 *
 * PREVIEW ONLY: these functions do math; they do NOT mint. Use the result with amountMin guards.
 *
 * Preconditions the CALLER should ensure (or this code will revert):
 * - tickSpacing > 0
 * - For pickHiMaxUtil:  sp > sa  (i.e., price strictly above lo → inside-range)
 * - For pickLoMaxUtil:  sp < sb  (i.e., price strictly below hi → inside-range)
 * - At least one balance is non-zero: (b0 > 0 || b1 > 0)
 *
 * Notes:
 * - Monotonicity makes a single binary search sufficient:
 *   amount0(sp,sa,sb,L1) increases with sb; amount1(sp,sa,sb,L0) increases as sa moves down.
 */

/// @title Neighborhood Scanner - Smart contract for scanning neighborhood ticks to better fit liquidity
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract NeighborhoodScanner {
    // TODO Calculate steps - linear gas spending dependency
    uint8 public constant MAX_NUM_BINARY_STEPS = 32;
    // Number of iterations to find the best liquidity for both tick ranges
    int8 public constant MAX_NUM_FAFO_STEPS = 4;
    // TODO SAFETY_STEPS vs NEAR_STEPS
    // Safety steps
    int24 internal constant SAFETY_STEPS = 2;
    // Steps near to tick boundaries
    int24 internal constant NEAR_STEPS = SAFETY_STEPS;

    // ---------- binary search to raise hi ----------
    // Finds minimal hi ∈ [hi0, hiMax], multiple of spacing, such that intermediate > 0.
    // If not found, returns hiMax as "best possible".
    function _bsearchRaiseHi(
        int24 lo,
        int24 hi0,
        int24 hiMax,
        int24 spacing
    ) private pure returns (int24) {
        hi0  = _roundUpToSpacing(hi0, spacing);
        hiMax = _roundDownToSpacing(hiMax, spacing);
        if (hi0 > hiMax) hi0 = hiMax;

        int24 L = hi0;
        int24 R = hiMax;
        int24 ans = hiMax;

        // Binary search while L <= R
        for (uint256 i = 0; i < MAX_NUM_BINARY_STEPS; ++i) {
            int24 mid = _roundDownToSpacing( (L + R) / 2, spacing );
            if (mid < L) mid = L;

            if (_hasNonZeroIntermediate(lo, mid)) {
                // search for smaller hi
                ans = mid;
                R = mid - spacing;
            } else {
                // need to raise hi further
                L = mid + spacing;
            }

            // Break condition: L > R
            if (L > R) break;
        }
        return ans;
    }

    // ---------- binary search to raise lo ----------
    // Finds minimal lo ∈ [loMin, hi - spacing], multiple of spacing, such that intermediate > 0 (with fixed hi).
    // If not found, returns hi - spacing (maximum possible raise of lo).
    function _bsearchRaiseLo(
        int24 loMin,
        int24 hi,
        int24 spacing
    ) private pure returns (int24) {
        loMin = _roundUpToSpacing(loMin, spacing);
        int24 loMax = _roundDownToSpacing(hi - spacing, spacing);
        if (loMin > loMax) loMin = loMax;

        int24 L = loMin;
        int24 R = loMax;
        int24 ans = loMax;

        while (L <= R) {
            int24 mid = _roundUpToSpacing( (L + R) / 2, spacing );
            if (mid > loMax) mid = loMax;

            if (_hasNonZeroIntermediate(mid, hi)) {
                // try smaller lo
                ans = mid;
                R = mid - spacing;
            } else {
                // need to raise lo further
                L = mid + spacing;
            }
        }
        return ans;
    }

    // check if intermediate = floor(sqrtA * sqrtB / Q96) is non-zero
    function _hasNonZeroIntermediate(int24 lo, int24 hi) private pure returns (bool) {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(lo);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(hi);
        uint256 intermediate = FullMath.mulDiv(uint256(sqrtA), uint256(sqrtB), FixedPoint96.Q96);
        return (intermediate > 0);
    }

    /// @dev Optimizes liquidity amounts by widening up provided ticks using binary search + neighborhood search.
    /// @notice 1. Adjusts extreme boundaries, if required.
    ///         2. Looks for correct boundaries and adjusts tick spacings accordingly.
    ///         3. Fixes one of ticks and executed binary + neighborhood search if scan option is true.
    /// Ensures non-zero intermediate for amount0 formula without linear loops.
    function optimizeLiquidityAmounts(
        uint160 centerSqrtPriceX96,
        int24[] memory ticks,
        int24 tickSpacing,
        uint256[] memory balances,
        bool scan
    ) external pure returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired) {
        // 5) raw ticks
        loHi = new int24[](2);
        loHi[0] = ticks[0];
        loHi[1] = ticks[1];

        // 6) snap to spacing + safety margins
        int24 minSp = _roundUpToSpacing(TickMath.MIN_TICK, tickSpacing);
        int24 maxSp = _roundDownToSpacing(TickMath.MAX_TICK, tickSpacing);
        int24 minSafe = minSp + SAFETY_STEPS * tickSpacing;
        int24 maxSafe = maxSp - SAFETY_STEPS * tickSpacing;

        loHi[0] = _roundDownToSpacing(loHi[0], tickSpacing);
        loHi[1] = _roundUpToSpacing(loHi[1], tickSpacing);

        if (loHi[0] < minSafe) loHi[0] = minSafe;
        if (loHi[1] > maxSafe) loHi[1] = maxSafe;

        // 7) ensure non-empty interval
        if (loHi[0] >= loHi[1]) {
            loHi[0] = minSafe;
            loHi[1] = _roundUpToSpacing(loHi[0] + tickSpacing, tickSpacing);
            if (loHi[1] > maxSafe) loHi[1] = maxSafe;
            require(loHi[0] < loHi[1], "EMPTY_RANGE");
        }

        // if already non-zero, return
        if (_hasNonZeroIntermediate(loHi[0], loHi[1])) {
            if (scan) {
                (loHi, liquidity, amountsDesired) = _scanNeighborhood(tickSpacing, centerSqrtPriceX96,
                    loHi, balances);
            } else {
                amountsDesired = balances;
            }
            return (loHi, liquidity, amountsDesired);
        }

        // 8) choose widening side based on closeness to global boundaries
        bool nearMin = (loHi[0] - minSp) <= NEAR_STEPS * tickSpacing;
        bool nearMax = (maxSp - loHi[1]) <= NEAR_STEPS * tickSpacing;

        if (nearMin && !nearMax) {
            // lower near MIN → raise loHi[1] (widen upwards)
            loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            }
        } else if (nearMax && !nearMin) {
            // upper near MAX → raise loHi[0]
            loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            }
        } else {
            // neither or both near boundaries: first try raising loHi[1]
            loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            }
        }

        require(loHi[0] >= minSafe && loHi[1] <= maxSafe && loHi[0] < loHi[1], "RANGE_BOUNDS");
        require(_hasNonZeroIntermediate(loHi[0], loHi[1]), "AMOUNT0_ZERO_LIQ");
    }

    function _iterateRight(int24 L, int24 R, int24 tickSpacing, uint160 sqrtP, uint160 sa, uint128 liquidity, uint256 amount)
        internal pure returns (int24)
    {
        int24 ans = L;
        uint8 it;
        while (L <= R && it++ < MAX_NUM_BINARY_STEPS) {
            int24 steps = (R - L) / tickSpacing;
            int24 mid   = L + (steps / 2) * tickSpacing;

            uint160 sbMid = TickMath.getSqrtRatioAtTick(mid);
            (uint256 need0_mid, ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMid, liquidity);

            if (need0_mid <= amount) {
                // fits → try wider
                ans = mid;
                if (mid == R) break;
                L = mid + tickSpacing;
            } else {
                // too tight
                if (mid == L) break;
                R = mid - tickSpacing;
            }
        }

        return ans;
    }

    function _fafo(int24[] memory loHiBase, uint256[] memory amounts, int24 tickSpacing, uint160 sqrtP, uint128 liquidity)
        internal pure returns (int24[] memory loHiBest, uint128 Lbest, uint256[] memory usedBest)
    {
        usedBest = new uint256[](2);
        loHiBest = new int24[](2);
        usedBest = new uint256[](2);
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(loHiBase[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(loHiBase[1]);

        loHiBest[0] = loHiBase[0];
        loHiBest[1] = loHiBase[1];
        Lbest = liquidity;
        (usedBest[0], usedBest[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);
        uint256[] memory utilizationMinMax = new uint256[](2);
        utilizationMinMax[0] = utilization1e18(usedBest, amounts, sqrtP);

        int24 i = loHiBase[0] - MAX_NUM_FAFO_STEPS * tickSpacing;
        for (; i <= loHiBase[0] + MAX_NUM_FAFO_STEPS * tickSpacing; i = i + tickSpacing) {
            int24 j = loHiBase[1] - MAX_NUM_FAFO_STEPS * tickSpacing;
            for (; j <= loHiBase[1] + MAX_NUM_FAFO_STEPS * tickSpacing; j = j + tickSpacing) {
                if (i >= j) {
                    continue;
                }
                if (i <= TickMath.MIN_TICK || j >= TickMath.MAX_TICK) {
                    continue;
                }

                sqrtAB[0] = TickMath.getSqrtRatioAtTick(i);
                sqrtAB[1] = TickMath.getSqrtRatioAtTick(j);
                if (sqrtAB[0] >= sqrtP || sqrtAB[1] <= sqrtP) {
                    continue;
                }

                liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, sqrtAB[0], sqrtAB[1], amounts[0], amounts[1]);
                if (liquidity == 0) {
                    continue;
                }

                uint256[] memory used = new uint256[](2);
                (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);

                utilizationMinMax[1] = utilization1e18(used, amounts, sqrtP);
                if (utilizationMinMax[1] > utilizationMinMax[0]) {
                    loHiBest[0] = i;
                    loHiBest[1] = j;
                    usedBest[0] = used[0];
                    usedBest[1] = used[1];
                    Lbest = liquidity;
                    utilizationMinMax[0] = utilizationMinMax[1];
                }
            }
        }
    }

    /// @dev Finds optimal ticks when initially fixing lower base tick.
    /// @notice 1. Find ticks via a binary search such that the position consumes all available token0.
    ///         2. Minimally search around to find optimal ranges such that max amounts of token0 and token1 are used.
    /// @param tickSpacing > 0
    /// @param sqrtP current sqrtPriceX96 (Q64.96)
    /// @param lowerBaseTick lower tick candidate (will be snapped DOWN to grid). MUST satisfy: priceAbove(lo) i.e. sqrtP > sqrt(lo)
    /// @param amounts Available token amounts
    function pickHiMaxUtil(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 lowerBaseTick,
        uint256[] memory amounts
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 Lbest, uint256[] memory used)
    {
        loHiBest = new int24[](2);
        loHiBest[0] = lowerBaseTick;
        used = new uint256[](2);

        uint160 sa = TickMath.getSqrtRatioAtTick(lowerBaseTick);

        // hi search range: [first grid above price, MAX_TICK on grid]
        int24 ct = TickMath.getTickAtSqrtRatio(sqrtP);
        int24[] memory hiMinMax = new int24[](2);
        hiMinMax[0] = _roundUpToSpacing(ct + 1, tickSpacing);
        if (hiMinMax[0] <= loHiBest[0]) hiMinMax[0] = loHiBest[0] + tickSpacing;
        hiMinMax[1]= _roundDownToSpacing(TickMath.MAX_TICK, tickSpacing);
        if (hiMinMax[1] <= hiMinMax[0]) hiMinMax[1] = hiMinMax[0] + tickSpacing;

        // token1-limited liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
        if (liquidity == 0) {
            loHiBest[1] = hiMinMax[0];
            return (loHiBest, Lbest, used);
        }

        // --- edge @ hiMin ---
        uint160 sb = TickMath.getSqrtRatioAtTick(hiMinMax[0]);
        (used[0], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (used[0] > amounts[0]) {
            // even narrowest needs too much token0 → cap by b0 at hiMin
            Lbest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
            Lbest = _min128(Lbest, liquidity);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, Lbest);
            loHiBest[1] = hiMinMax[0];
            return (loHiBest, Lbest, used);
        }

        // --- edge @ hiMax ---
        sb = TickMath.getSqrtRatioAtTick(hiMinMax[1]);
        (used[0], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (used[0] <= amounts[0]) {
            // widest still fits → take hiMax (cap by b0 to absorb rounding)
            Lbest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
            Lbest = _min128(Lbest, liquidity);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, Lbest);
            loHiBest[1] = hiMinMax[1];
            return (loHiBest, Lbest, used);
        }

        // minimal hi that satisfies token0 budget
        loHiBest[1] = _iterateRight(hiMinMax[0], hiMinMax[1], tickSpacing, sqrtP, sa, liquidity, amounts[0]);
        sb = TickMath.getSqrtRatioAtTick(loHiBest[1]);

        liquidity = _min128(LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]), liquidity);

        return _fafo(loHiBest, amounts, tickSpacing, sqrtP, liquidity);
    }

    function _iterateLeft(int24 L, int24 R, int24 tickSpacing, uint160 sqrtP, uint160 sb, uint128 liquidity, uint256 amount)
    internal pure returns (int24)
    {
        int24 ans = R;
        uint8 it;
        while (L <= R && it++ < MAX_NUM_BINARY_STEPS) {
            int24 steps = (R - L) / tickSpacing;
            int24 mid   = L + (steps / 2) * tickSpacing;

            uint160 saMid = TickMath.getSqrtRatioAtTick(mid);
            (, uint256 need1_mid) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMid, sb, liquidity);

            if (need1_mid <= amount) {
                ans = mid;                        // fits → try wider (lower lo)
                if (mid == R) break;
                R = mid - tickSpacing;
            } else {
                if (mid == L) break;              // too narrow → raise lo
                L = mid + tickSpacing;
            }
        }

        return ans;
    }

    /// @dev Finds optimal ticks when initially fixing upper base tick.
    /// @notice 1. Find ticks via a binary search such that the position consumes all available token1.
    ///         2. Minimally search around to find optimal ranges such that max amounts of token0 and token1 are used.
    /// @param tickSpacing > 0
    /// @param sqrtP current sqrtPriceX96 (Q64.96)
    /// @param upperBaseTick upper tick candidate (will be snapped DOWN to grid). MUST satisfy: priceBelow(hi) i.e. sqrtP < sqrt(hi)
    /// @param amounts Available token amounts.
    function pickLoMaxUtil(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 upperBaseTick,
        uint256[] memory amounts
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 Lbest, uint256[] memory used)
    {
        loHiBest = new int24[](2);
        loHiBest[1] = upperBaseTick;
        used = new uint256[](2);

        uint160 sb = TickMath.getSqrtRatioAtTick(upperBaseTick);

        // hi search range: [first grid above price, MAX_TICK on grid]
        int24 ct = TickMath.getTickAtSqrtRatio(sqrtP);
        int24[] memory loMinMax = new int24[](2);
        loMinMax[1] = _roundDownToSpacing(ct - 1, tickSpacing);
        if (loMinMax[1] >= loHiBest[1]) loMinMax[1] = loHiBest[1] - tickSpacing;
        loMinMax[0]= _roundUpToSpacing(TickMath.MIN_TICK, tickSpacing);
        if (loMinMax[0] >= loMinMax[1]) loMinMax[0] = loMinMax[1] - tickSpacing;

        // token0-limited liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
        if (liquidity == 0) {
            loHiBest[0] = loMinMax[1];
            return (loHiBest, Lbest, used);
        }

        // --- edge @ loMin (widest) ---
        uint160 sa = TickMath.getSqrtRatioAtTick(loMinMax[0]);
        (, used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (used[1] <= amounts[1]) {
            Lbest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
            Lbest = _min128(Lbest, liquidity);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, Lbest);
            loHiBest[0] = loMinMax[0];
            return (loHiBest, Lbest, used);
        }

        // --- edge @ loMax (narrowest) ---
        sa = TickMath.getSqrtRatioAtTick(loMinMax[1]);
        (, used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (used[1] > amounts[1]) {
            Lbest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
            Lbest = _min128(Lbest, liquidity);
            (used[0], used[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, Lbest);
            loHiBest[0] = loMinMax[1];
            return (loHiBest, Lbest, used);
        }

        // minimal lo that satisfies token1 budget
        loHiBest[0] = _iterateLeft(loMinMax[0], loMinMax[1], tickSpacing, sqrtP, sb, liquidity, amounts[1]);
        sa = TickMath.getSqrtRatioAtTick(loHiBest[0]);

        liquidity = _min128(LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]), liquidity);

        return _fafo(loHiBest, amounts, tickSpacing, sqrtP, liquidity);
    }

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

    function _min128(uint128 x, uint128 y) private pure returns (uint128) {
        return x < y ? x : y;
    }

    /// @notice Amount value in token1-value: amount * P, где P=(sqrtP^2)/2^192
    function value0InToken1(uint256 amount, uint160 sqrtP) internal pure returns (uint256) {
        if (amount == 0) return 0;
        unchecked {
            uint256 num = uint256(sqrtP) * uint256(sqrtP);           // sqrtP^2 (до 256 бит)
            return FullMath.mulDiv(amount, num, 1 << 192);
        }
    }

    /// @notice Accumulated value of (amount0, amount1) in token1-value
    function valueInToken1(uint256 amount0, uint256 amount1, uint160 sqrtP) internal pure returns (uint256) {
        return value0InToken1(amount0, sqrtP) + amount1;
    }

    /// @notice Utlization metrics (0..1e18) according to accumulated token value (in token1-value)
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

    /// @notice Search direction according to he balance value one against another: which one needs to be fixed.
    function _chooseMode(
        uint160 sqrtP,
        uint256[] memory balances
    ) internal pure returns (bool) {
        // Calculate V0 ~ b0*P and compare with V1 ~ b1
        uint256 V0 = value0InToken1(balances[0], sqrtP);
        uint256 V1 = balances[1];

        // Check balance inequality
        return (V0 >= V1);
    }
    
    /// @dev Scans neighborhood with binary search and locally based on amounts[0] or amounts[1] in absolute token value.
    /// @notice ticks[0] is used for pickHiMaxUtil, ticks[0] - for pickLoMaxUtil.
    function _scanNeighborhood(
        int24 tickSpacing,
        uint160 sqrtP,
        int24[] memory ticks,
        uint256[] memory amounts
    )
    internal
    pure
    returns (
        int24[] memory loHiBest,
        uint128 Lbest,
        uint256[] memory used
    )
    {
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert();
        }

        loHiBest = new int24[](2);

        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);

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

        bool optimizeHi = _chooseMode(sqrtP, amounts);

        if (optimizeHi) {
            (loHiBest, Lbest, used) =
            pickHiMaxUtil(
                tickSpacing,
                sqrtP,
                ticks[0],
                amounts
            );
        } else {
            (loHiBest, Lbest, used) =
            pickLoMaxUtil(
                tickSpacing,
                sqrtP,
                ticks[1],
                amounts
            );
        }

        utilization1e18BeforeAfter[1] = utilization1e18(used, amounts, sqrtP);

        // Check for best outcome
        if (utilization1e18BeforeAfter[0] > utilization1e18BeforeAfter[1]) {
            loHiBest[0] = ticks[0];
            loHiBest[1] = ticks[1];
            return (loHiBest, liquidity, amountsMin);
        } else {
            return (loHiBest, Lbest, used);
        }
    }
}
