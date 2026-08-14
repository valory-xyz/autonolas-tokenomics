// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore, ZeroAddress} from "./LiquidityManagerCore.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

/// @dev Expected token addresses do not match provided ones.
/// @param provided Provided token addresses.
/// @param expected Expected token addresses.
error WrongTokenAddresses(address[] provided, address[] expected);

interface IOracle {
    /// @dev Gets the current TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256);
}

/// @title Liquidity Manager Source Base - Shared source-side machinery for POL withdrawal mixins
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Holds the source-side price oracle and the manipulation-resistant, TWAP-anchored min-amounts-out
///      computation shared by every `_checkTokensAndRemoveLiquidityV2` implementation (Uniswap V2, Balancer).
///      The withdrawal itself (which DEX to exit and how) is left abstract to the concrete source mixin.
abstract contract LiquidityManagerSourceBase is LiquidityManagerCore {
    // Source pool (V2/Balancer) related OLAS TWAP oracle address
    address public immutable oracleV2;

    /// @dev LiquidityManagerSourceBase constructor.
    /// @param _oracleV2 Source pool related oracle address.
    constructor(address _oracleV2) {
        // Check for zero address
        if (_oracleV2 == address(0)) {
            revert ZeroAddress();
        }

        oracleV2 = _oracleV2;
    }

    /// @dev Computes manipulation-resistant minimum withdrawal amounts from the constant-product invariant.
    /// @notice `k` (reserve0 * reserve1, or balance0 * balance1) is invariant across swaps, so pairing it with
    ///         the OLAS TWAP yields fair reserves the removal must at least honor (floored by `maxSlippage`).
    ///         NOTE: whether this TWAP floor (and therefore `oracleV2` and `maxSlippage`) is needed at all is
    ///         tracked in issue #324 — a proportional removeLiquidity cannot be sandwiched for a value loss
    ///         (constant-product convexity, per internal20 R6), so it may be droppable. Read #324 before changing.
    /// @param k Constant-product invariant of the source pool (product of the two reserves/balances).
    /// @param token0IsOlas True if `tokens[0]` is OLAS (selects which fair reserve gets the TWAP numerator).
    /// @param liquidity This contract's LP/BPT balance being withdrawn.
    /// @param totalSupply Total LP/BPT supply of the source pool.
    /// @return minAmount0 Minimum out for token0.
    /// @return minAmount1 Minimum out for token1.
    function _fairMinAmountsOut(uint256 k, bool token0IsOlas, uint256 liquidity, uint256 totalSupply)
        internal
        view
        returns (uint256 minAmount0, uint256 minAmount1)
    {
        // TWAP is OLAS per secondToken in 1e18 format
        uint256 twap = IOracle(oracleV2).getTWAP();

        // Compute fair reserves using constant product invariant and TWAP price
        // If token0 is OLAS: fair_r0 = sqrt(k * twap / 1e18), fair_r1 = sqrt(k * 1e18 / twap)
        // If token1 is OLAS: fair_r0 = sqrt(k * 1e18 / twap), fair_r1 = sqrt(k * twap / 1e18)
        uint256 fairReserve0;
        uint256 fairReserve1;
        if (token0IsOlas) {
            fairReserve0 = FixedPointMathLib.sqrt(FixedPointMathLib.mulDivDown(k, twap, 1e18));
            fairReserve1 = FixedPointMathLib.sqrt(FixedPointMathLib.mulDivDown(k, 1e18, twap));
        } else {
            fairReserve0 = FixedPointMathLib.sqrt(FixedPointMathLib.mulDivDown(k, 1e18, twap));
            fairReserve1 = FixedPointMathLib.sqrt(FixedPointMathLib.mulDivDown(k, twap, 1e18));
        }

        // Expected withdrawal amounts (proportional to fair reserves)
        // minAmount = liquidity * fairReserve / totalSupply * (MAX_BPS - maxSlippage) / MAX_BPS
        minAmount0 = (liquidity * fairReserve0 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
        minAmount1 = (liquidity * fairReserve1 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
    }
}
