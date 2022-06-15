#!/bin/bash
FILE="./node_modules/@uniswap/lib/contracts/libraries/BitMath.sol"
case "$(uname -s)" in
   Darwin)
     sed -i.bu "s/uint128(-1)/type(uint128).max/g" $FILE
     sed -i.bu "s/uint64(-1)/type(uint64).max/g" $FILE
     sed -i.bu "s/uint32(-1)/type(uint32).max/g" $FILE
     sed -i.bu "s/uint16(-1)/type(uint16).max/g" $FILE
     sed -i.bu "s/uint8(-1)/type(uint8).max/g" $FILE 
     ;;

   Linux)
     sed -i "s/uint128(-1)/type(uint128).max/g" $FILE                                      
     sed -i "s/uint64(-1)/type(uint64).max/g" $FILE   
     sed -i "s/uint32(-1)/type(uint32).max/g" $FILE
     sed -i "s/uint16(-1)/type(uint16).max/g" $FILE
     sed -i "s/uint8(-1)/type(uint8).max/g" $FILE 
     ;;

   *)
     echo 'Other OS'
     ;;
esac

FILE="./node_modules/@uniswap/lib/contracts/libraries/FixedPoint.sol"
rm -rf $FILE
case "$(uname -s)" in
   Darwin)
cat << 'EOF' > ./node_modules/@uniswap/lib/contracts/libraries/FixedPoint.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.4.0;

