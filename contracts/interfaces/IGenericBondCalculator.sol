// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Interface for generic bond calculator.
interface IGenericBondCalculator {
    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(uint256 tokenAmount, uint256 priceLP) external view
        returns (uint256 amountOLAS);

    /// @dev Get reserveX/reserveY at the time of product creation.
    /// @param token Token address.
    /// @return priceLP Resulting reserve ratio.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP);


    /// @dev Gets last cumulative price and block timestamp from the OLAS-contained LP.
    /// @param token LP token address.
    /// @return priceCumulative OLAS cumulative price.
    /// @return btsLast Last block timestamp.
    function priceCumulativeLast(address token) external view returns (uint256 priceCumulative, uint256 btsLast);

    /// @dev Gets current cumulative price of LP token.
    /// @param token LP token address.
    /// @return priceCumulative Current cumulative price.
    function priceCumulativeCurrent(address token) external view returns (uint256 priceCumulative);

    /// @dev Gets average price.
    /// @param priceCurrent Current cumulative price.
    /// @param priceLast Last cumulative price.
    /// @param timeElapsed Elapsed time.
    /// @return priceAvg Average price.
    function priceAverage(uint256 priceCurrent, uint256 priceLast, uint256 timeElapsed)
        external pure returns (uint256 priceAvg);

    /// @dev Gets price in the current block.
    /// @param token LP token address.
    /// @return price Price in the current block.
    function priceNow(address token) external view returns(uint256 price);
}
