// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {LiquidityManagerSourceUniV2} from "./LiquidityManagerSourceUniV2.sol";
import {LiquidityManagerTargetUniV3} from "./LiquidityManagerTargetUniV3.sol";
import {LiquidityManagerBurnViaBridge} from "./LiquidityManagerBurnViaBridge.sol";

/// @title Liquidity Manager UniV2 UniV3 Bridge - OLAS Liquidity Manager for Uniswap V2 -> Uniswap V3 on L2s
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Converts protocol-owned Uniswap-V2-style liquidity (e.g. Ubeswap on Celo) into a canonical Uniswap V3
///      concentrated position on an L2, bridging OLAS to L1 for burning. It is the L2-burn sibling of
///      `LiquidityManagerUniV2UniV3` (which burns locally on L1): same UniV2 source + UniV3 target, but the
///      `BurnViaBridge` mixin instead of the direct L1 `OLAS.burn`. Pure composition of the existing
///      UniV2-source, UniV3-target and L2-burn mixins — it declares no logic of its own.
contract LiquidityManagerUniV2UniV3Bridge is
    LiquidityManagerSourceUniV2,
    LiquidityManagerTargetUniV3,
    LiquidityManagerBurnViaBridge
{
    /// @dev LiquidityManagerUniV2UniV3Bridge constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _routerV2 Uniswap V2 (e.g. Ubeswap) Router address.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        address _routerV2,
        address _bridge2Burner
    )
        LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality)
        LiquidityManagerSourceUniV2(_routerV2)
        LiquidityManagerBurnViaBridge(_bridge2Burner)
    {}
}