import './FullMath.sol';
import './Babylonian.sol';
import './BitMath.sol';

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
library FixedPoint {
    // range: [0, 2**112 - 1]
    // resolution: 1 / 2**112
    struct uq112x112 {
        uint224 _x;
    }

    // range: [0, 2**144 - 1]
    // resolution: 1 / 2**112
    struct uq144x112 {
        uint256 _x;
    }

    uint8 public constant RESOLUTION = 112;
    uint256 public constant Q112 = 0x10000000000000000000000000000; // 2**112
    uint256 private constant Q224 = 0x100000000000000000000000000000000000000000000000000000000; // 2**224
    uint256 private constant LOWER_MASK = 0xffffffffffffffffffffffffffff; // decimal of UQ*x112 (lower 112 bits)

    // encode a uint112 as a UQ112x112
    function encode(uint112 x) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(x) << RESOLUTION);
    }

    // encodes a uint144 as a UQ144x112
    function encode144(uint144 x) internal pure returns (uq144x112 memory) {
        return uq144x112(uint256(x) << RESOLUTION);
    }

    // decode a UQ112x112 into a uint112 by truncating after the radix point
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    // decode a UQ144x112 into a uint144 by truncating after the radix point
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }

    // multiply a UQ112x112 by a uint, returning a UQ144x112
    // reverts on overflow
    function mul(uq112x112 memory self, uint256 y) internal pure returns (uq144x112 memory) {
        unchecked {
            uint256 z = 0;
            require(y == 0 || (z = self._x * y) / y == self._x, 'FixedPoint::mul: overflow');
            return uq144x112(z);
        }
    }

    // multiply a UQ112x112 by an int and decode, returning an int
    // reverts on overflow
    function muli(uq112x112 memory self, int256 y) internal pure returns (int256) {
        unchecked {
            uint256 z = FullMath.mulDiv(self._x, uint256(y < 0 ? -y : y), Q112); 
            require(z < 2**255, 'FixedPoint::muli: overflow');
            return y < 0 ? -int256(z) : int256(z);
        }
    }

    // multiply a UQ112x112 by a UQ112x112, returning a UQ112x112
    // lossy
    function muluq(uq112x112 memory self, uq112x112 memory other) internal pure returns (uq112x112 memory) {
        if (self._x == 0 || other._x == 0) {
            return uq112x112(0);
        }
        unchecked {
            uint112 upper_self = uint112(self._x >> RESOLUTION); // * 2^0
            uint112 lower_self = uint112(self._x & LOWER_MASK); // * 2^-112
            uint112 upper_other = uint112(other._x >> RESOLUTION); // * 2^0
            uint112 lower_other = uint112(other._x & LOWER_MASK); // * 2^-112

            // partial products
            uint224 upper = uint224(upper_self) * upper_other; // * 2^0
            uint224 lower = uint224(lower_self) * lower_other; // * 2^-224
            uint224 uppers_lowero = uint224(upper_self) * lower_other; // * 2^-112
            uint224 uppero_lowers = uint224(upper_other) * lower_self; // * 2^-112

            // so the bit shift does not overflow
            require(upper <= type(uint112).max, 'FixedPoint::muluq: upper overflow');

            // this cannot exceed 256 bits, all values are 224 bits
            uint256 sum = uint256(upper << RESOLUTION) + uppers_lowero + uppero_lowers + (lower >> RESOLUTION);

            // so the cast does not overflow
            require(sum <= type(uint224).max, 'FixedPoint::muluq: sum overflow');
            return uq112x112(uint224(sum));
        }
    }

    // divide a UQ112x112 by a UQ112x112, returning a UQ112x112
    function divuq(uq112x112 memory self, uq112x112 memory other) internal pure returns (uq112x112 memory) {
        require(other._x > 0, 'FixedPoint::divuq: division by zero');
        if (self._x == other._x) {
            return uq112x112(uint224(Q112));
        }
        if (self._x <= type(uint144).max) {
            uint256 value = (uint256(self._x) << RESOLUTION) / other._x;
            require(value <= type(uint224).max, 'FixedPoint::divuq: overflow');
            return uq112x112(uint224(value));
        }
        unchecked {
            uint256 result = FullMath.mulDiv(Q112, self._x, other._x);
            require(result <= type(uint224).max, 'FixedPoint::divuq: overflow');
            return uq112x112(uint224(result));
        }
    }

    // returns a UQ112x112 which represents the ratio of the numerator to the denominator
    // can be lossy
    function fraction(uint256 numerator, uint256 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, 'FixedPoint::fraction: division by zero');
        if (numerator == 0) return FixedPoint.uq112x112(0);
        unchecked {
            if (numerator <= type(uint144).max) {
                uint256 result = (numerator << RESOLUTION) / denominator;
                require(result <= type(uint224).max, 'FixedPoint::fraction: overflow');
                return uq112x112(uint224(result));
            } else {
                uint256 result = FullMath.mulDiv(numerator, Q112, denominator);
                require(result <= type(uint224).max, 'FixedPoint::fraction: overflow');
                return uq112x112(uint224(result));
            }
        }
    }

    // take the reciprocal of a UQ112x112
    // reverts on overflow
    // lossy
    function reciprocal(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        require(self._x != 0, 'FixedPoint::reciprocal: reciprocal of zero');
        require(self._x != 1, 'FixedPoint::reciprocal: overflow');
        return uq112x112(uint224(Q224 / self._x));
    }

    // square root of a UQ112x112
    // lossy between 0/1 and 40 bits
    function sqrt(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        if (self._x <= type(uint144).max) {
            return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << 112)));
        }
        uint8 safeShiftBits = 255 - BitMath.mostSignificantBit(self._x);
        safeShiftBits -= safeShiftBits % 2;
        return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << safeShiftBits) << ((112 - safeShiftBits) / 2)));
    }
}
EOF
     ;;
   Linux)
cat << EOF > ./node_modules/@uniswap/lib/contracts/libraries/FixedPoint.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.4.0;

