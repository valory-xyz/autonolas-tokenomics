// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 ^0.8.30;

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

// contracts/utils/LPSwapCelo.sol

// ERC20 token interface
interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

// Uniswap V2 pair interface
interface IUniswapV2Pair {
    function totalSupply() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

// Uniswap V2 Router interface
interface IUniswapV2Router {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

// Oracle interface
interface IOracle {
    /// @dev Gets the current TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256);
}

// L2 Standard Bridge interface (OP-stack)
interface IL2StandardBridge {
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/L2/L2StandardBridge.sol#L121
    /// @dev Initiates a withdrawal from L2 to L1 to a target account on L1.
    /// @param _l2Token Address of the L2 token to withdraw.
    /// @param _to Recipient account on L1.
    /// @param _amount Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData Extra data attached to the withdrawal.
    function withdrawTo(address _l2Token, address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData)
        external;
}

// Wormhole Token Bridge interface
interface IWormholeTokenBridge {
    /// @dev Transfers tokens via Wormhole bridge.
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param recipientChain Wormhole chain Id of the recipient chain.
    /// @param recipient Recipient address in bytes32 format.
    /// @param arbiterFee Arbiter fee (typically 0).
    /// @param nonce Nonce value.
    /// @return sequence Wormhole sequence number.
    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Token transfer failed.
/// @param token Token address.
/// @param from Sender address.
/// @param to Recipient address.
/// @param amount Token amount.
error TransferFailed(address token, address from, address to, uint256 amount);

/// @title LPSwapCelo - Smart contract for swapping whOLAS-CELO liquidity to OLAS-CELO liquidity on Celo
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LPSwapCelo {
    event LiquiditySwapped(uint256 whOlasAmount, uint256 celoAmount, uint256 olasAmount, uint256 newLiquidity);
    event OLASBridgedToL1(uint256 amount);
    event WhOLASBridgedToL1(uint256 amount);

    // Version number
    string public constant VERSION = "0.1.0";
    // Max BPS value
    uint256 public constant MAX_BPS = 10_000;
    // Token transfer gas limit for L1
    uint32 public constant TOKEN_GAS_LIMIT = 300_000;
    // Wormhole chain Id for Ethereum L1
    uint16 public constant WORMHOLE_L1_CHAIN_ID = 2;

    // whOLAS-CELO LP token address on Ubeswap
    address public constant LP_TOKEN = 0x2976Fa805141b467BCBc6334a69AffF4D914d96A;
    // wCELO token address (token0 of LP)
    address public constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    // whOLAS token address (token1 of LP)
    address public constant WHOLAS = 0xaCFfAe8e57Ec6E394Eb1b41939A8CF7892DbDc51;
    // OLAS token address on Celo
    address public constant OLAS = 0xD80533CA29fF6F033a0b55732Ed792af9Fbb381E;
    // L2 Standard Bridge (OP-stack predeploy)
    address public constant L2_STANDARD_BRIDGE = 0x4200000000000000000000000000000000000010;
    // Ubeswap V2 Router address
    address public constant ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    // Wormhole Token Bridge address on Celo
    address public constant WORMHOLE_TOKEN_BRIDGE = 0x796Dff6D74F3E27060B71255Fe517BFb23C93eed;
    // L1 Timelock address (recipient for bridged tokens)
    address public constant L1_TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // Oracle address for TWAP-based slippage protection
    address public immutable oracle;
    // Max slippage for liquidity operations (in BPS)
    uint256 public immutable maxSlippage;

    // Reentrancy lock
    uint8 internal _locked;

    /// @dev LPSwapCelo constructor.
    /// @param _oracle UniswapPriceOracle address for TWAP slippage protection.
    /// @param _maxSlippage Max slippage in BPS (e.g., 100 = 1%).
    constructor(address _oracle, uint256 _maxSlippage) {
        // Check for zero address
        if (_oracle == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_maxSlippage == 0) {
            revert ZeroValue();
        }

        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        oracle = _oracle;
        maxSlippage = _maxSlippage;

        _locked = 1;
    }

    /// @dev Swaps whOLAS-CELO liquidity to OLAS-CELO liquidity and bridges leftovers to L1.
    function swapLiquidity() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Step 1: Check LP token balance
        uint256 liquidity = IToken(LP_TOKEN).balanceOf(address(this));
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Step 2: Remove whOLAS-CELO liquidity with TWAP slippage protection
        (uint256 whOlasAmount, uint256 celoAmount) = _removeLiquidity(liquidity);

        // Step 3: Add OLAS-CELO liquidity using same amounts
        uint256 newLiquidity = _addLiquidity(whOlasAmount, celoAmount);

        emit LiquiditySwapped(whOlasAmount, celoAmount, whOlasAmount, newLiquidity);

        // Step 4: Bridge remaining OLAS to L1 Timelock via native bridge
        _bridgeOLAS();

        // Step 5: Bridge remaining whOLAS to L1 Timelock via Wormhole
        _bridgeWhOLAS();

        _locked = 1;
    }

