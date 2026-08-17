// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {LiquidityManagerSourceBalancer} from "./LiquidityManagerSourceBalancer.sol";
import {LiquidityManagerTargetSlipstream} from "./LiquidityManagerTargetSlipstream.sol";
import {LiquidityManagerBurnViaBridge} from "./LiquidityManagerBurnViaBridge.sol";

/// @title Liquidity Manager Balancer Slipstream - OLAS Liquidity Manager for Balancer V2 -> Slipstream (Optimism, Base)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Converts protocol-owned Balancer V2 liquidity into a Velodrome/Aerodrome Slipstream concentrated
///      position. OLAS is bridged to L1 for burning. Formerly `LiquidityManagerOptimism`.
contract LiquidityManagerBalancerSlipstream is
    LiquidityManagerSourceBalancer,
    LiquidityManagerTargetSlipstream,
    LiquidityManagerBurnViaBridge
{
    /// @dev LiquidityManagerBalancerSlipstream constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Slipstream position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _balancerVault Balancer vault address.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        address _balancerVault,
        address _bridge2Burner
    )
        LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality)
        LiquidityManagerSourceBalancer(_balancerVault)
        LiquidityManagerBurnViaBridge(_bridge2Burner)
    {}
}
