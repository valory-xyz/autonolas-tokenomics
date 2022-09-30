// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Interface for generic bond calculator.
interface IGenericBondCalculator {
    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(uint224 tokenAmount, uint256 priceLP) external view
        returns (uint96 amountOLAS);

    /// @dev Get reserveX/reserveY at the time of product creation.
    /// @param token Token address.
    /// @return priceLP Resulting reserve ratio.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP);

    /// @dev Checks if the token is a UniswapV2Pair.
    /// @param token Address of an LP token.
    /// @return success True if successful.
    function checkLP(address token) external returns (bool success);
}