    /// @dev Removes whOLAS-CELO liquidity with TWAP-based slippage protection.
    /// @param liquidity LP token amount to remove.
    /// @return whOlasAmount Received whOLAS amount.
    /// @return celoAmount Received CELO amount.
    function _removeLiquidity(uint256 liquidity) internal returns (uint256 whOlasAmount, uint256 celoAmount) {
        // Compute TWAP-based manipulation-resistant minAmountsOut
        uint256 minAmountCelo;
        uint256 minAmountWhOlas;
        {
            // Get reserves and totalSupply from the pair
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(LP_TOKEN).getReserves();
            uint256 totalSupply = IUniswapV2Pair(LP_TOKEN).totalSupply();

            // k = reserve0 * reserve1 is manipulation-resistant (invariant across swaps)
            uint256 k = uint256(reserve0) * uint256(reserve1);

            // TWAP is OLAS per secondToken in 1e18 format
            // For whOLAS-CELO pair: token0 = WCELO, token1 = whOLAS
            // Oracle direction: OLAS(whOLAS) per CELO, so twap = whOLAS/CELO price
            uint256 twap = IOracle(oracle).getTWAP();

            // Compute fair reserves using constant product invariant and TWAP price
            // token0 is WCELO (secondToken), token1 is whOLAS (OLAS-like)
            // fair_r0 = sqrt(k * 1e18 / twap), fair_r1 = sqrt(k * twap / 1e18)
            uint256 fairReserve0 = FixedPointMathLib.sqrt(k * 1e18 / twap);
            uint256 fairReserve1 = FixedPointMathLib.sqrt(k * twap / 1e18);

            // Expected withdrawal amounts (proportional to fair reserves)
            // minAmount = liquidity * fairReserve / totalSupply * (MAX_BPS - maxSlippage) / MAX_BPS
            minAmountCelo = (liquidity * fairReserve0 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
            minAmountWhOlas = (liquidity * fairReserve1 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
        }

        // Approve LP tokens for the router
        IToken(LP_TOKEN).approve(ROUTER, liquidity);

        // Remove liquidity with TWAP-derived slippage protection
        // token0 = WCELO, token1 = whOLAS
        (celoAmount, whOlasAmount) = IUniswapV2Router(ROUTER)
            .removeLiquidity(WCELO, WHOLAS, liquidity, minAmountCelo, minAmountWhOlas, address(this), block.timestamp);
    }

    /// @dev Adds OLAS-CELO liquidity using the same amounts as removed from whOLAS-CELO.
    /// @param olasDesired Desired OLAS amount (same as removed whOLAS amount).
    /// @param celoDesired Desired CELO amount (same as removed CELO amount).
    /// @return liquidity New LP token amount created.
    function _addLiquidity(uint256 olasDesired, uint256 celoDesired) internal returns (uint256 liquidity) {
        // The olasDesired and celoDesired amounts come from the TWAP-protected whOLAS-CELO removal,
        // which means they already reflect the fair OLAS/CELO price ratio.
        //
        // If the OLAS-CELO pair does not exist yet, the router creates it and uses both amounts
        // exactly, so min amounts have no effect.
        //
        // If the OLAS-CELO pair already exists, an attacker could have manipulated its reserves
        // before this call. The router's addLiquidity adjusts one of the desired amounts down to
        // match the current pool ratio. With a skewed pool, the router would accept a bad ratio
        // and the attacker profits by sandwiching the other side.
        //
        // Since whOLAS and OLAS are equivalent in value, the whOLAS-CELO TWAP serves as a valid
        // reference price for the expected OLAS/CELO ratio. Applying maxSlippage to the
        // TWAP-derived desired amounts ensures the router reverts if the OLAS-CELO pool ratio
        // deviates too far from the fair price.
        //
        // celoMin is set to the full celoDesired amount to guarantee all CELO is deposited into
        // the new pair. Any leftover OLAS (if the router adjusts it down) gets bridged to L1.
        uint256 olasMin = (olasDesired * (MAX_BPS - maxSlippage)) / MAX_BPS;

        // Approve tokens for the router
        IToken(OLAS).approve(ROUTER, olasDesired);
        IToken(WCELO).approve(ROUTER, celoDesired);

        // Add liquidity (router creates pair if it does not exist)
        (, , liquidity) = IUniswapV2Router(ROUTER)
            .addLiquidity(OLAS, WCELO, olasDesired, celoDesired, olasMin, celoDesired, address(this), block.timestamp);
    }

    /// @dev Bridges remaining OLAS to L1 Timelock via Celo native bridge (OP-stack).
    function _bridgeOLAS() internal {
        uint256 olasBalance = IToken(OLAS).balanceOf(address(this));
        if (olasBalance > 0) {
            // Approve OLAS for the L2 Standard Bridge
            IToken(OLAS).approve(L2_STANDARD_BRIDGE, olasBalance);

            // Bridge OLAS to L1 Timelock
            IL2StandardBridge(L2_STANDARD_BRIDGE).withdrawTo(OLAS, L1_TIMELOCK, olasBalance, TOKEN_GAS_LIMIT, "");

            emit OLASBridgedToL1(olasBalance);
        }
    }

    /// @dev Bridges remaining whOLAS to L1 Timelock via Wormhole Token Bridge.
    function _bridgeWhOLAS() internal {
        uint256 whOlasBalance = IToken(WHOLAS).balanceOf(address(this));
        if (whOlasBalance > 0) {
            // Approve whOLAS for the Wormhole Token Bridge
            IToken(WHOLAS).approve(WORMHOLE_TOKEN_BRIDGE, whOlasBalance);

            // Convert L1_TIMELOCK address to bytes32 for Wormhole
            bytes32 recipient = bytes32(uint256(uint160(L1_TIMELOCK)));

            // Bridge whOLAS to L1 Timelock via Wormhole
            IWormholeTokenBridge(WORMHOLE_TOKEN_BRIDGE).transferTokens(
                WHOLAS, whOlasBalance, WORMHOLE_L1_CHAIN_ID, recipient, 0, 0
            );

            emit WhOLASBridgedToL1(whOlasBalance);
        }
    }
}