import './FullMath.sol';
import './Babylonian.sol';
import './BitMath.sol';

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
library FixedPoint {
    // range: [0, 2**112 - 1]
    // resolution: 1 / 2**112
    struct uq112x112 {
        uint224 _x;
    }

    // range: [0, 2**144 - 1]
    // resolution: 1 / 2**112
    struct uq144x112 {
        uint256 _x;
    }

    uint8 public constant RESOLUTION = 112;
    uint256 public constant Q112 = 0x10000000000000000000000000000; // 2**112
    uint256 private constant Q224 = 0x100000000000000000000000000000000000000000000000000000000; // 2**224
    uint256 private constant LOWER_MASK = 0xffffffffffffffffffffffffffff; // decimal of UQ*x112 (lower 112 bits)

    // encode a uint112 as a UQ112x112
    function encode(uint112 x) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(x) << RESOLUTION);
    }

    // encodes a uint144 as a UQ144x112
    function encode144(uint144 x) internal pure returns (uq144x112 memory) {
        return uq144x112(uint256(x) << RESOLUTION);
    }

    // decode a UQ112x112 into a uint112 by truncating after the radix point
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    // decode a UQ144x112 into a uint144 by truncating after the radix point
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }

    // multiply a UQ112x112 by a uint, returning a UQ144x112
    // reverts on overflow
    function mul(uq112x112 memory self, uint256 y) internal pure returns (uq144x112 memory) {
        unchecked {
            uint256 z = 0;
            require(y == 0 || (z = self._x * y) / y == self._x, 'FixedPoint::mul: overflow');
            return uq144x112(z);
        }
    }

    // multiply a UQ112x112 by an int and decode, returning an int
    // reverts on overflow
    function muli(uq112x112 memory self, int256 y) internal pure returns (int256) {
        unchecked {
            uint256 z = FullMath.mulDiv(self._x, uint256(y < 0 ? -y : y), Q112); 
            require(z < 2**255, 'FixedPoint::muli: overflow');
            return y < 0 ? -int256(z) : int256(z);
        }
    }

    // multiply a UQ112x112 by a UQ112x112, returning a UQ112x112
    // lossy
    function muluq(uq112x112 memory self, uq112x112 memory other) internal pure returns (uq112x112 memory) {
        if (self._x == 0 || other._x == 0) {
            return uq112x112(0);
        }
        unchecked {
            uint112 upper_self = uint112(self._x >> RESOLUTION); // * 2^0
            uint112 lower_self = uint112(self._x & LOWER_MASK); // * 2^-112
            uint112 upper_other = uint112(other._x >> RESOLUTION); // * 2^0
            uint112 lower_other = uint112(other._x & LOWER_MASK); // * 2^-112

            // partial products
            uint224 upper = uint224(upper_self) * upper_other; // * 2^0
            uint224 lower = uint224(lower_self) * lower_other; // * 2^-224
            uint224 uppers_lowero = uint224(upper_self) * lower_other; // * 2^-112
            uint224 uppero_lowers = uint224(upper_other) * lower_self; // * 2^-112

            // so the bit shift does not overflow
            require(upper <= type(uint112).max, 'FixedPoint::muluq: upper overflow');

            // this cannot exceed 256 bits, all values are 224 bits
            uint256 sum = uint256(upper << RESOLUTION) + uppers_lowero + uppero_lowers + (lower >> RESOLUTION);

            // so the cast does not overflow
            require(sum <= type(uint224).max, 'FixedPoint::muluq: sum overflow');
            return uq112x112(uint224(sum));
        }
    }

    // divide a UQ112x112 by a UQ112x112, returning a UQ112x112
    function divuq(uq112x112 memory self, uq112x112 memory other) internal pure returns (uq112x112 memory) {
        require(other._x > 0, 'FixedPoint::divuq: division by zero');
        if (self._x == other._x) {
            return uq112x112(uint224(Q112));
        }
        if (self._x <= type(uint144).max) {
            uint256 value = (uint256(self._x) << RESOLUTION) / other._x;
            require(value <= type(uint224).max, 'FixedPoint::divuq: overflow');
            return uq112x112(uint224(value));
        }
        unchecked {
            uint256 result = FullMath.mulDiv(Q112, self._x, other._x);
            require(result <= type(uint224).max, 'FixedPoint::divuq: overflow');
            return uq112x112(uint224(result));
        }
    }

    // returns a UQ112x112 which represents the ratio of the numerator to the denominator
    // can be lossy
    function fraction(uint256 numerator, uint256 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, 'FixedPoint::fraction: division by zero');
        if (numerator == 0) return FixedPoint.uq112x112(0);
        unchecked {
            if (numerator <= type(uint144).max) {
                uint256 result = (numerator << RESOLUTION) / denominator;
                require(result <= type(uint224).max, 'FixedPoint::fraction: overflow');
                return uq112x112(uint224(result));
            } else {
                uint256 result = FullMath.mulDiv(numerator, Q112, denominator);
                require(result <= type(uint224).max, 'FixedPoint::fraction: overflow');
                return uq112x112(uint224(result));
            }
        }
    }

    // take the reciprocal of a UQ112x112
    // reverts on overflow
    // lossy
    function reciprocal(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        require(self._x != 0, 'FixedPoint::reciprocal: reciprocal of zero');
        require(self._x != 1, 'FixedPoint::reciprocal: overflow');
        return uq112x112(uint224(Q224 / self._x));
    }

    // square root of a UQ112x112
    // lossy between 0/1 and 40 bits
    function sqrt(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        if (self._x <= type(uint144).max) {
            return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << 112)));
        }
        uint8 safeShiftBits = 255 - BitMath.mostSignificantBit(self._x);
        safeShiftBits -= safeShiftBits % 2;
        return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << safeShiftBits) << ((112 - safeShiftBits) / 2)));
    }
}
EOF
     ;;

   *)
     echo 'Other OS'
     ;;
