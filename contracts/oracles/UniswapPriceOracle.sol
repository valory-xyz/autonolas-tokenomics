// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUniswapV2 {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}

/// @title UniswapPriceOracle - a smart contract oracle wrapper for Uniswap V2 pools
/// @dev This contract acts as an oracle wrapper for a specific Uniswap V2 pool. It allows:
///      1) Getting the price by any caller
///      2) Validating slippage against the oracle
contract UniswapPriceOracle {
    // LP token address
    address public immutable pair;
    // Max allowable slippage
    uint256 public immutable maxSlippage;
    // LP token direction
    uint256 public immutable direction;

    constructor(address _nativeToken, uint256 _maxSlippage, address _pair) {
        pair = _pair;
        maxSlippage = _maxSlippage;

        // Get token direction
        address token0 =  IUniswapV2(pair).token0();
        if (token0 != _nativeToken) {
            direction = 1;
        }
    }

    /// @dev Gets the current OLAS token price in 1e18 format.
    function getPrice() public view returns (uint256) {
        uint256[] memory balances = new uint256[](2);
        (balances[0], balances[1], ) = IUniswapV2(pair).getReserves();
        // Native token
        uint256 balanceIn = balances[direction];
        // OLAS
        uint256 balanceOut = balances[(direction + 1) % 2];

        return (balanceOut * 1e18) / balanceIn;
    }

    /// @dev Updates the time-weighted average price.
    /// @notice This is a compatibility function, which always needs to return false, as TWAP is updated automatically.
    function updatePrice() external pure returns (bool) {
        // Nothing to update; use built-in TWAP from Uniswap V2 pool
        return false;
    }

    /// @dev Validates the current price against a TWAP according to slippage tolerance.
    /// @param slippage the acceptable slippage tolerance
    function validatePrice(uint256 slippage) external view returns (bool) {
        require(slippage <= maxSlippage, "Slippage overflow");

        // Compute time-weighted average price
        // Fetch the cumulative prices from the pair
        uint256 cumulativePriceLast;
        if (direction == 0) {
            cumulativePriceLast = IUniswapV2(pair).price1CumulativeLast();
        } else {
            cumulativePriceLast = IUniswapV2(pair).price0CumulativeLast();
        }

        // Fetch the reserves and the last block timestamp
        (, , uint256 blockTimestampLast) = IUniswapV2(pair).getReserves();

        // Require at least one block since last update
        if (block.timestamp == blockTimestampLast) {
            return false;
        }
        uint256 elapsedTime = block.timestamp - blockTimestampLast;

        uint256 tradePrice = getPrice();

        // Calculate cumulative prices
        uint256 cumulativePrice = cumulativePriceLast + (tradePrice * elapsedTime);

        // Calculate the TWAP for OLAS in terms of native token
        uint256 timeWeightedAverage = (cumulativePrice - cumulativePriceLast) / elapsedTime;

        // Get the final derivation to compare with slippage
        // Final derivation value must be
        uint256 derivation = (tradePrice > timeWeightedAverage)
            ? ((tradePrice - timeWeightedAverage) * 1e16) / timeWeightedAverage
            : ((timeWeightedAverage - tradePrice) * 1e16) / timeWeightedAverage;

        return derivation <= slippage;
    }
}
