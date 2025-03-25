// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVault {
    function getPoolTokens(bytes32 poolId) external view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

/// @title BalancerPriceOracle - a smart contract oracle for Balancer V2 pools
/// @dev This contract acts as an oracle for a specific Balancer V2 pool. It allows:
///      1) Updating the price by any caller
///      2) Getting the price by any caller
///      3) Validating slippage against the oracle
contract BalancerPriceOracle {
    event PriceUpdated(address indexed sender, uint256 currentPrice, uint256 cumulativePrice);

    struct PriceSnapshot {
        // Time-weighted cumulative price
        uint256 cumulativePrice;
        // Timestamp of the last update
        uint256 lastUpdated;
        // Most recent calculated average price
        uint256 averagePrice;
    }

    // Snapshot history struct
    PriceSnapshot public snapshotHistory;

    // Maximum allowed update slippage in %
    uint256 public immutable maxSlippage;
    // Minimum update time period in seconds
    uint256 public immutable minUpdateTimePeriod;
    // LP token direction
    uint256 public immutable direction;
    // Native token (ERC-20) address
    address public immutable nativeToken;
    // OLAS token address
    address public immutable olas;
    // Balancer vault address
    address public immutable balancerVault;
    // Balancer pool Id
    bytes32 public immutable balancerPoolId;

    constructor(
        address _olas,
        address _nativeToken,
        uint256 _maxSlippage,
        uint256 _minUpdateTimePeriod,
        address _balancerVault,
        bytes32 _balancerPoolId
    ) {
        require(_maxSlippage < 100, "Slippage must be less than 100%");

        olas = _olas;
        nativeToken = _nativeToken;
        maxSlippage = _maxSlippage;
        minUpdateTimePeriod = _minUpdateTimePeriod;
        balancerVault = _balancerVault;
        balancerPoolId = _balancerPoolId;

        // Get token direction
        (address[] memory tokens, , ) = IVault(balancerVault).getPoolTokens(_balancerPoolId);
        if (tokens[0] != _nativeToken) {
            direction = 1;
        }

        // Initialize price snapshot
        updatePrice();
    }

    /// @dev Gets the current OLAS token price in 1e18 format.
    function getPrice() public view returns (uint256) {
        (, uint256[] memory balances, ) = IVault(balancerVault).getPoolTokens(balancerPoolId);
        // Native token
        uint256 balanceIn = balances[direction];
        // OLAS
        uint256 balanceOut = balances[(direction + 1) % 2];

        return (balanceOut * 1e18) / balanceIn;
    }

    /// @dev Updates the time-weighted average price.
    /// @notice This implementation only accounts for the first price update in a block.
    function updatePrice() public returns (bool) {
        uint256 currentPrice = getPrice();
        require(currentPrice > 0, "Price must be non-zero");

        PriceSnapshot storage snapshot = snapshotHistory;

        if (snapshot.lastUpdated == 0) {
            // Initialize snapshot
            snapshot.cumulativePrice = 0;
            snapshot.averagePrice = currentPrice;
            snapshot.lastUpdated = block.timestamp;
            emit PriceUpdated(msg.sender, currentPrice, 0);
            return true;
        }

        // Check if update is too soon
        if (block.timestamp < snapshotHistory.lastUpdated + minUpdateTimePeriod) {
            return false;
        }

        // This implementation only accounts for the first price update in a block.
        // Calculate elapsed time since the last update
        uint256 elapsedTime = block.timestamp - snapshot.lastUpdated;

        // Update cumulative price with the previous average over the elapsed time
        snapshot.cumulativePrice += snapshot.averagePrice * elapsedTime;

        // Update the average price to reflect the current price
        uint256 averagePrice = (snapshot.cumulativePrice + (currentPrice * elapsedTime)) /
            ((snapshot.cumulativePrice / snapshot.averagePrice) + elapsedTime);

        // Check if price deviation is too high
        if (currentPrice < averagePrice - (averagePrice * maxSlippage / 100) ||
            currentPrice > averagePrice + (averagePrice * maxSlippage / 100))
        {
            return false;
        }

        snapshot.averagePrice = averagePrice;
        snapshot.lastUpdated = block.timestamp;

        emit PriceUpdated(msg.sender, currentPrice, snapshot.cumulativePrice);

        return true;
    }

    /// @dev Validates Current price against a TWAP according to slippage tolerance.
    /// @param slippage Acceptable slippage tolerance.
    function validatePrice(uint256 slippage) external view returns (bool) {
        require(slippage <= maxSlippage, "Slippage overflow");

        PriceSnapshot memory snapshot = snapshotHistory;

        // Ensure there is historical price data
        if (snapshot.lastUpdated == 0) return false;

        // Calculate elapsed time
        uint256 elapsedTime = block.timestamp - snapshot.lastUpdated;
        // Require at least one block since last update
        if (elapsedTime == 0) return false;

        // Compute time-weighted average price
        uint256 timeWeightedAverage = (snapshot.cumulativePrice + (snapshot.averagePrice * elapsedTime)) /
            ((snapshot.cumulativePrice / snapshot.averagePrice) + elapsedTime);

        uint256 tradePrice = getPrice();

        // Validate against slippage thresholds
        uint256 lowerBound = (timeWeightedAverage * (100 - slippage)) / 100;
        uint256 upperBound = (timeWeightedAverage * (100 + slippage)) / 100;

        return tradePrice >= lowerBound && tradePrice <= upperBound;
    }
}
