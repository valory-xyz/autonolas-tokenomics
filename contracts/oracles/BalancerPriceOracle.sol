// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IVault {
    function getPoolTokens(bytes32 poolId) external view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Provided wrong pool.
/// @param tokens Token addresses.
error WrongPool(address[] tokens);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);


/// @title BalancerPriceOracle - a smart contract oracle for Balancer V2 pools (BPS version)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev This contract acts as an oracle for a specific Balancer V2 pool. It allows:
///      1) Getting the spot price (balance ratio) in 1e18 format
///      2) Validating slippage against a proper two-observation rolling-window TWAP
///
///      Fixes vs the original version:
///      - TWAP is computed from two independent observations (delta_cumulative / delta_t).
///      - No state mutation on rejected updates (commit-on-success).
///      - Avoids permanent freeze after large market moves by allowing baseline to adapt via rolling-window TWAP.
///      - updatePrice() is rate-limited to prevent griefing resets of the observation.
///      - Adds freshness constraints for validation.
///      - Slippage is specified in basis points (BPS), 10_000 = 100%.
contract BalancerPriceOracle {
    event ObservationUpdated(address indexed sender, uint256 priceCumulative, uint256 timestamp);

    // Max BPS value
    uint256 public constant MAX_BPS = 10_000;

    // Max allowable slippage in BPS (0..MAX_BPS)
    uint256 public immutable maxSlippageBps;
    // Minimum time between successful updatePrice() calls (seconds)
    uint256 public immutable minUpdateInterval;
    // Minimum TWAP window required for validation (seconds)
    uint256 public immutable minTwapWindow;
    // Maximum allowed staleness of the last observation for validatePrice (seconds)
    uint256 public immutable maxStaleness;

    // LP token direction:
    //   direction==0 => balances[0] is secondToken (in), balances[1] is OLAS (out)
    //   direction==1 => balances[1] is secondToken (in), balances[0] is OLAS (out)
    uint256 public immutable direction;

    // Balancer vault address
    address public immutable balancerVault;
    // Balancer pool Id
    bytes32 public immutable balancerPoolId;

    struct Observation {
        // Time-weighted cumulative price (1e18 * seconds)
        uint256 priceCumulative;
        // Timestamp of the observation
        uint256 timestamp;
    }

    // Previous observation for rolling TWAP window
    Observation public prevObservation;
    // Stored last observation used for TWAP
    Observation public lastObservation;

    /// @dev BalancerPriceOracle constructor.
    /// @param _balancerVault Balancer vault address.
    /// @param _balancerPoolId Balancer pool Id.
    /// @param _olas OLAS address.
    /// @param _maxSlippageBps Max slippage BPS.
    /// @param _minTwapWindowSeconds Min TWAP window in seconds.
    /// @param _minUpdateIntervalSeconds Min price update interval in seconds.
    /// @param _maxStalenessSeconds Max staleness in seconds.
    constructor(
        address _balancerVault,
        bytes32 _balancerPoolId,
        address _olas,
        uint256 _maxSlippageBps,
        uint256 _minTwapWindowSeconds,
        uint256 _minUpdateIntervalSeconds,
        uint256 _maxStalenessSeconds
    ) {
        // Check for zero address
        if (_balancerVault == address(0)) {
            revert ZeroAddress();
        }

        // Check for overflow
        if (_maxSlippageBps > MAX_BPS) {
            revert Overflow(_maxSlippageBps, MAX_BPS);
        }

        // TODO _minUpdateIntervalSeconds?
        // Check for zero value
        if (_minTwapWindowSeconds == 0) {
            revert ZeroValue();
        }

        // Check for maxStaleness consistency
        if (_minTwapWindowSeconds > _maxStalenessSeconds) {
            revert Overflow(_minTwapWindowSeconds, _maxStalenessSeconds);
        }

        maxSlippageBps = _maxSlippageBps;
        minUpdateInterval = _minUpdateIntervalSeconds;
        minTwapWindow = _minTwapWindowSeconds;
        maxStaleness = _maxStalenessSeconds;
        balancerVault = _balancerVault;
        balancerPoolId = _balancerPoolId;

        // Get tokens from pool
        (address[] memory tokens, , ) = IVault(balancerVault).getPoolTokens(_balancerPoolId);

        // Check for pool validity
        if (tokens.length != 2 || (tokens[0] != _olas && tokens[1] != _olas)) {
            revert WrongPool(tokens);
        }

        // Get token direction
        if (tokens[0] == _olas) {
            direction = 1;
        }

        // Bootstrap observations with current timestamp
        getPrice();
        prevObservation = Observation({priceCumulative: 0, timestamp: block.timestamp});
        lastObservation = Observation({priceCumulative: 0, timestamp: block.timestamp});

        emit ObservationUpdated(msg.sender, 0, block.timestamp);
    }

    /// @dev Gets the current OLAS token price in 1e18 format.
    /// @return Current spot price in 1e18 format.
    function getPrice() public view returns (uint256) {
        // Get pool balances
        (, uint256[] memory balances, ) = IVault(balancerVault).getPoolTokens(balancerPoolId);

        // Second token balance
        uint256 balanceIn = balances[direction];
        // OLAS balance
        uint256 balanceOut = balances[(direction + 1) % 2];

        // Check for zero values
        if (balanceIn == 0 || balanceOut == 0) {
            revert ZeroValue();
        }

        return (balanceOut * 1e18) / balanceIn;
    }

    /// @dev Records a new rolling TWAP observation from the Balancer V2 pool.
    /// @notice Permissionless but rate-limited to prevent griefing resets.
    /// @return True if price update is successful.
    function updatePrice() external returns (bool) {
        // Get last observation
        Observation memory last = lastObservation;
        // Calculate dt
        uint256 dt = block.timestamp - last.timestamp;

        // Check if dt is lower than min update interval
        if (last.timestamp > 0 && dt < minUpdateInterval) {
            return false;
        }

        // Get current spot price
        uint256 spot = getPrice();

        // Check for zero value
        if (spot == 0) {
            revert ZeroValue();
        }

        // Compute prospective cumulative at now based on last observation + spot * dt (commit-on-success)
        uint256 priceCumulativeNow = last.priceCumulative;
        if (dt > 0) {
            priceCumulativeNow += spot * dt;
        }

        // Shift window: previous becomes last, current becomes new last
        prevObservation = last;
        lastObservation = Observation({priceCumulative: priceCumulativeNow, timestamp: block.timestamp});

        emit ObservationUpdated(msg.sender, priceCumulativeNow, block.timestamp);

        return true;
    }

    /// @dev Validates the current spot price against a TWAP according to slippage tolerance.
    ///      Returns false (not revert) for "insufficient data" cases to reduce DoS risk.
    /// @param slippageBps Acceptable slippage tolerance in basis points.
    /// @return True if price is validated.
    function validatePrice(uint256 slippageBps) external view returns (bool) {
        // Check for requested slippage value
        if (slippageBps > maxSlippageBps) {
            revert Overflow(slippageBps, maxSlippageBps);
        }

        // Get observations
        Observation memory prev = prevObservation;
        Observation memory last = lastObservation;

        // Check if initialized
        if (prev.timestamp == 0 || last.timestamp == 0) {
            revert ZeroValue();
        }

        // Freshness: require that last observation is not too old
        uint256 age = block.timestamp - last.timestamp;
        if (age > maxStaleness) {
            revert Overflow(age, maxStaleness);
        }

        // TWAP history check: need a usable window
        uint256 dtWin = block.timestamp - prev.timestamp;
        if (dtWin < minTwapWindow) {
            // Window too small: not enough history for TWAP
            return false;
        }

        // Get spot price
        uint256 spot = getPrice();
        if (spot == 0) {
            return false;
        }

        // Counterfactual cumulative at now using last observation + current spot over elapsed time
        uint256 priceCumulativeNow = last.priceCumulative + spot * age;

        // Rolling TWAP over [prev.timestamp, now]
        uint256 twap = (priceCumulativeNow - prev.priceCumulative) / dtWin;

        // Check for zero value
        if (twap == 0) {
            return false;
        }

        // Calculate price difference
        uint256 diff = (spot > twap) ? (spot - twap) : (twap - spot);

        // Compare as BPS: diff / twap <= slippageBps / MAX_BPS
        // => diff * MAX_BPS <= twap * slippageBps
        return diff * MAX_BPS <= twap * slippageBps;
    }
}
