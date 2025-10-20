// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TickMath} from "../libraries/TickMath.sol";
import {FixedPoint96, LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {FullMath} from "../libraries/FullMath.sol";

/// @dev Zero value provided.
error ZeroValue();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(int24 provided, int24 max);

/// @dev Out of tick range bounds.
/// @param low Low tick provided.
/// @param high High tick provided.
/// @param minLow Min low tick allowed.
/// @param maxHigh Max high tick allowed.
error RangeBounds(int24 low, int24 high, int24 minLow, int24 maxHigh);

/**
 * Tick range pickers for Uniswap V3.
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
 *   amount0(sp, sa, sb, L1) increases with sb; amount1(sp, sa, sb, L0) increases as sa moves down.
 */

/// @title Neighborhood Scanner - Smart contract for scanning neighborhood ticks to better fit liquidity
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract NeighborhoodScanner {
    // Number of binary search steps
    uint8 public constant MAX_NUM_BINARY_STEPS = 32;
    // Number of iterations to find the best liquidity for both tick ranges in a nearest neighborhood
    int8 public constant MAX_NUM_NEIGHBORHOOD_STEPS = 4;
    // Safety spacing steps near boundaries
    int24 internal constant SAFETY_STEPS = 2;

    /// @dev Executes binary search to raise higher tick.
    /// @notice Finds minimal hi ∈ [hi, hiMax], multiple of spacing, such that intermediate > 0.
    ///         If not found, returns hiMax as "best possible".
    /// @param lo Lower tick value.
    /// @param hi Base higher tick value.
    /// @param hiMax Max value of higher tick value.
    /// @param tickSpacing Tick spacing.
    /// @return Optimal higher tick value.
    function _raiseHigh(
        int24 lo,
        int24 hi,
        int24 hiMax,
        int24 tickSpacing
    ) internal pure returns (int24) {
        // Limit hi by hiMax
        if (hi > hiMax) {
            hi = hiMax;
        }

        // Initial values
        int24 L = hi;
        int24 R = hiMax;
        int24 ans = hiMax;

        // Binary search while L <= R
        for (uint256 i = 0; i < MAX_NUM_BINARY_STEPS; ++i) {
            int24 mid = _roundDownToSpacing((L + R) / 2, tickSpacing);
            if (mid < L) {
                mid = L;
            }

            // Check for non-zero intermediate
            if (_hasNonZeroIntermediate(lo, mid)) {
                // Search for smaller hi
                ans = mid;
                R = mid - tickSpacing;
            } else {
                // Need to raise hi further
                L = mid + tickSpacing;
            }

            // Break condition: L > R (lower hi candidate tick is bigger than higher hi one)
            if (L > R) break;
        }

        return ans;
    }

    /// @dev Executes binary search to raise lower tick.
    /// @notice Finds minimal lo ∈ [loMin, hi - tickSpacing], such that intermediate > 0 (with fixed hi).
    ///         If not found, returns hi - tickSpacing (maximum possible raise of lo).
    /// @param loMin Min value of lower tick value.
    /// @param hi Fixed higher tick value.
    /// @param tickSpacing Tick spacing.
    /// @return Optimal lower tick value.
    function _raiseLow(
        int24 loMin,
        int24 hi,
        int24 tickSpacing
    ) internal pure returns (int24) {
        // Limit loMin by loMax
        int24 loMax = hi - tickSpacing;
        if (loMin > loMax) {
            loMin = loMax;
        }

        // Initial values
        int24 L = loMin;
        int24 R = loMax;
        int24 ans = loMax;

        // Binary search while L <= R
        for (uint256 i = 0; i < MAX_NUM_BINARY_STEPS; ++i) {
            int24 mid = _roundUpToSpacing((L + R) / 2, tickSpacing);
            if (mid > loMax) mid = loMax;

            // Check for non-zero intermediate
            if (_hasNonZeroIntermediate(mid, hi)) {
                // Try smaller lo
                ans = mid;
                R = mid - tickSpacing;
            } else {
                // Need to raise lo further
                L = mid + tickSpacing;
            }

            // Break condition: L > R (lower lo candidate tick is bigger than higher lo one)
            if (L > R) break;
        }

        return ans;
    }

    /// @dev Checks if intermediate = floor(sqrtA * sqrtB / Q96) is non-zero.
    /// @param lo Low tick value.
    /// @param hi High tick value.
    /// @return True if intermediate ois non-zero.
    function _hasNonZeroIntermediate(int24 lo, int24 hi) internal pure returns (bool) {
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
    /// @param sqrtP Center sqrt price.
    /// @param ticks Ticks array.
    /// @param tickSpacing Tick spacing.
    /// @param initialAmounts Initial amounts array.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return loHi Optimized ticks.
    /// @return liquidity Corresponding liquidity.
    /// @return amountsDesired Corresponding desired amounts.
    function optimizeLiquidityAmounts(
        uint160 sqrtP,
        int24[] calldata ticks,
        int24 tickSpacing,
        uint256[] calldata initialAmounts,
        bool scan
    ) external pure returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired) {
        // Assign raw ticks
        loHi = new int24[](2);
        amountsDesired = new uint256[](2);
        loHi[0] = ticks[0];
        loHi[1] = ticks[1];

        // Snap to spacing + safety margins
        int24 minSafe = _roundUpToSpacing(TickMath.MIN_TICK, tickSpacing);
        minSafe += SAFETY_STEPS * tickSpacing;
        int24 maxSafe = _roundDownToSpacing(TickMath.MAX_TICK, tickSpacing);
        maxSafe -= SAFETY_STEPS * tickSpacing;

        // Round to exact spacing values
        loHi[0] = _roundDownToSpacing(loHi[0], tickSpacing);
        loHi[1] = _roundUpToSpacing(loHi[1], tickSpacing);

        // Safe bounds after rounding
        if (loHi[0] < minSafe) {
            loHi[0] = minSafe;
        }
        if (loHi[1] > maxSafe) {
            loHi[1] = maxSafe;
        }

        // Ensure non-empty ticks interval
        if (loHi[0] >= loHi[1]) {
            loHi[0] = minSafe;
            loHi[1] += tickSpacing;
            if (loHi[1] > maxSafe) {
                loHi[1] = maxSafe;
            }

            if (loHi[0] >= loHi[1]) {
                revert Overflow(loHi[0], loHi[1] - 1);
            }
        }

        // If already non-zero, return (after neighborhood scanning, if specified)
        if (_hasNonZeroIntermediate(loHi[0], loHi[1])) {
            if (scan) {
                return _scanNeighborhood(tickSpacing, sqrtP, loHi, initialAmounts);
            }
        } else {
            // Choose widening side based on closeness to global boundaries
            bool nearMin = (loHi[0] - minSafe) <= SAFETY_STEPS * tickSpacing;
            bool nearMax = (maxSafe - loHi[1]) <= SAFETY_STEPS * tickSpacing;

            if (nearMin && !nearMax) {
                // Lower near MIN: raise loHi[1]
                loHi[1] = _raiseHigh(loHi[0], loHi[1], maxSafe, tickSpacing);
                if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                    loHi[0] = _raiseLow(minSafe, loHi[1], tickSpacing);
                }
            } else if (nearMax && !nearMin) {
                // Upper near MAX: raise loHi[0]
                loHi[0] = _raiseLow(minSafe, loHi[1], tickSpacing);
                if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                    loHi[1] = _raiseHigh(loHi[0], loHi[1], maxSafe, tickSpacing);
                }
            } else {
                // Neither or both near boundaries: first try raising loHi[1]
                loHi[1] = _raiseHigh(loHi[0], loHi[1], maxSafe, tickSpacing);
                if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                    loHi[0] = _raiseLow(minSafe, loHi[1], tickSpacing);
                }
            }

            // Check correctness of ranges
            if (minSafe > loHi[0] || loHi[1] > maxSafe || loHi[0] >= loHi[1]) {
                revert RangeBounds(loHi[0], loHi[1], minSafe, maxSafe);
            }

            // Check for final intermadiate value
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                revert ZeroValue();
            }
        }

        // Calculate liquidity
        liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, TickMath.getSqrtRatioAtTick(loHi[0]),
            TickMath.getSqrtRatioAtTick(loHi[1]), initialAmounts[0], initialAmounts[1]);

        // Amounts desired are equal to initial amounts
        amountsDesired[0] = initialAmounts[0];
        amountsDesired[1] = initialAmounts[1];
    }

    /// @dev Executes binary search for higher tick with fixed lower one.
    /// @notice Finds optimal ans ∈ [L, R], such that amount for token0 is biggest.
    /// @param L Left tick value bound.
    /// @param R Right tick value bound.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param sa Left tick sqrt price.
    /// @param liquidity Initial liquidity for token0.
    /// @param amount Corresponding initial amount for token0.
    /// @return Optimal lower tick value with maximized token0 liquidity.
    function _iterateRight(int24 L, int24 R, int24 tickSpacing, uint160 sqrtP, uint160 sa, uint128 liquidity, uint256 amount)
        internal pure returns (int24)
    {
        int24 ans = L;
        // Binary search while L <= R
        for (uint256 i = 0; i < MAX_NUM_BINARY_STEPS; ++i) {
            int24 steps = (R - L) / tickSpacing;
            int24 mid = L + (steps / 2) * tickSpacing;

            // Get right tick liquidity and token0 amount for provided liquidity
            uint160 sbMid = TickMath.getSqrtRatioAtTick(mid);
            (uint256 optimalAmount, ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sbMid, liquidity);

            if (optimalAmount <= amount) {
                // Amounts fit, try wider range
                ans = mid;
                if (mid == R) break;
                L = mid + tickSpacing;
            } else {
                // Amounts does not fit, try narrower range
                if (mid == L) break;
                R = mid - tickSpacing;
            }

            // Break condition: L > R (lower hi candidate tick is bigger than higher hi one)
            if (L > R) break;
        }

        return ans;
    }

    /// @dev Executed neighborhood search for both lo and hi ticks to find optimal amounts.
    /// @param loHiBase Base ticks array.
    /// @param initialAmounts Initial amounts array.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param liquidity Initial liquidity.
    /// @return loHiBest Optimized ticks.
    /// @return liqBest Corresponding liquidity.
    /// @return optimizedAmounts Corresponding amounts.
    function _neighborhoodSearch(int24[] memory loHiBase, uint256[] memory initialAmounts, int24 tickSpacing, uint160 sqrtP, uint128 liquidity)
        internal pure returns (int24[] memory loHiBest, uint128 liqBest, uint256[] memory optimizedAmounts)
    {
        loHiBest = new int24[](2);
        optimizedAmounts = new uint256[](2);
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(loHiBase[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(loHiBase[1]);

        loHiBest[0] = loHiBase[0];
        loHiBest[1] = loHiBase[1];
        liqBest = liquidity;
        (optimizedAmounts[0], optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);
        uint256[] memory utilizationMinMax = new uint256[](2);
        utilizationMinMax[0] = utilization1e18(optimizedAmounts, initialAmounts, sqrtP);

        /// Traverse all neighboring ticks
        int24 i = loHiBase[0] - MAX_NUM_NEIGHBORHOOD_STEPS * tickSpacing;
        for (; i <= loHiBase[0] + MAX_NUM_NEIGHBORHOOD_STEPS * tickSpacing; i = i + tickSpacing) {
            int24 j = loHiBase[1] - MAX_NUM_NEIGHBORHOOD_STEPS * tickSpacing;
            for (; j <= loHiBase[1] + MAX_NUM_NEIGHBORHOOD_STEPS * tickSpacing; j = j + tickSpacing) {
                // Skip lo >= high and out of tick boundary cases
                if ((i >= j) || (i <= TickMath.MIN_TICK || j >= TickMath.MAX_TICK)) {
                    continue;
                }

                // Get sqrt price for ticks
                sqrtAB[0] = TickMath.getSqrtRatioAtTick(i);
                sqrtAB[1] = TickMath.getSqrtRatioAtTick(j);

                // Check for getting out of center sqrt ratio
                if (sqrtAB[0] >= sqrtP || sqrtAB[1] <= sqrtP) {
                    continue;
                }

                // Calculate liquidity
                liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, sqrtAB[0], sqrtAB[1], initialAmounts[0], initialAmounts[1]);
                if (liquidity == 0) {
                    continue;
                }

                // Get amounts for liquidity
                uint256[] memory amountsForLiquidity = new uint256[](2);
                (amountsForLiquidity[0], amountsForLiquidity[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);

                // Calculate utilization based on initial amounts
                utilizationMinMax[1] = utilization1e18(amountsForLiquidity, initialAmounts, sqrtP);

                // Record values as best if utilization obtained with calculated amounts for liquidity is higher
                if (utilizationMinMax[1] > utilizationMinMax[0]) {
                    loHiBest[0] = i;
                    loHiBest[1] = j;
                    optimizedAmounts[0] = amountsForLiquidity[0];
                    optimizedAmounts[1] = amountsForLiquidity[1];
                    liqBest = liquidity;
                    utilizationMinMax[0] = utilizationMinMax[1];
                }
            }
        }
    }

    /// @dev Finds optimal ticks while fixing lower base tick.
    /// @notice 1. Find ticks via a binary search such that the position consumes all available token0.
    ///         2. Minimally search around to find optimal ranges such that max amounts of token0 and token1 are used.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param lo Raw lower tick candidate: MUST satisfy sqrtP > sqrt(lo).
    /// @param amounts Available token amounts.
    /// @return loHiBest Optimized ticks.
    /// @return liqBest Corresponding liquidity.
    /// @return optimizedAmounts Corresponding amounts.
    function pickHiMaxUtil(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 lo,
        uint256[] calldata amounts
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 liqBest, uint256[] memory optimizedAmounts)
    {
        loHiBest = new int24[](2);
        optimizedAmounts = new uint256[](2);
        loHiBest[0] = lo;

        // hi search range: [first grid above price, MAX_TICK on grid]
        int24[] memory hiMinMax = new int24[](2);
        hiMinMax[0] = _roundUpToSpacing(TickMath.getTickAtSqrtRatio(sqrtP) + 1, tickSpacing);

        // Limit lower tick by lo + tickSpacing
        if (hiMinMax[0] <= loHiBest[0]) {
            hiMinMax[0] = loHiBest[0] + tickSpacing;
        }

        // Check for upper tick limit
        hiMinMax[1] = _roundDownToSpacing(TickMath.MAX_TICK, tickSpacing);
        if (hiMinMax[1] < hiMinMax[0]) {
            hiMinMax[0] = hiMinMax[1];
        }

        // Get sqrt price of lower tick
        uint160 sa = TickMath.getSqrtRatioAtTick(lo);

        // token1-limited liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
        if (liquidity == 0) {
            loHiBest[1] = hiMinMax[0];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // Edge case for hiMin
        uint160 sb = TickMath.getSqrtRatioAtTick(hiMinMax[0]);
        (optimizedAmounts[0], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (optimizedAmounts[0] > amounts[0]) {
            // Even narrowest needs too much token0: cap by amount0 at hiMin
            liqBest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
            liqBest = _min128(liqBest, liquidity);
            
            // Recalculate amounts from liquidity
            (optimizedAmounts[0], optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liqBest);
            loHiBest[1] = hiMinMax[0];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // Edge case for hiMax
        sb = TickMath.getSqrtRatioAtTick(hiMinMax[1]);
        (optimizedAmounts[0], ) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (optimizedAmounts[0] <= amounts[0]) {
            // Widest still fits: take hiMax (cap by amount0 to absorb rounding)
            liqBest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
            liqBest = _min128(liqBest, liquidity);

            // Recalculate amounts from liquidity
            (optimizedAmounts[0], optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liqBest);
            loHiBest[1] = hiMinMax[1];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // minimal hi that satisfies token0 budget
        loHiBest[1] = _iterateRight(hiMinMax[0], hiMinMax[1], tickSpacing, sqrtP, sa, liquidity, amounts[0]);
        sb = TickMath.getSqrtRatioAtTick(loHiBest[1]);

        // Choose min liquidity
        liqBest = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
        liqBest = _min128(liqBest, liquidity);

        return _neighborhoodSearch(loHiBest, amounts, tickSpacing, sqrtP, liqBest);
    }

    /// @dev Executes binary search for lower tick with fixed higher one.
    /// @notice Finds optimal ans ∈ [L, R], such that amount for token1 is biggest.
    /// @param L Left tick value bound.
    /// @param R Right tick value bound.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param sqrtP Right tick sqrt price.
    /// @param liquidity Initial liquidity for token1.
    /// @param amount Corresponding initial amount for token1.
    /// @return Optimal lower tick value with maximized token1 liquidity.
    function _iterateLeft(int24 L, int24 R, int24 tickSpacing, uint160 sqrtP, uint160 sb, uint128 liquidity, uint256 amount)
    internal pure returns (int24)
    {
        int24 ans = R;
        // Binary search while L <= R
        for (uint256 i = 0; i < MAX_NUM_BINARY_STEPS; ++i) {
            int24 steps = (R - L) / tickSpacing;
            int24 mid = L + (steps / 2) * tickSpacing;

            // Get left tick liquidity and token1 amount for provided liquidity
            uint160 saMid = TickMath.getSqrtRatioAtTick(mid);
            (, uint256 optimalAmount) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, saMid, sb, liquidity);

            if (optimalAmount <= amount) {
                // Amounts fits, try wider range
                ans = mid;
                if (mid == R) break;
                R = mid - tickSpacing;
            } else {
                if (mid == L) break;
                // Amounts does not fit, try narrower range
                L = mid + tickSpacing;
            }

            // Break condition: L > R (lower lo candidate tick is bigger than higher lo one)
            if (L > R) break;
        }

        return ans;
    }

    /// @dev Finds optimal ticks while fixing upper base tick.
    /// @notice 1. Find ticks via a binary search such that the position consumes all available token1.
    ///         2. Minimally search around to find optimal ranges such that max amounts of token0 and token1 are used.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param hi upper tick candidate: MUST satisfy sqrtP < sqrt(hi).
    /// @param amounts Available token amounts.
    /// @return loHiBest Optimized ticks.
    /// @return liqBest Corresponding liquidity.
    /// @return optimizedAmounts Corresponding amounts.
    function pickLoMaxUtil(
        int24 tickSpacing,
        uint160 sqrtP,
        int24 hi,
        uint256[] calldata amounts
    )
    public
    pure
    returns (int24[] memory loHiBest, uint128 liqBest, uint256[] memory optimizedAmounts)
    {
        loHiBest = new int24[](2);
        optimizedAmounts = new uint256[](2);
        loHiBest[1] = hi;

        // hi search range: [first grid above price, MAX_TICK on grid]
        int24[] memory loMinMax = new int24[](2);
        loMinMax[1] = _roundDownToSpacing(TickMath.getTickAtSqrtRatio(sqrtP) - 1, tickSpacing);

        // Limit higher tick by hi - tickSpacing
        if (loMinMax[1] >= loHiBest[1]) {
            loMinMax[1] = loHiBest[1] - tickSpacing;
        }

        // Check for lower tick limit
        loMinMax[0] = _roundUpToSpacing(TickMath.MIN_TICK, tickSpacing);
        if (loMinMax[0] > loMinMax[1]) {
            loMinMax[1] = loMinMax[0];
        }

        // Get sqrt price of higher tick
        uint160 sb = TickMath.getSqrtRatioAtTick(hi);

        // token0-limited liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sb, amounts[0]);
        if (liquidity == 0) {
            loHiBest[0] = loMinMax[1];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // Edge case for loMin
        uint160 sa = TickMath.getSqrtRatioAtTick(loMinMax[0]);
        (, optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (optimizedAmounts[1] <= amounts[1]) {
            liqBest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
            liqBest = _min128(liqBest, liquidity);

            // Recalculate amounts from liquidity
            (optimizedAmounts[0], optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liqBest);
            loHiBest[0] = loMinMax[0];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // Edge case for loMax
        sa = TickMath.getSqrtRatioAtTick(loMinMax[1]);
        (, optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liquidity);
        if (optimizedAmounts[1] > amounts[1]) {
            liqBest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
            liqBest = _min128(liqBest, liquidity);

            // Recalculate amounts from liquidity
            (optimizedAmounts[0], optimizedAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sa, sb, liqBest);
            loHiBest[0] = loMinMax[1];
            return (loHiBest, liqBest, optimizedAmounts);
        }

        // minimal lo that satisfies token1 budget
        loHiBest[0] = _iterateLeft(loMinMax[0], loMinMax[1], tickSpacing, sqrtP, sb, liquidity, amounts[1]);
        sa = TickMath.getSqrtRatioAtTick(loHiBest[0]);

        // Choose min liquidity
        liqBest = LiquidityAmounts.getLiquidityForAmount1(sa, sqrtP, amounts[1]);
        liqBest = _min128(liqBest, liquidity);

        return _neighborhoodSearch(loHiBest, amounts, tickSpacing, sqrtP, liqBest);
    }

    /// @dev Snap down to tick grid.
    /// @param tick Tick value.
    /// @param spacing Tick spacing.
    /// @return Tick value rounded down to tick grid.
    function _roundDownToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick % spacing;
        return r == 0 ? tick : (r > 0 ? tick - r : tick - (r + spacing));
    }

    /// @dev Snap up to tick grid.
    /// @param tick Tick value.
    /// @param spacing Tick spacing.
    /// @return Tick value rounded up to tick grid.
    function _roundUpToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick % spacing;
        return r == 0 ? tick : (r > 0 ? tick + (spacing - r) : tick - r);
    }

    /// @dev Chooses min from given two values.
    /// @param x Value x.
    /// @param y Value y.
    /// @return MIN(x, y).
    function _min128(uint128 x, uint128 y) internal pure returns (uint128) {
        return x < y ? x : y;
    }

    /// @dev Calculates amount value in token1-value: amount * P, where P = (sqrtP^2)/2^192.
    /// @param amount Amount value.
    /// @param sqrtP Sqrt price.
    function value0InToken1(uint256 amount, uint160 sqrtP) internal pure returns (uint256) {
        if (amount == 0) return 0;
        // amount * sqrtP / 2^96
        uint256 intermediate = FullMath.mulDiv(amount, sqrtP, FixedPoint96.Q96);
        // (amount * sqrtP / 2^96) * sqrtP / 2^96  == amount * (sqrtP^2) / 2^192
        return FullMath.mulDiv(intermediate, sqrtP, FixedPoint96.Q96);
    }

    /// @dev Calculates accumulated value of (amounts[0], amounts[1]) in token1-value.
    /// @param amounts Token amounts array.
    /// @param sqrtP Sqrt price.
    function valueInToken1(uint256[] memory amounts, uint160 sqrtP) internal pure returns (uint256) {
        return value0InToken1(amounts[0], sqrtP) + amounts[1];
    }

    /// @dev Calculates utilization metrics (0..1e18) according to accumulated token value (in token1-value).
    /// @param optimizedAmounts Optimized token amounts.
    /// @param initialAmounts Initial token amounts.
    /// @param sqrtP Sqrt price.
    /// @return Utilization metrics: 1e18 is most optimal.
    function utilization1e18(
        uint256[] memory optimizedAmounts,
        uint256[] memory initialAmounts,
        uint160 sqrtP
    ) internal pure returns (uint256) {
        uint256 valUsed  = valueInToken1(optimizedAmounts, sqrtP);
        uint256 valTotal = valueInToken1(initialAmounts, sqrtP);
        if (valTotal == 0) return 0;
        return FullMath.mulDiv(valUsed, 1e18, valTotal);
    }

    /// @dev Chooses search direction according to he balance value one against another: which one needs to be fixed.
    /// @param amounts Token amounts.
    /// @param sqrtP Sqrt price.
    function _chooseMode(
        uint256[] calldata amounts,
        uint160 sqrtP
    ) internal pure returns (bool) {
        // Calculate V0 ~ b0*P and compare with V1 ~ b1
        uint256 V0 = value0InToken1(amounts[0], sqrtP);
        uint256 V1 = amounts[1];

        // Check balance inequality
        return (V0 >= V1);
    }
    
    /// @dev Scans neighborhood with binary search and locally based on amounts[0] or amounts[1] in absolute token value.
    /// @notice ticks[0] is used for pickHiMaxUtil, ticks[0] - for pickLoMaxUtil.
    /// @param tickSpacing Tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param ticks Initial tick values.
    /// @param amounts Initial token amounts.
    /// @return loHiBest Optimized ticks.
    /// @return liqBest Corresponding liquidity.
    /// @return optimizedAmounts Corresponding amounts.
    function _scanNeighborhood(
        int24 tickSpacing,
        uint160 sqrtP,
        int24[] memory ticks,
        uint256[] calldata amounts
    )
    internal
    pure
    returns (
        int24[] memory loHiBest,
        uint128 liqBest,
        uint256[] memory optimizedAmounts
    )
    {
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        bool optimizeHi = _chooseMode(amounts, sqrtP);

        if (optimizeHi) {
            return pickHiMaxUtil(tickSpacing, sqrtP, ticks[0], amounts);
        } else {
            return pickLoMaxUtil(tickSpacing, sqrtP, ticks[1], amounts);
        }
    }
}
