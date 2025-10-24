// Sources flattened with hardhat v2.25.0 https://hardhat.org

// SPDX-License-Identifier: GPL-2.0-or-later AND MIT
pragma solidity ^0.8.0;

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}


// File contracts/libraries/FullMath.sol
/// @title Contains 512-bit math functions
/// @notice Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision
/// @dev Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits
library FullMath {
    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = a * b
            // Compute the product mod 2**256 and mod 2**256 - 1
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2**256 + prod0
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division
            if (prod1 == 0) {
                require(denominator > 0);
                assembly {
                    result := div(prod0, denominator)
                }
                return result;
            }

            // Make sure the result is less than 2**256.
            // Also prevents denominator == 0
            require(denominator > prod1);

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0]
            // Compute remainder using mulmod
            uint256 remainder;
            assembly {
                remainder := mulmod(a, b, denominator)
            }
            // Subtract 256 bit number from 512 bit number
            assembly {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator
            // Compute largest power of two divisor of denominator.
            // Always >= 1.
            uint256 twos = (0 - denominator) & denominator;
            // Divide denominator by power of two
            assembly {
                denominator := div(denominator, twos)
            }

            // Divide [prod1 prod0] by the factors of two
            assembly {
                prod0 := div(prod0, twos)
            }
            // Shift in bits from prod1 into prod0. For this we need
            // to flip `twos` such that it is 2**256 / twos.
            // If twos is zero, then it becomes one
            assembly {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            // Invert denominator mod 2**256
            // Now that denominator is an odd number, it has an inverse
            // modulo 2**256 such that denominator * inv = 1 mod 2**256.
            // Compute the inverse by starting with a seed that is correct
            // correct for four bits. That is, denominator * inv = 1 mod 2**4
            uint256 inv = (3 * denominator) ^ 2;
            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv *= 2 - denominator * inv; // inverse mod 2**8
            inv *= 2 - denominator * inv; // inverse mod 2**16
            inv *= 2 - denominator * inv; // inverse mod 2**32
            inv *= 2 - denominator * inv; // inverse mod 2**64
            inv *= 2 - denominator * inv; // inverse mod 2**128
            inv *= 2 - denominator * inv; // inverse mod 2**256

            // Because the division is now exact we can divide by multiplying
            // with the modular inverse of denominator. This will give us the
            // correct result modulo 2**256. Since the precoditions guarantee
            // that the outcome is less than 2**256, this is the final result.
            // We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inv;
            return result;
        }
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            result = mulDiv(a, b, denominator);
            if (mulmod(a, b, denominator) > 0) {
                require(result < type(uint256).max);
                result++;
            }
        }
    }
}


// File contracts/libraries/LiquidityAmounts.sol
/// @title Liquidity amount functions
/// @notice Provides functions for computing liquidity amounts from token amounts and prices
library LiquidityAmounts {
    /// @notice Downcasts uint256 to uint128
    /// @param x The uint258 to be downcasted
    /// @return y The passed value, downcasted to uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount0 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        unchecked {
            return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
        }
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        unchecked {
            return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
        }
    }

    /// @notice Computes the maximum amount of liquidity received for a given amount of token0, token1, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount of token0 being sent in
    /// @param amount1 The amount of token1 being sent in
    /// @return liquidity The maximum amount of liquidity received
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            return
                FullMath.mulDiv(
                    uint256(liquidity) << FixedPoint96.RESOLUTION,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    sqrtRatioBX96
                ) / sqrtRatioAX96;
        }
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount1 The amount of token1
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        unchecked {
            return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
        }
    }

    /// @notice Computes the token0 and token1 value for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }
}


// File contracts/libraries/TickMath.sol
/// @title Math library for computing sqrt prices from ticks and vice versa
/// @notice Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports
/// prices between 2**-128 and 2**128
library TickMath {
    error T();
    error R();

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
    /// at the given tick
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
            if (absTick > uint256(int256(MAX_TICK))) revert T();

            uint256 ratio = absTick & 0x1 != 0
                ? 0xfffcb933bd6fad37aa2d162d1a594001
                : 0x100000000000000000000000000000000;
            if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

            if (tick > 0) ratio = type(uint256).max / ratio;

            // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
            // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
            // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
            sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
        }
    }

    /// @notice Calculates the greatest tick value such that getRatioAtTick(tick) <= ratio
    /// @dev Throws in case sqrtPriceX96 < MIN_SQRT_RATIO, as MIN_SQRT_RATIO is the lowest value getRatioAtTick may
    /// ever return.
    /// @param sqrtPriceX96 The sqrt ratio for which to compute the tick as a Q64.96
    /// @return tick The greatest tick for which the ratio is less than or equal to the input ratio
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        unchecked {
            // second inequality must be < because the price can never reach the price at the max tick
            if (!(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO)) revert R();
            uint256 ratio = uint256(sqrtPriceX96) << 32;

            uint256 r = ratio;
            uint256 msb = 0;

            assembly {
                let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(5, gt(r, 0xFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(4, gt(r, 0xFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(3, gt(r, 0xFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(2, gt(r, 0xF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(1, gt(r, 0x3))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := gt(r, 0x1)
                msb := or(msb, f)
            }

            if (msb >= 128) r = ratio >> (msb - 127);
            else r = ratio << (127 - msb);

            int256 log_2 = (int256(msb) - 128) << 64;

            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(63, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(62, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(61, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(60, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(59, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(58, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(57, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(56, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(55, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(54, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(53, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(52, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(51, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(50, f))
            }

            int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number

            int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
            int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

            tick = tickLow == tickHi ? tickLow : getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
        }
    }
}


// File contracts/pol/NeighborhoodScanner.sol
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
