// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 >=0.5.0 >=0.8.0 >=0.8.19 ^0.8.0 ^0.8.18 ^0.8.28 ^0.8.30;

// node_modules/@prb/math/src/Common.sol

// Common.sol
//
// Common mathematical functions used in both SD59x18 and UD60x18. Note that these global functions do not
// always operate with SD59x18 and UD60x18 numbers.

/*//////////////////////////////////////////////////////////////////////////
                                CUSTOM ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when the resultant value in {mulDiv} overflows uint256.
error PRBMath_MulDiv_Overflow(uint256 x, uint256 y, uint256 denominator);

/// @notice Thrown when the resultant value in {mulDiv18} overflows uint256.
error PRBMath_MulDiv18_Overflow(uint256 x, uint256 y);

/// @notice Thrown when one of the inputs passed to {mulDivSigned} is `type(int256).min`.
error PRBMath_MulDivSigned_InputTooSmall();

/// @notice Thrown when the resultant value in {mulDivSigned} overflows int256.
error PRBMath_MulDivSigned_Overflow(int256 x, int256 y);

/*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
//////////////////////////////////////////////////////////////////////////*/

/// @dev The maximum value a uint128 number can have.
uint128 constant MAX_UINT128 = type(uint128).max;

/// @dev The maximum value a uint40 number can have.
uint40 constant MAX_UINT40 = type(uint40).max;

/// @dev The unit number, which the decimal precision of the fixed-point types.
uint256 constant UNIT = 1e18;

/// @dev The unit number inverted mod 2^256.
uint256 constant UNIT_INVERSE = 78156646155174841979727994598816262306175212592076161876661_508869554232690281;

/// @dev The the largest power of two that divides the decimal value of `UNIT`. The logarithm of this value is the least significant
/// bit in the binary representation of `UNIT`.
uint256 constant UNIT_LPOTD = 262144;

