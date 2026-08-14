// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";

/// @dev Value underflow.
/// @param provided Underflow value.
/// @param min Minimum possible value.
error Underflow(int256 provided, int256 min);

interface IUniV3Factory {
    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled.
    /// @param fee The enabled fee, denominated in hundredths of a bip.
    /// @return The tick spacing.
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist.
    /// @param tokenA The contract address of either token0 or token1.
    /// @param tokenB The contract address of the other token.
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip.
    /// @return pool The pool address.
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @title Liquidity Manager Target UniV3 - Uniswap V3 concentrated-liquidity mint mixin
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Mints concentrated liquidity via a canonical Uniswap V3 NonfungiblePositionManager. The fee tier
///      selects the tick spacing through the V3 factory. Reads the NPM and factory from `LiquidityManagerCore`.
abstract contract LiquidityManagerTargetUniV3 is LiquidityManagerCore {
    /// @inheritdoc LiquidityManagerCore
    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTier,
        uint160
    ) internal virtual override returns (uint256 positionId, uint128 liquidity, uint256[] memory) {
        // Params for minting
        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
            token0: tokens[0],
            token1: tokens[1],
            fee: uint24(feeTier),
            tickLower: ticks[0],
            tickUpper: ticks[1],
            amount0Desired: amounts[0],
            amount1Desired: amounts[1],
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            recipient: address(this),
            deadline: block.timestamp
        });

        // Mint position
        (positionId, liquidity, amounts[0], amounts[1]) = IUniswapV3(positionManagerV3).mint(params);

        return (positionId, liquidity, amounts);
    }

    /// @dev Gets tick spacing according to fee tier or tick spacing directly.
    /// @param feeTier Fee tier.
    /// @return Tick spacing.
    function _feeAmountTickSpacing(int24 feeTier) internal view virtual override returns (int24) {
        // Check for value underflow
        if (feeTier < 0) {
            revert Underflow(feeTier, 0);
        }

        return IUniV3Factory(factoryV3).feeAmountTickSpacing(uint24(feeTier));
    }

    /// @dev Gets V3 pool based on token addresses and fee tier.
    /// @param tokens Token addresses.
    /// @param feeTier Fee tier.
    /// @return V3 pool address.
    function _getV3Pool(address[] memory tokens, int24 feeTier) internal view virtual override returns (address) {
        // Check for value underflow
        if (feeTier < 0) {
            revert Underflow(feeTier, 0);
        }

        return IUniV3Factory(factoryV3).getPool(tokens[0], tokens[1], uint24(feeTier));
    }
}
