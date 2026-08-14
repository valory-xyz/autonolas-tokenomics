// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";

interface ICLFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist.
    /// @param tokenA The contract address of either token0 or token1.
    /// @param tokenB The contract address of the other token.
    /// @param tickSpacing The tick spacing of the pool.
    /// @return pool The pool address.
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
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

    /// @notice Creates a new position wrapped in a NFT.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata.
    /// @return tokenId The ID of the token that represents the minted position.
    /// @return liquidity The amount of liquidity for this position.
    /// @return amount0 The amount of token0.
    /// @return amount1 The amount of token1.
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title Liquidity Manager Target Slipstream - Velodrome/Aerodrome Slipstream concentrated-liquidity mint mixin
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Mints concentrated liquidity via a Slipstream (Velodrome/Aerodrome) NonfungiblePositionManager, which
///      is tick-spacing-indexed rather than fee-tier-indexed. Reads the NPM and factory from `LiquidityManagerCore`.
abstract contract LiquidityManagerTargetSlipstream is LiquidityManagerCore {
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
