// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {LiquidityManagerSourceBalancer} from "./LiquidityManagerSourceBalancer.sol";
import {LiquidityManagerTargetUniV3} from "./LiquidityManagerTargetUniV3.sol";
import {LiquidityManagerBurnViaBridge} from "./LiquidityManagerBurnViaBridge.sol";

/// @title Liquidity Manager Balancer UniV3 - OLAS Liquidity Manager for Balancer V2 -> Uniswap V3 (Polygon, Arbitrum, Base)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Converts protocol-owned Balancer V2 liquidity into a canonical Uniswap V3 concentrated position, for L2s
///      that run Balancer as the source DEX and Uniswap V3 as the target. Pure composition of the existing
///      Balancer-source, UniV3-target and L2-burn mixins — it declares no logic of its own.
contract LiquidityManagerBalancerUniV3 is
    LiquidityManagerSourceBalancer,
    LiquidityManagerTargetUniV3,
    LiquidityManagerBurnViaBridge
{
    /// @dev LiquidityManagerBalancerUniV3 constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
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
