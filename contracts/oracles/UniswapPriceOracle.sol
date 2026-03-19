// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UQ112x112} from "../libraries/UQ112x112.sol";

interface IUniswapV2 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Provided wrong pool.
/// @param tokens Token addresses.
error WrongPool(address[] tokens);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @title UniswapPriceOracle - a smart contract oracle wrapper for Uniswap V2 pools (BPS version)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev This contract acts as an oracle wrapper for a specific Uniswap V2 pool. It allows:
///      1) Getting the spot price (reserve ratio) in UQ112x112 format
///      2) Getting the TWAP price in 1e18 format
///
///      Fixes vs the original version:
///      - TWAP is computed from two independent observations (delta_cumulative / delta_t).
///      - No reliance on block.timestamp == blockTimestampLast (avoids per-block sync griefing).
///      - No mixing of incompatible encodings: cumulative prices are UQ112x112 * seconds; TWAP is UQ112x112.
///      - updatePrice() is rate-limited to prevent griefing resets of the observation.
contract UniswapPriceOracle {
    using UQ112x112 for uint224;

    event ObservationUpdated(address indexed sender, uint256 priceCumulative, uint256 timestamp);

    // LP token address
    address public immutable pair;
    // LP token direction:
    //   direction==0 => price0 (token1/token0), use price0CumulativeLast
    //   direction==1 => price1 (token0/token1), use price1CumulativeLast
    uint256 public immutable direction;
    // Minimum TWAP window required for validation (seconds)
    uint256 public immutable minTwapWindow;
    // Minimum time between successful updatePrice() calls (seconds)
    uint256 public immutable minUpdateInterval;
    // Maximum allowed staleness of the last observation (seconds)
    uint256 public immutable maxStaleness;

    struct Observation {
        // UQ112x112 * seconds
        uint256 priceCumulative;
        // Timestamp
        uint256 timestamp;
    }

    // Previous observation for rolling TWAP window
    Observation public prevObservation;
    // Stored last observation used for TWAP
    Observation public lastObservation;

    /// @dev UniswapPriceOracle constructor.
    /// @param _pair LP token with OLAS.
    /// @param _olas OLAS address.
    /// @param _minTwapWindowSeconds Min TWAP window in seconds.
    /// @param _minUpdateIntervalSeconds Min price update interval in seconds.
    /// @param _maxStalenessSeconds Max staleness in seconds.
    constructor(
        address _pair,
        address _olas,
        uint256 _minTwapWindowSeconds,
        uint256 _minUpdateIntervalSeconds,
        uint256 _maxStalenessSeconds
    ) {
        // Check for zero address
        if (_pair == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (_minTwapWindowSeconds == 0 || _minUpdateIntervalSeconds == 0) {
            revert ZeroValue();
        }

        // Check for update interval
        if (_minTwapWindowSeconds > _minUpdateIntervalSeconds) {
            revert Overflow(_minTwapWindowSeconds, _minUpdateIntervalSeconds);
        }

        // Check for maxStaleness consistency
        if (_minTwapWindowSeconds > _maxStalenessSeconds) {
            revert Overflow(_minTwapWindowSeconds, _maxStalenessSeconds);
        }

        pair = _pair;
        minTwapWindow = _minTwapWindowSeconds;
        minUpdateInterval = _minUpdateIntervalSeconds;
        maxStaleness = _maxStalenessSeconds;

        // Get tokens from pair
        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (IUniswapV2(pair).token0(), IUniswapV2(pair).token1());

        // Check for pair validity
        if (tokens[0] != _olas && tokens[1] != _olas) {
            revert WrongPool(tokens);
        }

        // Get token direction
        if (tokens[0] == _olas) {
            direction = 1;
        }
    }

    /// @dev Gets the current spot price (reserve ratio) in UQ112x112 format.
    /// @return Current spot price in UQ112x112 format.
    function getPrice() public view returns (uint256) {
        // Get reserves
        (uint112 r0, uint112 r1,) = IUniswapV2(pair).getReserves();

        // Check for zero values
        if (r0 == 0 || r1 == 0) {
            revert ZeroValue();
        }

        // direction == 0 ? token1 / token0 : token0 / token1
        return (direction == 0) ? UQ112x112.encode(r1).uqdiv(r0) : UQ112x112.encode(r0).uqdiv(r1);
    }

    /// @dev Records a fresh TWAP observation from the Uniswap V2 pair.
    /// @notice Permissionless but rate-limited to prevent griefing resets.
    /// @return True if price update is successful.
    function updatePrice() external returns (bool) {
        // Get current cumulative price
        uint256 priceCumulativeNow = _currentCumulativePrice();

        // Get last observation
        Observation memory obs = lastObservation;
        if (obs.timestamp > 0) {
            // Get observation dt
            uint256 dt = block.timestamp - obs.timestamp;

            // Check if dt is lower than min update interval
            if (dt < minUpdateInterval) {
                return false;
            }
        }

        // Shift window: previous becomes last, current becomes new last
        prevObservation = lastObservation;
        lastObservation = Observation({priceCumulative: priceCumulativeNow, timestamp: block.timestamp});

        emit ObservationUpdated(msg.sender, priceCumulativeNow, block.timestamp);

        return true;
    }

    /// @dev Gets the current TWAP price in 1e18 format.
    ///      Reverts if the oracle is not initialized, observations are stale, or the TWAP window is insufficient.
    ///      Requires at least 2 updatePrice() calls for warmup.
    /// @return TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256) {
        // Get both observations
        Observation memory prev = prevObservation;
        Observation memory last = lastObservation;

        // Check if initialized (need at least 2 updatePrice() calls)
        if (prev.timestamp == 0 || last.timestamp == 0) {
            revert ZeroValue();
        }

        // Freshness: require that last observation is not too old
        uint256 age = block.timestamp - last.timestamp;
        if (age > maxStaleness) {
            revert Overflow(age, maxStaleness);
        }

        // Get current cumulative price
        uint256 priceCumulativeNow = _currentCumulativePrice();

        // TWAP window: from prev observation to now
        uint256 dtWin = block.timestamp - prev.timestamp;

        // TWAP history check
        if (dtWin < minTwapWindow || dtWin == 0) {
            revert ZeroValue();
        }

        // TWAP in UQ112x112
        uint224 twapUQ = uint224((priceCumulativeNow - prev.priceCumulative) / dtWin);

        // Check for zero value
        if (twapUQ == 0) {
            revert ZeroValue();
        }

        // Convert from UQ112x112 to 1e18 format
        return (uint256(twapUQ) * 1e18) >> 112;
    }

    /// @dev Computes the current cumulative price (counterfactual) at block.timestamp.
    function _currentCumulativePrice() internal view returns (uint256 priceCumulative) {
        // Get LP token
        IUniswapV2 lpToken = IUniswapV2(pair);

        // Fetch the cumulative price from the pair
        uint256 priceCumulativeLast = (direction == 0) ? lpToken.price0CumulativeLast() : lpToken.price1CumulativeLast();
        (uint112 r0, uint112 r1, uint32 tsLast) = lpToken.getReserves();

        // By default priceCumulative is priceCumulativeLast
        priceCumulative = priceCumulativeLast;

        // Extrapolate if time has elapsed since last pair update
        // Note: overflow is not expected for realistic timeframes despite Uniswap V2 unchecked semantics
        uint256 timeElapsed = block.timestamp - tsLast;
        if (timeElapsed > 0 && r0 > 0 && r1 > 0) {
            // direction == 0 ? token1 / token0 : token0 / token1
            uint256 priceUQ = (direction == 0) ? UQ112x112.encode(r1).uqdiv(r0) : UQ112x112.encode(r0).uqdiv(r1);

            // Increase priceCumulative
            priceCumulative += priceUQ * timeElapsed;
        }
    }
}
