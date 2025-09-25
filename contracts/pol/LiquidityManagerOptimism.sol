// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";

/// @dev Provided zero address.
error ZeroAddress();

interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title Liquidity Manager Optimism - Smart contract for OLAS core Liquidity Manager functionality on Optimism stack chains
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerOptimism is LiquidityManagerCore {
    // Bridge to Burner address
    address public immutable bridge2Burner;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _routerV2 Uniswap V2 Router address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _maxSlippage Max slippage for operations.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(
        address _olas,
        address _treasury,
        address _oracleV2,
        address _routerV2,
        address _positionManagerV3,
        uint16 _maxSlippage,
        address _bridge2Burner
    ) LiquidityManagerCore(_olas, _treasury, _oracleV2, _routerV2, _positionManagerV3, _maxSlippage)
    {
        // Check for zero address
        if (_bridge2Burner == address(0)) {
            revert ZeroAddress();
        }

        bridge2Burner = _bridge2Burner;
    }

    /// @dev Transfer OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal override {
        IToken(olas).transfer(bridge2Burner, amount);
    }
}