/*//////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Calculates the binary exponent of x using the binary fraction method.
/// @dev Has to use 192.64-bit fixed-point numbers. See https://ethereum.stackexchange.com/a/96594/24693.
/// @param x The exponent as an unsigned 192.64-bit fixed-point number.
/// @return result The result as an unsigned 60.18-decimal fixed-point number.
/// @custom:smtchecker abstract-function-nondet
function exp2(uint256 x) pure returns (uint256 result) {
    unchecked {
        // Start from 0.5 in the 192.64-bit fixed-point format.
        result = 0x800000000000000000000000000000000000000000000000;

        // The following logic multiplies the result by $\sqrt{2^{-i}}$ when the bit at position i is 1. Key points:
        //
        // 1. Intermediate results will not overflow, as the starting point is 2^191 and all magic factors are under 2^65.
        // 2. The rationale for organizing the if statements into groups of 8 is gas savings. If the result of performing
        // a bitwise AND operation between x and any value in the array [0x80; 0x40; 0x20; 0x10; 0x08; 0x04; 0x02; 0x01] is 1,
        // we know that `x & 0xFF` is also 1.
        if (x & 0xFF00000000000000 > 0) {
            if (x & 0x8000000000000000 > 0) {
                result = (result * 0x16A09E667F3BCC909) >> 64;
            }
            if (x & 0x4000000000000000 > 0) {
                result = (result * 0x1306FE0A31B7152DF) >> 64;
            }
            if (x & 0x2000000000000000 > 0) {
                result = (result * 0x1172B83C7D517ADCE) >> 64;
            }
            if (x & 0x1000000000000000 > 0) {
                result = (result * 0x10B5586CF9890F62A) >> 64;
            }
            if (x & 0x800000000000000 > 0) {
                result = (result * 0x1059B0D31585743AE) >> 64;
            }
            if (x & 0x400000000000000 > 0) {
                result = (result * 0x102C9A3E778060EE7) >> 64;
            }
            if (x & 0x200000000000000 > 0) {
                result = (result * 0x10163DA9FB33356D8) >> 64;
            }
            if (x & 0x100000000000000 > 0) {
                result = (result * 0x100B1AFA5ABCBED61) >> 64;
            }
        }

        if (x & 0xFF000000000000 > 0) {
            if (x & 0x80000000000000 > 0) {
                result = (result * 0x10058C86DA1C09EA2) >> 64;
            }
            if (x & 0x40000000000000 > 0) {
                result = (result * 0x1002C605E2E8CEC50) >> 64;
            }
            if (x & 0x20000000000000 > 0) {
                result = (result * 0x100162F3904051FA1) >> 64;
            }
            if (x & 0x10000000000000 > 0) {
                result = (result * 0x1000B175EFFDC76BA) >> 64;
            }
            if (x & 0x8000000000000 > 0) {
                result = (result * 0x100058BA01FB9F96D) >> 64;
            }
            if (x & 0x4000000000000 > 0) {
                result = (result * 0x10002C5CC37DA9492) >> 64;
            }
            if (x & 0x2000000000000 > 0) {
                result = (result * 0x1000162E525EE0547) >> 64;
            }
            if (x & 0x1000000000000 > 0) {
                result = (result * 0x10000B17255775C04) >> 64;
            }
        }

        if (x & 0xFF0000000000 > 0) {
            if (x & 0x800000000000 > 0) {
                result = (result * 0x1000058B91B5BC9AE) >> 64;
            }
            if (x & 0x400000000000 > 0) {
                result = (result * 0x100002C5C89D5EC6D) >> 64;
            }
            if (x & 0x200000000000 > 0) {
                result = (result * 0x10000162E43F4F831) >> 64;
            }
            if (x & 0x100000000000 > 0) {
                result = (result * 0x100000B1721BCFC9A) >> 64;
            }
            if (x & 0x80000000000 > 0) {
                result = (result * 0x10000058B90CF1E6E) >> 64;
            }
            if (x & 0x40000000000 > 0) {
                result = (result * 0x1000002C5C863B73F) >> 64;
            }
            if (x & 0x20000000000 > 0) {
                result = (result * 0x100000162E430E5A2) >> 64;
            }
            if (x & 0x10000000000 > 0) {
                result = (result * 0x1000000B172183551) >> 64;
            }
        }

        if (x & 0xFF00000000 > 0) {
            if (x & 0x8000000000 > 0) {
                result = (result * 0x100000058B90C0B49) >> 64;
            }
            if (x & 0x4000000000 > 0) {
                result = (result * 0x10000002C5C8601CC) >> 64;
            }
            if (x & 0x2000000000 > 0) {
                result = (result * 0x1000000162E42FFF0) >> 64;
            }
            if (x & 0x1000000000 > 0) {
                result = (result * 0x10000000B17217FBB) >> 64;
            }
            if (x & 0x800000000 > 0) {
                result = (result * 0x1000000058B90BFCE) >> 64;
            }
            if (x & 0x400000000 > 0) {
                result = (result * 0x100000002C5C85FE3) >> 64;
            }
            if (x & 0x200000000 > 0) {
                result = (result * 0x10000000162E42FF1) >> 64;
            }
            if (x & 0x100000000 > 0) {
                result = (result * 0x100000000B17217F8) >> 64;
            }
        }

        if (x & 0xFF000000 > 0) {
            if (x & 0x80000000 > 0) {
                result = (result * 0x10000000058B90BFC) >> 64;
            }
            if (x & 0x40000000 > 0) {
                result = (result * 0x1000000002C5C85FE) >> 64;
            }
            if (x & 0x20000000 > 0) {
                result = (result * 0x100000000162E42FF) >> 64;
            }
            if (x & 0x10000000 > 0) {
                result = (result * 0x1000000000B17217F) >> 64;
            }
            if (x & 0x8000000 > 0) {
                result = (result * 0x100000000058B90C0) >> 64;
            }
            if (x & 0x4000000 > 0) {
                result = (result * 0x10000000002C5C860) >> 64;
            }
            if (x & 0x2000000 > 0) {
                result = (result * 0x1000000000162E430) >> 64;
            }
            if (x & 0x1000000 > 0) {
                result = (result * 0x10000000000B17218) >> 64;
            }
        }

        if (x & 0xFF0000 > 0) {
            if (x & 0x800000 > 0) {
                result = (result * 0x1000000000058B90C) >> 64;
            }
            if (x & 0x400000 > 0) {
                result = (result * 0x100000000002C5C86) >> 64;
            }
            if (x & 0x200000 > 0) {
                result = (result * 0x10000000000162E43) >> 64;
            }
            if (x & 0x100000 > 0) {
                result = (result * 0x100000000000B1721) >> 64;
            }
            if (x & 0x80000 > 0) {
                result = (result * 0x10000000000058B91) >> 64;
            }
            if (x & 0x40000 > 0) {
                result = (result * 0x1000000000002C5C8) >> 64;
            }
            if (x & 0x20000 > 0) {
                result = (result * 0x100000000000162E4) >> 64;
            }
            if (x & 0x10000 > 0) {
                result = (result * 0x1000000000000B172) >> 64;
            }
        }

        if (x & 0xFF00 > 0) {
            if (x & 0x8000 > 0) {
                result = (result * 0x100000000000058B9) >> 64;
            }
            if (x & 0x4000 > 0) {
                result = (result * 0x10000000000002C5D) >> 64;
            }
            if (x & 0x2000 > 0) {
                result = (result * 0x1000000000000162E) >> 64;
            }
            if (x & 0x1000 > 0) {
                result = (result * 0x10000000000000B17) >> 64;
            }
            if (x & 0x800 > 0) {
                result = (result * 0x1000000000000058C) >> 64;
            }
            if (x & 0x400 > 0) {
                result = (result * 0x100000000000002C6) >> 64;
            }
            if (x & 0x200 > 0) {
                result = (result * 0x10000000000000163) >> 64;
            }
            if (x & 0x100 > 0) {
                result = (result * 0x100000000000000B1) >> 64;
            }
        }

        if (x & 0xFF > 0) {
            if (x & 0x80 > 0) {
                result = (result * 0x10000000000000059) >> 64;
            }
            if (x & 0x40 > 0) {
                result = (result * 0x1000000000000002C) >> 64;
            }
            if (x & 0x20 > 0) {
                result = (result * 0x10000000000000016) >> 64;
            }
            if (x & 0x10 > 0) {
                result = (result * 0x1000000000000000B) >> 64;
            }
            if (x & 0x8 > 0) {
                result = (result * 0x10000000000000006) >> 64;
            }
            if (x & 0x4 > 0) {
                result = (result * 0x10000000000000003) >> 64;
            }
            if (x & 0x2 > 0) {
                result = (result * 0x10000000000000001) >> 64;
            }
            if (x & 0x1 > 0) {
                result = (result * 0x10000000000000001) >> 64;
            }
        }

        // In the code snippet below, two operations are executed simultaneously:
        //
        // 1. The result is multiplied by $(2^n + 1)$, where $2^n$ represents the integer part, and the additional 1
        // accounts for the initial guess of 0.5. This is achieved by subtracting from 191 instead of 192.
        // 2. The result is then converted to an unsigned 60.18-decimal fixed-point format.
        //
        // The underlying logic is based on the relationship $2^{191-ip} = 2^{ip} / 2^{191}$, where $ip$ denotes the,
        // integer part, $2^n$.
        result *= UNIT;
        result >>= (191 - (x >> 64));
    }
}

/// @notice Finds the zero-based index of the first 1 in the binary representation of x.
///
/// @dev See the note on "msb" in this Wikipedia article: https://en.wikipedia.org/wiki/Find_first_set
///
/// Each step in this implementation is equivalent to this high-level code:
///
/// ```solidity
/// if (x >= 2 ** 128) {
///     x >>= 128;
///     result += 128;
/// }
/// ```
///
/// Where 128 is replaced with each respective power of two factor. See the full high-level implementation here:
/// https://gist.github.com/PaulRBerg/f932f8693f2733e30c4d479e8e980948
///
/// The Yul instructions used below are:
///
/// - "gt" is "greater than"
/// - "or" is the OR bitwise operator
/// - "shl" is "shift left"
/// - "shr" is "shift right"
///
/// @param x The uint256 number for which to find the index of the most significant bit.
/// @return result The index of the most significant bit as a uint256.
/// @custom:smtchecker abstract-function-nondet
function msb(uint256 x) pure returns (uint256 result) {
    // 2^128
    assembly ("memory-safe") {
        let factor := shl(7, gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^64
    assembly ("memory-safe") {
        let factor := shl(6, gt(x, 0xFFFFFFFFFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^32
    assembly ("memory-safe") {
        let factor := shl(5, gt(x, 0xFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^16
    assembly ("memory-safe") {
        let factor := shl(4, gt(x, 0xFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^8
    assembly ("memory-safe") {
        let factor := shl(3, gt(x, 0xFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^4
    assembly ("memory-safe") {
        let factor := shl(2, gt(x, 0xF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^2
    assembly ("memory-safe") {
        let factor := shl(1, gt(x, 0x3))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^1
    // No need to shift x any more.
    assembly ("memory-safe") {
        let factor := gt(x, 0x1)
        result := or(result, factor)
    }
}

/// @notice Calculates x*y÷denominator with 512-bit precision.
///
/// @dev Credits to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv.
///
/// Notes:
/// - The result is rounded toward zero.
///
/// Requirements:
/// - The denominator must not be zero.
/// - The result must fit in uint256.
///
/// @param x The multiplicand as a uint256.
/// @param y The multiplier as a uint256.
/// @param denominator The divisor as a uint256.
/// @return result The result as a uint256.
/// @custom:smtchecker abstract-function-nondet
function mulDiv(uint256 x, uint256 y, uint256 denominator) pure returns (uint256 result) {
    // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
    // use the Chinese Remainder Theorem to reconstruct the 512-bit result. The result is stored in two 256
    // variables such that product = prod1 * 2^256 + prod0.
    uint256 prod0; // Least significant 256 bits of the product
    uint256 prod1; // Most significant 256 bits of the product
    assembly ("memory-safe") {
        let mm := mulmod(x, y, not(0))
        prod0 := mul(x, y)
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    // Handle non-overflow cases, 256 by 256 division.
    if (prod1 == 0) {
        unchecked {
            return prod0 / denominator;
        }
    }

    // Make sure the result is less than 2^256. Also prevents denominator == 0.
    if (prod1 >= denominator) {
        revert PRBMath_MulDiv_Overflow(x, y, denominator);
    }

    ////////////////////////////////////////////////////////////////////////////
    // 512 by 256 division
    ////////////////////////////////////////////////////////////////////////////

    // Make division exact by subtracting the remainder from [prod1 prod0].
    uint256 remainder;
    assembly ("memory-safe") {
        // Compute remainder using the mulmod Yul instruction.
        remainder := mulmod(x, y, denominator)

        // Subtract 256 bit number from 512-bit number.
        prod1 := sub(prod1, gt(remainder, prod0))
        prod0 := sub(prod0, remainder)
    }

    unchecked {
        // Calculate the largest power of two divisor of the denominator using the unary operator ~. This operation cannot overflow
        // because the denominator cannot be zero at this point in the function execution. The result is always >= 1.
        // For more detail, see https://cs.stackexchange.com/q/138556/92363.
        uint256 lpotdod = denominator & (~denominator + 1);
        uint256 flippedLpotdod;

        assembly ("memory-safe") {
            // Factor powers of two out of denominator.
            denominator := div(denominator, lpotdod)

            // Divide [prod1 prod0] by lpotdod.
            prod0 := div(prod0, lpotdod)

            // Get the flipped value `2^256 / lpotdod`. If the `lpotdod` is zero, the flipped value is one.
            // `sub(0, lpotdod)` produces the two's complement version of `lpotdod`, which is equivalent to flipping all the bits.
            // However, `div` interprets this value as an unsigned value: https://ethereum.stackexchange.com/q/147168/24693
            flippedLpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
        }

        // Shift in bits from prod1 into prod0.
        prod0 |= prod1 * flippedLpotdod;

        // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
        // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
        // four bits. That is, denominator * inv = 1 mod 2^4.
        uint256 inverse = (3 * denominator) ^ 2;

        // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
        // in modular arithmetic, doubling the correct bits in each step.
        inverse *= 2 - denominator * inverse; // inverse mod 2^8
        inverse *= 2 - denominator * inverse; // inverse mod 2^16
        inverse *= 2 - denominator * inverse; // inverse mod 2^32
        inverse *= 2 - denominator * inverse; // inverse mod 2^64
        inverse *= 2 - denominator * inverse; // inverse mod 2^128
        inverse *= 2 - denominator * inverse; // inverse mod 2^256

        // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
        // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
        // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inverse;
    }
}

/// @notice Calculates x*y÷1e18 with 512-bit precision.
///
/// @dev A variant of {mulDiv} with constant folding, i.e. in which the denominator is hard coded to 1e18.
///
/// Notes:
/// - The body is purposely left uncommented; to understand how this works, see the documentation in {mulDiv}.
/// - The result is rounded toward zero.
/// - We take as an axiom that the result cannot be `MAX_UINT256` when x and y solve the following system of equations:
///
/// $$
/// \begin{cases}
///     x * y = MAX\_UINT256 * UNIT \\
///     (x * y) \% UNIT \geq \frac{UNIT}{2}
/// \end{cases}
/// $$
///
/// Requirements:
/// - Refer to the requirements in {mulDiv}.
/// - The result must fit in uint256.
///
/// @param x The multiplicand as an unsigned 60.18-decimal fixed-point number.
/// @param y The multiplier as an unsigned 60.18-decimal fixed-point number.
/// @return result The result as an unsigned 60.18-decimal fixed-point number.
/// @custom:smtchecker abstract-function-nondet
function mulDiv18(uint256 x, uint256 y) pure returns (uint256 result) {
    uint256 prod0;
    uint256 prod1;
    assembly ("memory-safe") {
        let mm := mulmod(x, y, not(0))
        prod0 := mul(x, y)
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    if (prod1 == 0) {
        unchecked {
            return prod0 / UNIT;
        }
    }

    if (prod1 >= UNIT) {
        revert PRBMath_MulDiv18_Overflow(x, y);
    }

    uint256 remainder;
    assembly ("memory-safe") {
        remainder := mulmod(x, y, UNIT)
        result :=
            mul(
                or(
                    div(sub(prod0, remainder), UNIT_LPOTD),
                    mul(sub(prod1, gt(remainder, prod0)), add(div(sub(0, UNIT_LPOTD), UNIT_LPOTD), 1))
                ),
                UNIT_INVERSE
            )
    }
}

/// @notice Calculates x*y÷denominator with 512-bit precision.
///
/// @dev This is an extension of {mulDiv} for signed numbers, which works by computing the signs and the absolute values separately.
///
/// Notes:
/// - The result is rounded toward zero.
///
/// Requirements:
/// - Refer to the requirements in {mulDiv}.
/// - None of the inputs can be `type(int256).min`.
/// - The result must fit in int256.
///
/// @param x The multiplicand as an int256.
/// @param y The multiplier as an int256.
/// @param denominator The divisor as an int256.
/// @return result The result as an int256.
/// @custom:smtchecker abstract-function-nondet
function mulDivSigned(int256 x, int256 y, int256 denominator) pure returns (int256 result) {
    if (x == type(int256).min || y == type(int256).min || denominator == type(int256).min) {
        revert PRBMath_MulDivSigned_InputTooSmall();
    }

    // Get hold of the absolute values of x, y and the denominator.
    uint256 xAbs;
    uint256 yAbs;
    uint256 dAbs;
    unchecked {
        xAbs = x < 0 ? uint256(-x) : uint256(x);
        yAbs = y < 0 ? uint256(-y) : uint256(y);
        dAbs = denominator < 0 ? uint256(-denominator) : uint256(denominator);
    }

    // Compute the absolute value of x*y÷denominator. The result must fit in int256.
    uint256 resultAbs = mulDiv(xAbs, yAbs, dAbs);
    if (resultAbs > uint256(type(int256).max)) {
        revert PRBMath_MulDivSigned_Overflow(x, y);
    }

    // Get the signs of x, y and the denominator.
    uint256 sx;
    uint256 sy;
    uint256 sd;
    assembly ("memory-safe") {
        // "sgt" is the "signed greater than" assembly instruction and "sub(0,1)" is -1 in two's complement.
        sx := sgt(x, sub(0, 1))
        sy := sgt(y, sub(0, 1))
        sd := sgt(denominator, sub(0, 1))
    }

    // XOR over sx, sy and sd. What this does is to check whether there are 1 or 3 negative signs in the inputs.
    // If there are, the result should be negative. Otherwise, it should be positive.
    unchecked {
        result = sx ^ sy ^ sd == 0 ? -int256(resultAbs) : int256(resultAbs);
    }
}

/// @notice Calculates the square root of x using the Babylonian method.
///
/// @dev See https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
///
/// Notes:
/// - If x is not a perfect square, the result is rounded down.
/// - Credits to OpenZeppelin for the explanations in comments below.
///
/// @param x The uint256 number for which to calculate the square root.
/// @return result The result as a uint256.
/// @custom:smtchecker abstract-function-nondet
function sqrt(uint256 x) pure returns (uint256 result) {
    if (x == 0) {
        return 0;
    }

    // For our first guess, we calculate the biggest power of 2 which is smaller than the square root of x.
    //
    // We know that the "msb" (most significant bit) of x is a power of 2 such that we have:
    //
    // $$
    // msb(x) <= x <= 2*msb(x)$
    // $$
    //
    // We write $msb(x)$ as $2^k$, and we get:
    //
    // $$
    // k = log_2(x)
    // $$
    //
    // Thus, we can write the initial inequality as:
    //
    // $$
    // 2^{log_2(x)} <= x <= 2*2^{log_2(x)+1} \\
    // sqrt(2^k) <= sqrt(x) < sqrt(2^{k+1}) \\
    // 2^{k/2} <= sqrt(x) < 2^{(k+1)/2} <= 2^{(k/2)+1}
    // $$
    //
    // Consequently, $2^{log_2(x) /2} is a good first approximation of sqrt(x) with at least one correct bit.
    uint256 xAux = uint256(x);
    result = 1;
    if (xAux >= 2 ** 128) {
        xAux >>= 128;
        result <<= 64;
    }
    if (xAux >= 2 ** 64) {
        xAux >>= 64;
        result <<= 32;
    }
    if (xAux >= 2 ** 32) {
        xAux >>= 32;
        result <<= 16;
    }
    if (xAux >= 2 ** 16) {
        xAux >>= 16;
        result <<= 8;
    }
    if (xAux >= 2 ** 8) {
        xAux >>= 8;
        result <<= 4;
    }
    if (xAux >= 2 ** 4) {
        xAux >>= 4;
        result <<= 2;
    }
    if (xAux >= 2 ** 2) {
        result <<= 1;
    }

    // At this point, `result` is an estimation with at least one bit of precision. We know the true value has at
    // most 128 bits, since it is the square root of a uint256. Newton's method converges quadratically (precision
    // doubles at every iteration). We thus need at most 7 iteration to turn our partial result with one bit of
    // precision into the expected uint128 result.
    unchecked {
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;

        // If x is not a perfect square, round the result toward zero.
        uint256 roundedResult = x / result;
        if (result >= roundedResult) {
            result = roundedResult;
        }
    }
}

// lib/solmate/src/tokens/ERC721.sol

/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) internal _ownerOf;

    mapping(address => uint256) internal _balanceOf;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        require((owner = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == _ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];

        require(owner != address(0), "NOT_MINTED");

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

// contracts/libraries/FixedPoint96.sol

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}

// lib/solmate/src/utils/FixedPointMathLib.sol

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library FixedPointMathLib {
    /*//////////////////////////////////////////////////////////////
                    SIMPLIFIED FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WAD = 1e18; // The scalar of ETH and most ERC20s.

    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD); // Equivalent to (x * y) / WAD rounded down.
    }

    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD); // Equivalent to (x * y) / WAD rounded up.
    }

    function divWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y); // Equivalent to (x * WAD) / y rounded down.
    }

    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y); // Equivalent to (x * WAD) / y rounded up.
    }

    function powWad(int256 x, int256 y) internal pure returns (int256) {
        // Equivalent to x to the power of y because x ** y = (e ** ln(x)) ** y = e ** (ln(x) * y)
        return expWad((lnWad(x) * y) / int256(WAD)); // Using ln(x) means x must be greater than 0.
    }

    function expWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            // When the result is < 0.5 we return zero. This happens when
            // x <= floor(log(0.5e18) * 1e18) ~ -42e18
            if (x <= -42139678854452767551) return 0;

            // When the result is > (2**255 - 1) / 1e18 we can not represent it as an
            // int. This happens when x >= floor(log((2**255 - 1) / 1e18) * 1e18) ~ 135.
            if (x >= 135305999368893231589) revert("EXP_OVERFLOW");

            // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
            // for more intermediate precision and a binary basis. This base conversion
            // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / 5**18;

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
            // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
            // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
            int256 k = ((x << 96) / 54916777467707473351141471128 + 2**95) >> 96;
            x = x - k * 54916777467707473351141471128;

            // k is in the range [-61, 195].

            // Evaluate using a (6, 7)-term rational approximation.
            // p is made monic, we'll multiply by a scale factor later.
            int256 y = x + 1346386616545796478920950773328;
            y = ((y * x) >> 96) + 57155421227552351082224309758442;
            int256 p = y + x - 94201549194550492254356042504812;
            p = ((p * y) >> 96) + 28719021644029726153956944680412240;
            p = p * x + (4385272521454847904659076985693276 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            int256 q = x - 2855989394907223263936484059900;
            q = ((q * x) >> 96) + 50020603652535783019961831881945;
            q = ((q * x) >> 96) - 533845033583426703283633433725380;
            q = ((q * x) >> 96) + 3604857256930695427073651918091429;
            q = ((q * x) >> 96) - 14423608567350463180887372962807573;
            q = ((q * x) >> 96) + 26449188498355588339934803723976023;

            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial won't have zeros in the domain as all its roots are complex.
                // No scaling is necessary because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r should be in the range (0.09, 0.25) * 2**96.

            // We now need to multiply r by:
            // * the scale factor s = ~6.031367120.
            // * the 2**k factor from the range reduction.
            // * the 1e18 / 2**96 factor for base conversion.
            // We do this all at once, with an intermediate result in 2**213
            // basis, so the final right shift is always by a positive amount.
            r = int256((uint256(r) * 3822833074963236453042738258902158003155416615667) >> uint256(195 - k));
        }
    }

    function lnWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            require(x > 0, "UNDEFINED");

            // We want to convert x from 10**18 fixed point to 2**96 fixed point.
            // We do this by multiplying by 2**96 / 10**18. But since
            // ln(x * C) = ln(x) + ln(C), we can simply do nothing here
            // and add ln(2**96 / 10**18) at the end.

            // Reduce range of x to (1, 2) * 2**96
            // ln(2^k * x) = k * ln(2) + ln(x)
            int256 k = int256(log2(uint256(x))) - 96;
            x <<= uint256(159 - k);
            x = int256(uint256(x) >> 159);

            // Evaluate using a (8, 8)-term rational approximation.
            // p is made monic, we will multiply by a scale factor later.
            int256 p = x + 3273285459638523848632254066296;
            p = ((p * x) >> 96) + 24828157081833163892658089445524;
            p = ((p * x) >> 96) + 43456485725739037958740375743393;
            p = ((p * x) >> 96) - 11111509109440967052023855526967;
            p = ((p * x) >> 96) - 45023709667254063763336534515857;
            p = ((p * x) >> 96) - 14706773417378608786704636184526;
            p = p * x - (795164235651350426258249787498 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            // q is monic by convention.
            int256 q = x + 5573035233440673466300451813936;
            q = ((q * x) >> 96) + 71694874799317883764090561454958;
            q = ((q * x) >> 96) + 283447036172924575727196451306956;
            q = ((q * x) >> 96) + 401686690394027663651624208769553;
            q = ((q * x) >> 96) + 204048457590392012362485061816622;
            q = ((q * x) >> 96) + 31853899698501571402653359427138;
            q = ((q * x) >> 96) + 909429971244387300277376558375;
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial is known not to have zeros in the domain.
                // No scaling required because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r is in the range (0, 0.125) * 2**96

            // Finalization, we need to:
            // * multiply by the scale factor s = 5.549…
            // * add ln(2**96 / 10**18)
            // * add k * ln(2)
            // * multiply by 10**18 / 2**96 = 5**18 >> 78

            // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
            r *= 1677202110996718588342820967067443963516166;
            // add ln(2) * k * 5e18 * 2**192
            r += 16597577552685614221487285958193947469193820559219878177908093499208371 * k;
            // add ln(2**96 / 10**18) * 5e18 * 2**192
            r += 600920179829731861736702779321621459595472258049074101567377883020018308;
            // base conversion: mul 2**18 / 2**192
            r >>= 174;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    LOW LEVEL FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the denominator and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), denominator), 1))
        }
    }

    function rpow(
        uint256 x,
        uint256 n,
        uint256 scalar
    ) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    // 0 ** 0 = 1
                    z := scalar
                }
                default {
                    // 0 ** n = 0
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    // If n is even, store scalar in z for now.
                    z := scalar
                }
                default {
                    // If n is odd, store x in z for now.
                    z := x
                }

                // Shifting right by 1 is like dividing by 2.
                let half := shr(1, scalar)

                for {
                    // Shift n right by 1 before looping to halve it.
                    n := shr(1, n)
                } n {
                    // Shift n right by 1 each iteration to halve it.
                    n := shr(1, n)
                } {
                    // Revert immediately if x ** 2 would overflow.
                    // Equivalent to iszero(eq(div(xx, x), x)) here.
                    if shr(128, x) {
                        revert(0, 0)
                    }

                    // Store x squared.
                    let xx := mul(x, x)

                    // Round to the nearest number.
                    let xxRound := add(xx, half)

                    // Revert if xx + half overflowed.
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }

                    // Set x to scaled xxRound.
                    x := div(xxRound, scalar)

                    // If n is even:
                    if mod(n, 2) {
                        // Compute z * x.
                        let zx := mul(z, x)

                        // If z * x overflowed:
                        if iszero(eq(div(zx, x), z)) {
                            // Revert if x is non-zero.
                            if iszero(iszero(x)) {
                                revert(0, 0)
                            }
                        }

                        // Round to the nearest number.
                        let zxRound := add(zx, half)

                        // Revert if zx + half overflowed.
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }

                        // Return properly scaled zxRound.
                        z := div(zxRound, scalar)
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GENERAL NUMBER UTILITIES
    //////////////////////////////////////////////////////////////*/

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            let y := x // We start y at x, which will help us make our initial estimate.

            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // We check y >= 2^(k + 8) but shift right by k bits
            // each branch to ensure that if x >= 256, then y >= 256.
            if iszero(lt(y, 0x10000000000000000000000000000000000)) {
                y := shr(128, y)
                z := shl(64, z)
            }
            if iszero(lt(y, 0x1000000000000000000)) {
                y := shr(64, y)
                z := shl(32, z)
            }
            if iszero(lt(y, 0x10000000000)) {
                y := shr(32, y)
                z := shl(16, z)
            }
            if iszero(lt(y, 0x1000000)) {
                y := shr(16, y)
                z := shl(8, z)
            }

            // Goal was to get z*z*y within a small factor of x. More iterations could
            // get y in a tighter range. Currently, we will have y in [256, 256*2^16).
            // We ensured y >= 256 so that the relative difference between y and y+1 is small.
            // That's not possible if x < 256 but we can just verify those cases exhaustively.

            // Now, z*z*y <= x < z*z*(y+1), and y <= 2^(16+8), and either y >= 256, or x < 256.
            // Correctness can be checked exhaustively for x < 256, so we assume y >= 256.
            // Then z*sqrt(y) is within sqrt(257)/sqrt(256) of sqrt(x), or about 20bps.

            // For s in the range [1/256, 256], the estimate f(s) = (181/1024) * (s+1) is in the range
            // (1/2.84 * sqrt(s), 2.84 * sqrt(s)), with largest error when s = 1 and when s = 256 or 1/256.

            // Since y is in [256, 256*2^16), let a = y/65536, so that a is in [1/256, 256). Then we can estimate
            // sqrt(y) using sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2^18.

            // There is no overflow risk here since y < 2^136 after the first branch above.
            z := shr(18, mul(z, add(y, 65536))) // A mul() is saved from starting z at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If x+1 is a perfect square, the Babylonian method cycles between
            // floor(sqrt(x)) and ceil(sqrt(x)). This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            // Since the ceil is rare, we save gas on the assignment and repeat division in the rare case.
            // If you don't care whether the floor or ceil square root is returned, you can remove this statement.
            z := sub(z, lt(div(x, z), z))
        }
    }

    function log2(uint256 x) internal pure returns (uint256 r) {
        require(x > 0, "UNDEFINED");

        assembly {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            r := or(r, shl(2, lt(0xf, shr(r, x))))
            r := or(r, shl(1, lt(0x3, shr(r, x))))
            r := or(r, lt(0x1, shr(r, x)))
        }
    }

    function unsafeMod(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // z will equal 0 if y is 0, unlike in Solidity where it will revert.
            z := mod(x, y)
        }
    }

    function unsafeDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // z will equal 0 if y is 0, unlike in Solidity where it will revert.
            z := div(x, y)
        }
    }

    /// @dev Will return 0 instead of reverting if y is zero.
    function unsafeDivUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // Add 1 to x * y if x % y > 0.
            z := add(gt(mod(x, y), 0), div(x, y))
        }
    }
}

