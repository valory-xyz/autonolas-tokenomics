// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {LiquidityManagerSourceUniV2} from "./LiquidityManagerSourceUniV2.sol";
import {LiquidityManagerTargetUniV3} from "./LiquidityManagerTargetUniV3.sol";

interface IOlasBurnable {
    /// @dev Burns tokens.
    /// @param amount Token amount to burn.
    function burn(uint256 amount) external;
}

/// @title Liquidity Manager UniV2 UniV3 - OLAS Liquidity Manager for Uniswap V2 -> Uniswap V3 (e.g. Ethereum mainnet)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Converts protocol-owned Uniswap V2 liquidity into a Uniswap V3 concentrated position. OLAS is burned
///      locally (L1). Formerly `LiquidityManagerETH`.
contract LiquidityManagerUniV2UniV3 is LiquidityManagerSourceUniV2, LiquidityManagerTargetUniV3 {
    /// @dev LiquidityManagerUniV2UniV3 constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _routerV2 Uniswap V2 Router address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        address _routerV2
    )
        LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality)
        LiquidityManagerSourceUniV2(_routerV2)
    {}

    /// @dev Burns OLAS.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal virtual override {
        IOlasBurnable(olas).burn(amount);
    }
}