esac

FILE="./node_modules/@uniswap/lib/contracts/libraries/FullMath.sol"
rm -rf $FILE
case "$(uname -s)" in
   Darwin)
cat << 'EOF' >> ./node_modules/@uniswap/lib/contracts/libraries/FullMath.sol
// SPDX-License-Identifier: CC-BY-4.0
pragma solidity >=0.4.0;

// taken from https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
// license is CC-BY-4.0
library FullMath {
    function fullMul(uint256 x, uint256 y) internal pure returns (uint256 l, uint256 h) {
        uint256 mm = mulmod(x, y, type(uint256).max);
        unchecked {
            l = x * y;
            h = mm - l;
            if (mm < l) h -= 1;
        }
    }

    function fullDiv(
        uint256 l,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & (~d+1);
        unchecked {
            d /= pow2;
            l /= pow2;
            l += h * ((~pow2+1) / pow2 + 1);
            uint256 r = 1;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;    
            return l * r;
        }
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);

        uint256 mm = mulmod(x, y, d);
        unchecked {
            if (mm > l) h -= 1;
            l -= mm;

            if (h == 0) return l / d;
        }
        require(h < d, 'FullMath: FULLDIV_OVERFLOW');
        return fullDiv(l, h, d);
    }
}
EOF
     ;;

   Linux)
cat << 'EOF' >> ./node_modules/@uniswap/lib/contracts/libraries/FullMath.sol
// SPDX-License-Identifier: CC-BY-4.0
pragma solidity >=0.4.0;

// taken from https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
// license is CC-BY-4.0
library FullMath {
    function fullMul(uint256 x, uint256 y) internal pure returns (uint256 l, uint256 h) {
        uint256 mm = mulmod(x, y, type(uint256).max);
        unchecked {
            l = x * y;
            h = mm - l;
            if (mm < l) h -= 1;
        }
    }

    function fullDiv(
        uint256 l,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & (~d+1);
        unchecked {
            d /= pow2;
            l /= pow2;
            l += h * ((~pow2+1) / pow2 + 1);
            uint256 r = 1;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;
            r *= 2 - d * r;    
            return l * r;
        }
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);

        uint256 mm = mulmod(x, y, d);
        unchecked {
            if (mm > l) h -= 1;
            l -= mm;

            if (h == 0) return l / d;
        }
        require(h < d, 'FullMath: FULLDIV_OVERFLOW');
        return fullDiv(l, h, d);
    }
}
EOF
     ;;

   *)
     echo 'Other OS'
     ;;
esac