// contracts/libraries/FullMath.sol

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

// contracts/interfaces/IPositionManagerV3.sol

interface IPositionManagerV3 {
    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @param tokenId The ID of the token that represents the position
    /// @return nonce The nonce for permits
    /// @return operator The address that is approved for spending
    /// @return token0 The address of the token0 for a specific pool
    /// @return token1 The address of the token1 for a specific pool
    /// @return fee The fee associated with the pool
    /// @return tickLower The lower end of the tick range for the position
    /// @return tickUpper The higher end of the tick range for the position
    /// @return liquidity The liquidity of the position
    /// @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
    /// @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
    /// @return tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation
    /// @return tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation
    function positions(uint256 tokenId)
    external
    view
    returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external payable returns (uint256 amount0, uint256 amount1);

    /// @dev Transfers position.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transferFrom(address from, address to, uint256 positionId) external;
}

// contracts/interfaces/IToken.sol

/// @dev Generic token interface for IERC20 and IERC721 tokens.
interface IToken_0 {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @dev Gets the total amount of tokens stored by the contract.
    /// @return Amount of tokens.
    function totalSupply() external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets remaining number of tokens that the `spender` can transfer on behalf of `owner`.
    /// @param owner Token owner.
    /// @param spender Account address that is able to transfer tokens on behalf of the owner.
    /// @return Token amount allowed to be transferred.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// contracts/interfaces/IUniswapV3.sol

interface IUniswapV3 {
    /// @notice Creates a new pool if it does not exist, then initializes if not initialized
    /// @dev This method can be bundled with others via IMulticall for the first action (e.g. mint) performed against a pool
    /// @param token0 The contract address of token0 of the pool
    /// @param token1 The contract address of token1 of the pool
    /// @param fee The fee amount of the v3 pool for the specified token pair
    /// @param sqrtPriceX96 The initial square root price of the pool as a Q64.96 value
    /// @return pool Returns the pool address based on the pair of tokens and fee, will return the newly created pool address if necessary
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external payable returns (address pool);

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

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params) external payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// tick The current tick of the pool, i.e. according to the last tick transition that was run.
    /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96) if the price is on a tick
    /// boundary.
    /// observationIndex The index of the last oracle observation that was written,
    /// observationCardinality The current maximum number of observations stored in the pool,
    /// observationCardinalityNext The next maximum number of observations, to be updated when the observation.
    /// feeProtocol The protocol fee for both tokens of the pool.
    /// Encoded as two 4 bit values, where the protocol fee of token1 is shifted 4 bits and the protocol fee of token0
    /// is the lower 4 bits. Used as the denominator of a fraction of the swap fee, e.g. 4 means 1/4th of the swap fee.
    /// unlocked Whether the pool is currently locked to reentrancy
    function slot0() external view
        returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality,
            uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);

    /// @notice Returns the cumulative tick and liquidity as of each timestamp `secondsAgo` from the current block timestamp
    /// @dev To get a time weighted average tick or liquidity-in-range, you must call this with two values, one representing
    /// the beginning of the period and another for the end of the period. E.g., to get the last hour time-weighted average tick,
    /// you must call it with secondsAgos = [3600, 0].
    /// @dev The time weighted average tick represents the geometric time weighted average price of the pool, in
    /// log base sqrt(1.0001) of token1 / token0. The TickMath library can be used to go from a tick value to a ratio.
    /// @param secondsAgos From how long ago each cumulative tick and liquidity value should be returned
    /// @return tickCumulatives Cumulative tick values as of each `secondsAgos` from the current block timestamp
    /// @return secondsPerLiquidityCumulativeX128s Cumulative seconds per liquidity-in-range value as of each `secondsAgos` from the current block
    /// timestamp
    function observe(uint32[] calldata secondsAgos)
        external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice Returns data about a specific observation index
    /// @param index The element of the observations array to fetch
    /// @dev You most likely want to use #observe() instead of this method to get an observation as of some amount of time
    /// ago, rather than at a specific index in the array.
    /// @return blockTimestamp The timestamp of the observation,
    /// @return tickCumulative the tick multiplied by seconds elapsed for the life of the pool as of the observation timestamp,
    /// @return secondsPerLiquidityCumulativeX128 the seconds per in range liquidity for the life of the pool as of the observation timestamp,
    /// @return initialized whether the observation has been initialized and the values are safe to use
    function observations(uint256 index) external view returns (uint32 blockTimestamp, int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128, bool initialized);

    /// @notice Increase the maximum number of price and liquidity observations that this pool will store
    /// @dev This method is no-op if the pool already has an observationCardinalityNext greater than or equal to
    /// the input observationCardinalityNext.
    /// @param observationCardinalityNext The desired minimum number of observations for the pool to store
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;

    function factory() external view returns (address);
}

