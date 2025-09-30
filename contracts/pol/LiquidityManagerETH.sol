// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";

// OLAS interface
interface IOlas {
    /// @dev Burns OLAS tokens.
    /// @param amount OLAS token amount to burn.
    /// @param amount OLAS token amount to burn.
    function burn(uint256 amount) external;
}

/// @title Liquidity Manager ETH - Smart contract for OLAS core Liquidity Manager functionality on ETH mainnet
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerETH is LiquidityManagerCore {
    /// @dev LiquidityManagerETH constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _routerV2 Uniswap V2 Router address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _maxSlippage Max slippage for operations.
    constructor(
        address _olas,
        address _treasury,
        address _oracleV2,
        address _routerV2,
        address _positionManagerV3,
        uint16 _observationCardinality,
        uint16 _maxSlippage
    ) LiquidityManagerCore(_olas, _treasury, _oracleV2, _routerV2, _positionManagerV3, _observationCardinality, _maxSlippage)
    {}

    /// @dev Burns OLAS.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal override {
        IOlas(olas).burn(amount);
    }
}