// contracts/utils/SafeTransferLib.sol

/// @dev Failure of a token transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TokenTransferFailed(address token, address from, address to, uint256 value);

/// @dev The implementation is fully copied from the audited MIT-licensed solmate code repository:
///      https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
///      The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
///      related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
///      Also, the final `require` statement is modified with this contract own `revert` statement.
library SafeTransferLib {
    /// @dev Safe token transferFrom implementation.
    /// @param token Token address.
    /// @param from Address to transfer tokens from.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(4, from) // Append the "from" argument.
            mstore(36, to) // Append the "to" argument.
            mstore(68, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 100 because that's the total length of our calldata (4 + 32 * 3)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 100, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TokenTransferFailed(token, from, to, amount);
        }
    }

    /// @dev Safe token transfer implementation.
    /// @notice The implementation is fully copied from the audited MIT-licensed solmate code repository:
    ///         https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
    ///         The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
    ///         related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
    ///         Also, the final `require` statement is modified with this contract own `revert` statement.
    /// @param token Token address.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransfer(address token, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(4, to) // Append the "to" argument.
            mstore(36, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 68 because that's the total length of our calldata (4 + 32 * 2)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 68, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TokenTransferFailed(token, address(this), to, amount);
        }
    }
}

// contracts/libraries/TickMath.sol

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

// contracts/libraries/LiquidityAmounts.sol

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

// contracts/pol/LiquidityManagerCore.sol

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Expected token address is not found in provided tokens.
/// @param provided Provided token addresses.
/// @param expected Expected token address.
error WrongTokenAddress(address[] provided, address expected);

/// @dev Out of tick range bounds.
/// @param low Low tick provided.
/// @param center Center tick provided.
/// @param high High tick provided.
error RangeBounds(int24 low, int24 center, int24 high);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

interface INeighborhoodScanner {
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
    ) external pure returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired);
}

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event MaxSlippageUpdated(uint256 maxSlippage);
    event ConvertedToV3(
        address indexed pool,
        uint256 indexed positionId,
        address[] tokens,
        uint256[] amounts,
        uint256 liquidiy,
        bool scan
    );
    event RangesChanged(
        address indexed pool,
        uint256 indexed positionId,
        address[] tokens,
        uint256[] amounts,
        uint256 liquidiy,
        bool scan
    );
    event UtilityAmountsManaged(
        address indexed olas, address indexed token, uint256 olasAmount, uint256 tokenAmount, bool olasBurnOrTransfer
    );
    event PositionMinted(uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy);
    event LiquidityDecreased(uint256 indexed positionId, uint256[] amounts, uint256 liquidity);
    event PositionLiquidityDecreased(
        address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy
    );
    event LiquidityIncreased(uint256 indexed positionId, uint256[] amounts, uint256 liquidity);
    event PositionLiquidityIncreased(
        address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy
    );
    event FeesCollected(address indexed sender, uint256 indexed positionId, uint256[] amounts);
    event PositionFeesCollected(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts);
    event TicksSet(address[] tokens, int24 feeTierOrTickSpacing, int24[] initTicks, int24[] optimizedTicks, bool scan);
    event PositionTransferred(uint256 indexed positionId, address indexed to);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount);

    // LiquidityManager version number
    string public constant VERSION = "0.1.0";
    // LiquidityManager proxy address slot
    // keccak256("PROXY_LIQUIDITY_MANAGER") = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
    bytes32 public constant PROXY_LIQUIDITY_MANAGER =
        0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd;
    // Max allowed price deviation for TWAP pool values (10%) in 1e18 format
    uint256 public constant MAX_ALLOWED_DEVIATION = 1e17;
    // Seconds ago to look back for TWAP pool values
    uint32 public constant SECONDS_AGO = 1800;
    // // Max bps value
    uint16 public constant MAX_BPS = 10_000;

    // OLAS token address
    address public immutable olas;
    // Treasury address (timelock or governing bridge mediator)
    address public immutable treasury;
    // V3 position manager address
    address public immutable positionManagerV3;
    // V3 factory
    address public immutable factoryV3;
    // Neighborhood ticks scanner
    address public immutable neighborhoodScanner;
    // Observations cardinality
    uint16 public immutable observationCardinality;

    // Owner address
    address public owner;

    // Max slippage for pool operations (in BPS, bound by 10_000)
    uint16 public maxSlippage;

    // Reentrancy lock
    uint8 internal _locked;

    // V3 position Ids
    mapping(address => uint256) public mapPoolAddressPositionIds;

    /// @dev LiquidityManagerCore constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality
    ) {
        // Check for zero addresses
        if (
            _olas == address(0) || _treasury == address(0) || _positionManagerV3 == address(0)
                || _neighborhoodScanner == address(0)
        ) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_observationCardinality == 0) {
            revert ZeroValue();
        }

        olas = _olas;
        treasury = _treasury;
        positionManagerV3 = _positionManagerV3;
        neighborhoodScanner = _neighborhoodScanner;
        observationCardinality = _observationCardinality;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    /// @dev Burns OLAS directly or transfers OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal virtual;

    /// @dev Checks provided tokens to match V2 pool ones and removes liquidity.
    /// @param tokens Tokens comprising V2 pool.
    /// @param v2Pool V2 pool hash or address.
    /// @return amounts Removed liquidity amounts.
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool)
        internal
        virtual
        returns (uint256[] memory amounts);

    /// @dev Gets tick spacing according to fee tier or tick spacing directly.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return tickSpacing Tick spacing.
    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing) internal view virtual returns (int24 tickSpacing);

    /// @dev Gets sqrt price and observation index values from slot 0.
    /// @notice This is a general usage function, it accounts for known UniswapV3-like versions of slot0() function.
    /// @param pool Pool address.
    /// @return sqrtPriceX96 Sqrt price.
    /// @return observationIndex Observation index.
    function _getPriceAndObservationIndexFromSlot0(address pool)
        internal
        view
        virtual
        returns (uint160 sqrtPriceX96, uint16 observationIndex)
    {
        // Get slot0 payload
        bytes memory payload = abi.encodeCall(IUniswapV3.slot0, ());
        // Low-level call of pool.slot0()
        (bool success, bytes memory returnData) = pool.staticcall(payload);

        // Check for success
        if (success) {
            // returnData comes with each variable in its own slot
            // Skip first 32 bytes of the returnData length prefix
            // mload(add(returnData, 32)) is the first return value
            // sqrtPriceX96 is in slot 1
            // observationIndex is in slot 3
            assembly {
                sqrtPriceX96 := mload(add(returnData, 32))
                observationIndex := mload(add(returnData, 96))
            }
        }
    }

    /// @dev Gets V3 pool based on token addresses and fee tier or tick spacing.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return v3Pool V3 pool address.
    function _getV3Pool(address[] memory tokens, int24 feeTierOrTickSpacing)
        internal
        view
        virtual
        returns (address v3Pool);

    /// @dev Mints V3 pool position.
    /// @param tokens Token addresses.
    /// @param amounts Desired amounts.
    /// @param amountsMin Minimum amounts.
    /// @param ticks Ticks array.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param centerSqrtPriceX96 Center sqrt price.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn);

    /// @dev Calculates ticks and mints position.
    /// @param tokens Token addresses.
    /// @param inputAmounts Input amounts corresponding to tokens.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _calculateTicksAndMintPosition(
        address[] memory tokens,
        uint256[] memory inputAmounts,
        int24 feeTierOrTickSpacing,
        uint160 sqrtP,
        int24[] memory tickShifts,
        bool scan
    ) internal returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn) {
        int24 centerTick = TickMath.getTickAtSqrtRatio(sqrtP);
        int24[] memory ticks = new int24[](2);
        ticks[0] = centerTick + tickShifts[0];
        ticks[1] = centerTick + tickShifts[1];

        if (ticks[0] >= centerTick || ticks[1] <= centerTick) {
            revert RangeBounds(ticks[0], centerTick, ticks[1]);
        }

        // Calculate and mint new position
        return _optimizeTicksAndMintPosition(tokens, inputAmounts, feeTierOrTickSpacing, sqrtP, ticks, scan);
    }

    /// @dev Collects fees from LP position.
    /// @notice Function does not revert if any of amounts are zero.
    /// @param positionId Position Id.
    /// @return amounts Amounts array.
    function _collectFees(uint256 positionId) internal returns (uint256[] memory amounts) {
        IUniswapV3.CollectParams memory params = IUniswapV3.CollectParams({
            tokenId: positionId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        amounts = new uint256[](2);
        // Get corresponding token fees
        (amounts[0], amounts[1]) = IUniswapV3(positionManagerV3).collect(params);

        emit FeesCollected(msg.sender, positionId, amounts);
    }

    /// @dev Decreases liquidity for specified pool.
    /// @param pool Pool address.
    /// @param positionId Position Id.
    /// @param decreaseRate Rate of position decrease in BPS.
    /// @return liquidity Decreased liquidity amount.
    /// @return amountsOut Amounts from liquidity.
    function _decreaseLiquidity(address pool, uint256 positionId, uint16 decreaseRate)
        internal
        returns (uint128 liquidity, uint256[] memory amountsOut)
    {
        // Read position & liquidity
        int24[] memory ticks = new int24[](2);
        (,,,,, ticks[0], ticks[1], liquidity,,,,) = IPositionManagerV3(positionManagerV3).positions(positionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Calculate liquidity based on provided BPS, if any
        if (decreaseRate < MAX_BPS) {
            liquidity = (liquidity * decreaseRate) / MAX_BPS;
        }

        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get current pool sqrt price
        (uint160 sqrtPriceX96,) = _getPriceAndObservationIndexFromSlot0(pool);
        // Check for zero value
        if (sqrtPriceX96 == 0) {
            revert ZeroValue();
        }

        // Get sqrt prices for ticks
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);

        // Get amounts based on liquidity
        uint256[] memory amountsMin = new uint256[](2);
        (amountsMin[0], amountsMin[1]) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);

        // Get minimum amounts according to slippage
        amountsMin[0] = amountsMin[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        amountsMin[1] = amountsMin[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Assemble decrease liquidity params
        IPositionManagerV3.DecreaseLiquidityParams memory params = IPositionManagerV3.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liquidity,
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            deadline: block.timestamp
        });

        // Decrease liquidity
        amountsOut = new uint256[](2);
        (amountsOut[0], amountsOut[1]) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(params);

        emit LiquidityDecreased(positionId, amountsOut, liquidity);
    }

    /// @dev Increases liquidity for specified pool.
    /// @param pool Pool address.
    /// @param positionId Position Id.
    /// @param inputAmounts Input amounts.
    /// @return liquidity Decreased liquidity amount.
    /// @return amountsIn Amounts in liquidity.
    function _increaseLiquidity(address pool, uint256 positionId, uint256[] memory inputAmounts)
        internal
        returns (uint128 liquidity, uint256[] memory amountsIn)
    {
        // Get current pool sqrt price
        (uint160 sqrtPriceX96,) = _getPriceAndObservationIndexFromSlot0(pool);
        // Check for zero value
        if (sqrtPriceX96 == 0) {
            revert ZeroValue();
        }

        // Read position & liquidity
        int24[] memory ticks = new int24[](2);
        (,,,,, ticks[0], ticks[1],,,,,) = IPositionManagerV3(positionManagerV3).positions(positionId);

        // Get sqrt prices for ticks
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);
        // Compute liquidity based on amounts and sqrt prices
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtAB[0], sqrtAB[1], inputAmounts[0], inputAmounts[1]
        );

        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get amounts for liquidity
        (inputAmounts[0], inputAmounts[1]) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);
        uint256[] memory aMin = new uint256[](2);
        aMin[0] = inputAmounts[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        aMin[1] = inputAmounts[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Assemble increase liquidity params
        IPositionManagerV3.IncreaseLiquidityParams memory params = IPositionManagerV3.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: inputAmounts[0],
            amount1Desired: inputAmounts[1],
            amount0Min: aMin[0],
            amount1Min: aMin[1],
            deadline: block.timestamp
        });

        // Increase liquidity
        amountsIn = new uint256[](2);
        (liquidity, amountsIn[0], amountsIn[1]) = IPositionManagerV3(positionManagerV3).increaseLiquidity(params);

        emit LiquidityIncreased(positionId, amountsIn, liquidity);
    }

    /// @dev Manages utility token amounts.
    /// @notice Non-OLAS token is always transferred to treasury, OLAS is either burnt or transferred as well.
    /// @param tokens Token addresses.
    /// @param utilizationRate Token utilization rate, in BPS.
    /// @param olasBurnOrTransfer True if OLAS is burnt, false if transferred to treasury.
    function _manageUtilityAmounts(address[] memory tokens, uint16 utilizationRate, bool olasBurnOrTransfer)
        internal
        returns (uint256[] memory updatedBalances)
    {
        updatedBalances = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        // Get token balances
        amounts[0] = IToken_0(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken_0(tokens[1]).balanceOf(address(this));

        // Adjust amounts according to utilizationRate
        if (utilizationRate < MAX_BPS) {
            updatedBalances[0] = amounts[0];
            updatedBalances[1] = amounts[1];

            amounts[0] = (amounts[0] * utilizationRate) / MAX_BPS;
            amounts[1] = (amounts[1] * utilizationRate) / MAX_BPS;

            // Update leftover balances
            updatedBalances[0] -= amounts[0];
            updatedBalances[1] -= amounts[1];
        }

        // Get token balances
        uint256 olasAmount;
        uint256 tokenAmount;
        address secondToken;

        // Check for OLAS token and swap values, if needed
        if (tokens[0] == olas) {
            secondToken = tokens[1];
            olasAmount = amounts[0];
            tokenAmount = amounts[1];
        } else {
            secondToken = tokens[0];
            olasAmount = amounts[1];
            tokenAmount = amounts[0];
        }

        // Manage OLAS token
        if (olasAmount > 0) {
            if (olasBurnOrTransfer) {
                // Directly burn or transfer OLAS to Burner contract
                _burn(olasAmount);
            } else {
                // Transfer OLAS to Treasury contract
                IToken_0(olas).transfer(treasury, olasAmount);
            }
        }

        // Transfer another token to Treasury
        if (tokenAmount > 0) {
            SafeTransferLib.safeTransfer(secondToken, treasury, tokenAmount);
        }

        emit UtilityAmountsManaged(olas, secondToken, olasAmount, tokenAmount, olasBurnOrTransfer);
    }

    /// @dev Optimizes given ticks at least to tick spacing (or liquidity based), and mints position.
    /// @param tokens Token addresses.
    /// @param inputAmounts Input amounts corresponding to tokens.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param initTicks Initial ticks array.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _optimizeTicksAndMintPosition(
        address[] memory tokens,
        uint256[] memory inputAmounts,
        int24 feeTierOrTickSpacing,
        uint160 sqrtP,
        int24[] memory initTicks,
        bool scan
    ) internal returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn) {
        // Get tick spacing
        int24 tickSpacing = _feeAmountTickSpacing(feeTierOrTickSpacing);
        // Check for zero value
        if (tickSpacing == 0) {
            revert ZeroValue();
        }

        int24[] memory optimizedTicks;
        // Build percent band around TWAP center
        (optimizedTicks, liquidity, amountsIn) = INeighborhoodScanner(neighborhoodScanner)
            .optimizeLiquidityAmounts(sqrtP, initTicks, tickSpacing, inputAmounts, scan);

        // Check for zero values
        if (liquidity == 0 || amountsIn[0] == 0 || amountsIn[1] == 0) {
            revert ZeroValue();
        }

        // Get min amounts
        uint256[] memory aMin = new uint256[](2);
        aMin[0] = amountsIn[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        aMin[1] = amountsIn[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Mint V3 position
        (positionId, liquidity, amountsIn) =
            _mintV3(tokens, amountsIn, aMin, optimizedTicks, feeTierOrTickSpacing, sqrtP);

        emit TicksSet(tokens, feeTierOrTickSpacing, initTicks, optimizedTicks, scan);
        emit PositionMinted(positionId, tokens, amountsIn, liquidity);
    }

    /// @dev Initialization function.
    /// @param _maxSlippage Max slippage for operations.
    function initialize(uint16 _maxSlippage) external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        // Check for zero value
        if (_maxSlippage == 0) {
            revert ZeroValue();
        }
        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        maxSlippage = _maxSlippage;

        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes liquidity manager implementation contract address.
    /// @notice Make sure the implementation contract has a function to change the implementation.
    /// @param implementation LiquidityManager implementation contract address.
    function changeImplementation(address implementation) external {
        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (implementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the implementation address under the designated storage slot
        assembly {
            sstore(PROXY_LIQUIDITY_MANAGER, implementation)
        }
        emit ImplementationUpdated(implementation);
    }

    /// @dev Changes max slippage value.
    /// @param newMaxSlippage New max slippage value.
    function changeMaxSlippage(uint16 newMaxSlippage) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (newMaxSlippage == 0) {
            revert ZeroValue();
        }

        maxSlippage = newMaxSlippage;
        emit MaxSlippageUpdated(newMaxSlippage);
    }

    /// @dev Converts token amounts to V3 liquidity: from balances, or from V2 liquidity, or both.
    /// @param tokens Token addresses.
    /// @param v2Pool V2 pool hash / address.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param olasBurnRate OLAS burn rate in BPS: burns specified amount of OLAS from initial token amounts,
    ///        transfers same rate of another token to treasury address.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function convertToV3(
        address[] memory tokens,
        bytes32 v2Pool,
        int24 feeTierOrTickSpacing,
        int24[] memory tickShifts,
        uint16 olasBurnRate,
        bool scan
    ) external returns (uint256 positionId, uint256 liquidity, uint256[] memory amounts) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for OLAS in pair
        if (tokens[0] != olas && tokens[1] != olas) {
            revert WrongTokenAddress(tokens, olas);
        }

        // Check conversion rate overflow
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        if (v2Pool != 0) {
            // Remove liquidity from V2 pool
            _checkTokensAndRemoveLiquidityV2(tokens, v2Pool);
        }

        // Get token amounts
        amounts = new uint256[](2);
        amounts[0] = IToken_0(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken_0(tokens[1]).balanceOf(address(this));

        // Check for zero values
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Get V3 pool
        address v3Pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (v3Pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on OLAS burn rate
        if (olasBurnRate > 0) {
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Check current pool prices
        uint160 sqrtP = checkPoolAndGetCenterPrice(v3Pool);

        // Approve tokens for position manager
        IToken_0(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken_0(tokens[1]).approve(positionManagerV3, amounts[1]);

        // Get position Id
        positionId = mapPoolAddressPositionIds[v3Pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            (positionId, liquidity, amounts) =
                _calculateTicksAndMintPosition(tokens, amounts, feeTierOrTickSpacing, sqrtP, tickShifts, scan);

            // Record position Id associated with pool
            mapPoolAddressPositionIds[v3Pool] = positionId;

            // Increase observation cardinality
            IUniswapV3(v3Pool).increaseObservationCardinalityNext(observationCardinality);
        } else {
            // Increase liquidity with actual ticks, since position already exists
            (liquidity, amounts) = _increaseLiquidity(v3Pool, positionId, amounts);
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit ConvertedToV3(v3Pool, positionId, tokens, amounts, liquidity, scan);

        _locked = 1;
    }

    /// @dev Changes ranges of position in a specified pool.
    /// @notice Any collected fees from liquidating initial position are supplied for one with repositioned ranges.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function changeRanges(address[] memory tokens, int24 feeTierOrTickSpacing, int24[] memory tickShifts, bool scan)
        external
        returns (uint256 positionId, uint128 liquidity, uint256[] memory amounts)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        uint256 currentPositionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (currentPositionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        uint160 centerSqrtPriceX96 = checkPoolAndGetCenterPrice(pool);

        // Decrease liquidity
        _decreaseLiquidity(pool, currentPositionId, MAX_BPS);

        // Collect fees and tokens removed from liquidity
        amounts = _collectFees(currentPositionId);

        // Check that we have liquidity for both tokens
        if (amounts[0] > 0 && amounts[1] > 0) {
            // Approve tokens for position manager
            IToken_0(tokens[0]).approve(positionManagerV3, amounts[0]);
            IToken_0(tokens[1]).approve(positionManagerV3, amounts[1]);

            // Calculate params and mint new position
            (positionId, liquidity, amounts) = _calculateTicksAndMintPosition(
                tokens, amounts, feeTierOrTickSpacing, centerSqrtPriceX96, tickShifts, scan
            );

            // Record position Id
            mapPoolAddressPositionIds[pool] = positionId;
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit RangesChanged(pool, positionId, tokens, amounts, liquidity, scan);

        _locked = 1;
    }

    /// @dev Collects fees from LP position, burns OLAS tokens and transfers another token to treasury.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return amounts Amounts array.
    function collectFees(address[] memory tokens, int24 feeTierOrTickSpacing)
        external
        returns (uint256[] memory amounts)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        uint256 positionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        checkPoolAndGetCenterPrice(pool);

        // Collect fees
        amounts = _collectFees(positionId);

        // Check for zero values
        if (amounts[0] == 0 && amounts[1] == 0) {
            revert ZeroValue();
        }

        // Manage collected fees: burn OLAS, transfer another token
        _manageUtilityAmounts(tokens, MAX_BPS, true);

        emit PositionFeesCollected(pool, positionId, tokens, amounts);

        _locked = 1;
    }

    /// @dev Decreases liquidity for specified pool.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param decreaseRate Rate of position decrease in BPS.
    /// @param olasBurnRate OLAS burn rate in BPS, relative to specified decreaseRate: burns OLAS from decreased
    ///        token amounts and collected fees, transfers same rate of another token to treasury address.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Decreased liquidity amount.
    /// @return amounts Amounts from liquidity.
    function decreaseLiquidity(
        address[] memory tokens,
        int24 feeTierOrTickSpacing,
        uint16 decreaseRate,
        uint16 olasBurnRate
    ) external returns (uint256 positionId, uint128 liquidity, uint256[] memory amounts) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check decrease and olas burn rates
        if (decreaseRate == 0) {
            revert ZeroValue();
        }
        if (decreaseRate > MAX_BPS) {
            revert Overflow(decreaseRate, MAX_BPS);
        }
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        positionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        checkPoolAndGetCenterPrice(pool);

        // Decrease liquidity
        (liquidity,) = _decreaseLiquidity(pool, positionId, decreaseRate);

        // Collect fees and tokens removed from liquidity
        amounts = _collectFees(positionId);

        // Burn OLAS and transfer another token to treasury
        if (olasBurnRate > 0) {
            _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Manage collected amounts - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit PositionLiquidityDecreased(pool, positionId, tokens, amounts, liquidity);

        _locked = 1;
    }

    /// @dev Increases liquidity for specified pool.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param olasBurnRate OLAS burn rate in BPS: burns specified amount of OLAS from initial token amounts,
    ///        transfers same rate of another token to treasury address.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function increaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 olasBurnRate)
        external
        returns (uint256 positionId, uint256 liquidity, uint256[] memory amounts)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check conversion rate overflow
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        // Get token amounts
        amounts = new uint256[](2);
        amounts[0] = IToken_0(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken_0(tokens[1]).balanceOf(address(this));

        // Check for zero values
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on OLAS burn rate
        if (olasBurnRate > 0) {
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Get positionId
        positionId = mapPoolAddressPositionIds[pool];

        // Check for zero position
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        checkPoolAndGetCenterPrice(pool);

        // Approve tokens for position manager
        IToken_0(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken_0(tokens[1]).approve(positionManagerV3, amounts[1]);

        // Increase liquidity
        (liquidity, amounts) = _increaseLiquidity(pool, positionId, amounts);

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit PositionLiquidityIncreased(pool, positionId, tokens, amounts, liquidity);

        _locked = 1;
    }

    /// @dev Transfers position Id to a specified address.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transferPositionId(address[] memory tokens, int24 feeTierOrTickSpacing, address to)
        external
        returns (uint256 positionId)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        positionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Transfer position Id
        IPositionManagerV3(positionManagerV3).transferFrom(address(this), to, positionId);

        mapPoolAddressPositionIds[pool] = 0;

        emit PositionTransferred(positionId, to);

        _locked = 1;
    }

    /// @dev Transfers token to a specified address.
    /// @param token Token address.
    /// @param to Account address to transfer to.
    /// @param amount Token amount.
    function transferToken(address token, address to, uint256 amount) external {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get token balance
        uint256 balance = IToken_0(token).balanceOf(address(this));
        if (amount > balance) {
            revert Overflow(amount, balance);
        }

        // Transfer token
        SafeTransferLib.safeTransfer(token, to, amount);

        emit TokenTransferred(token, to, amount);

        _locked = 1;
    }

    /// @dev Gets TWAP price via built-in Uniswap V3 oracle.
    /// @param pool Pool address.
    /// @return price Calculated price.
    /// @return centerSqrtPriceX96 Calculated center SQRT price.
    function getTwapFromOracle(address pool) public view returns (uint256 price, uint160 centerSqrtPriceX96) {
        // Query the pool for the current and historical tick
        uint32[] memory secondsAgo = new uint32[](2);
        // Start of the period
        secondsAgo[0] = SECONDS_AGO;

        // Fetch the tick cumulative values from the pool: either from observations, or from slot0
        (int56[] memory tickCumulatives,) = IUniswapV3(pool).observe(secondsAgo);

        // Calculate the average tick over the time period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 centerTick = int24(tickCumulativeDelta / int56(int32(SECONDS_AGO)));

        // Convert the average tick to sqrtPriceX96
        centerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(centerTick);

        // Calculate the price using the sqrtPriceX96
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        price = mulDiv(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));
    }

    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @param pool Pool address.
    /// @return centerSqrtPriceX96 Calculated center SQRT price.
    function checkPoolAndGetCenterPrice(address pool) public view returns (uint160 centerSqrtPriceX96) {
        uint16 observationIndex;
        // Get current pool sqrt price and observation index
        (centerSqrtPriceX96, observationIndex) = _getPriceAndObservationIndexFromSlot0(pool);
        // Check for zero value
        if (centerSqrtPriceX96 == 0) {
            revert ZeroValue();
        }

        // Get oldest observations timestamp
        (uint32 oldestTimestamp,,,) = IUniswapV3(pool).observations(observationIndex);

        // Check if the pool had enough activity during last SECONDS_AGO period
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return centerSqrtPriceX96;
        }

        uint256 twapPrice;
        bytes memory payload = abi.encodeCall(this.getTwapFromOracle, (pool));
        // Check TWAP or historical data
        (bool success, bytes memory returnData) = address(this).staticcall(payload);

        // If the call has failed - observe was not successful, meaning the pool has not have enough activity yet
        if (!success) {
            return centerSqrtPriceX96;
        }

        // Get returned values from oracle
        (twapPrice, centerSqrtPriceX96) = abi.decode(returnData, (uint256, uint160));

        // Get instant price
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        uint256 instantPrice = mulDiv(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));

        uint256 deviation;
        // Calculate price deviation
        if (twapPrice > 0) {
            deviation = (instantPrice > twapPrice)
                ? mulDiv((instantPrice - twapPrice), 1e18, twapPrice)
                : mulDiv((twapPrice - instantPrice), 1e18, twapPrice);
        }

        // Check price deviation
        if (deviation > MAX_ALLOWED_DEVIATION) {
            revert Overflow(deviation, MAX_ALLOWED_DEVIATION);
        }
    }
}

// contracts/pol/LiquidityManagerOptimism.sol

/// @dev Expected token addresses do not match provided ones.
/// @param provided Provided token addresses.
/// @param expected Expected token addresses.
error WrongTokenAddresses(address[] provided, address[] expected);

interface IBalancerV2 {
    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /**
     * @dev Called by users to exit a Pool, which transfers tokens from the Pool's balance to `recipient`. This will
     * trigger custom Pool behavior, which will typically ask for something in return from `sender` - often tokenized
     * Pool shares. The amount of tokens that can be withdrawn is limited by the Pool's `cash` balance (see
     * `getPoolTokenInfo`).
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `tokens` and `minAmountsOut` arrays must have the same length, and each entry in these indicates the minimum
     * token amount to receive for each token contract. The amounts to send are decided by the Pool and not the Vault:
     * it just enforces these minimums.
     *
     * If exiting a Pool that holds WETH, it is possible to receive ETH directly: the Vault will do the unwrapping. To
     * enable this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead
     * of the WETH address. Note that it is not possible to combine ETH and WETH in the same exit.
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If receiving ETH however, the array must
     * be sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the
     * final `assets` array might not be sorted. Pools with no registered tokens cannot be exited.
     *
     * If `toInternalBalance` is true, the tokens will be deposited to `recipient`'s Internal Balance. Otherwise,
     * an ERC20 transfer will be performed. Note that ETH cannot be deposited to Internal Balance: attempting to
     * do so will trigger a revert.
     *
     * `minAmountsOut` is the minimum amount of tokens the user expects to get out of the Pool, for each token in the
     * `tokens` array. This array must match the Pool's registered tokens.
     *
     * This causes the Vault to call the `IBasePool.onExitPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares to return). This can be encoded in the `userData` argument, which is ignored by the Vault and
     * passed directly to the Pool's contract.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request)
        external;

    /**
     * @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when *any* of
     * the tokens' `balances` changed.
     *
     * The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
     * Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
     *
     * If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
     * order as passed to `registerTokens`.
     *
     * Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
     * the amounts used by joins, exits and swaps. For a detailed breakdown of token balances, use `getPoolTokenInfo`
     * instead.
     */
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    /**
     * @dev Returns a Pool's contract address and specialization setting.
     */
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);
}

interface ICLFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

interface IOracle {
    /// @dev Gets the current TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256);
}

interface IToken_1 {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Gets the total supply.
    /// @return Total token supply.
    function totalSupply() external view returns (uint256);
}

interface ISlipstreamV3 {
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title Liquidity Manager Optimism - Smart contract for OLAS core Liquidity Manager functionality on Optimism stack chains
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerOptimism is LiquidityManagerCore {
    // Balancer vault address
    address public immutable balancerVault;
    // V2 pool related oracle address
    address public immutable oracleV2;
    // Bridge to Burner address
    address public immutable bridge2Burner;

    /// @dev LiquidityManagerOptimism constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _balancerVault Balancer vault address.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        address _oracleV2,
        address _balancerVault,
        address _bridge2Burner
    ) LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality) {
        // Check for zero address
        if (_oracleV2 == address(0) || _balancerVault == address(0) || _bridge2Burner == address(0)) {
            revert ZeroAddress();
        }

        oracleV2 = _oracleV2;
        balancerVault = _balancerVault;
        bridge2Burner = _bridge2Burner;
    }

    /// @dev Transfer OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal override {
        IToken_1(olas).transfer(bridge2Burner, amount);
    }

    /// @inheritdoc LiquidityManagerCore
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool)
        internal
        virtual
        override
        returns (uint256[] memory amounts)
    {
        // Get pool address
        (address poolToken,) = IBalancerV2(balancerVault).getPool(v2Pool);
        // Get this contract liquidity
        uint256 liquidity = IToken_1(poolToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        address[] memory tokensInPool = new address[](2);
        // Get V2 pool tokens and amounts
        (tokensInPool, amounts,) = IBalancerV2(balancerVault).getPoolTokens(v2Pool);

        // Check tokens
        if (tokensInPool[0] != tokens[0] || tokensInPool[1] != tokens[1]) {
            revert WrongTokenAddresses(tokens, tokensInPool);
        }

        // Check for zero balances
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Compute TWAP-based manipulation-resistant minAmountsOut
        uint256[] memory minAmountsOut = new uint256[](2);
        {
            // Get BPT totalSupply
            uint256 totalSupply = IToken_1(poolToken).totalSupply();

            // k = balance0 * balance1 is manipulation-resistant (invariant for 50/50 weighted pool)
            uint256 k = amounts[0] * amounts[1];

            // TWAP is OLAS per secondToken in 1e18 format
            uint256 twap = IOracle(oracleV2).getTWAP();

            // Compute fair balances using constant product invariant and TWAP price
            // If tokens[0] is OLAS: fair_b0 = sqrt(k * twap / 1e18), fair_b1 = sqrt(k * 1e18 / twap)
            // If tokens[1] is OLAS: fair_b0 = sqrt(k * 1e18 / twap), fair_b1 = sqrt(k * twap / 1e18)
            uint256 fairBalance0;
            uint256 fairBalance1;
            if (tokens[0] == olas) {
                fairBalance0 = FixedPointMathLib.sqrt(k * twap / 1e18);
                fairBalance1 = FixedPointMathLib.sqrt(k * 1e18 / twap);
            } else {
                fairBalance0 = FixedPointMathLib.sqrt(k * 1e18 / twap);
                fairBalance1 = FixedPointMathLib.sqrt(k * twap / 1e18);
            }

            // Expected withdrawal amounts (proportional to fair balances)
            // minAmount = liquidity * fairBalance / totalSupply * (MAX_BPS - maxSlippage) / MAX_BPS
            minAmountsOut[0] = (liquidity * fairBalance0 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
            minAmountsOut[1] = (liquidity * fairBalance1 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
        }

        IBalancerV2.ExitPoolRequest memory request = IBalancerV2.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(IBalancerV2.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, liquidity),
            toInternalBalance: false
        });

        // Remove liquidity
        IBalancerV2(balancerVault).exitPool(v2Pool, address(this), payable(address(this)), request);
    }

    /// @inheritdoc LiquidityManagerCore
    /// @notice In Slipstream, if sqrtPriceX96 is not zero, it will try to create pool and fail, if pool already exists.
    ///         Thus, sqrtPriceX96 is set to zero by default.
    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 tickSpacing,
        uint160
    ) internal virtual override returns (uint256 positionId, uint128 liquidity, uint256[] memory) {
        // Params for minting
        ISlipstreamV3.MintParams memory params = ISlipstreamV3.MintParams({
            token0: tokens[0],
            token1: tokens[1],
            tickSpacing: tickSpacing,
            tickLower: ticks[0],
            tickUpper: ticks[1],
            amount0Desired: amounts[0],
            amount1Desired: amounts[1],
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            recipient: address(this),
            deadline: block.timestamp,
            sqrtPriceX96: 0
        });

        // Mint position
        (positionId, liquidity, amounts[0], amounts[1]) = ISlipstreamV3(positionManagerV3).mint(params);

        return (positionId, liquidity, amounts);
    }

    /// @dev Gets tick spacing according to fee tier or tick spacing directly.
    /// @param tickSpacing Tick spacing.
    function _feeAmountTickSpacing(int24 tickSpacing) internal view virtual override returns (int24) {
        return tickSpacing;
    }

    /// @dev Gets V3 pool based on token addresses and tick spacing.
    /// @param tokens Token addresses.
    /// @param tickSpacing Tick spacing.
    /// @return V3 pool address.
    function _getV3Pool(address[] memory tokens, int24 tickSpacing) internal view virtual override returns (address) {
        return ICLFactory(factoryV3).getPool(tokens[0], tokens[1], tickSpacing);
    }
}

