// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore, ZeroAddress} from "./LiquidityManagerCore.sol";
import {IToken} from "../interfaces/IToken.sol";

/// @title Liquidity Manager Burn Via Bridge - L2 OLAS burn mixin
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev On L2s OLAS cannot be burned locally, so it is transferred to a Bridge2Burner that bridges it to L1
///      for burning. Used by every L2 liquidity manager regardless of its source/target DEX.
abstract contract LiquidityManagerBurnViaBridge is LiquidityManagerCore {
    // Bridge to Burner address
    address public immutable bridge2Burner;

    /// @dev LiquidityManagerBurnViaBridge constructor.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(address _bridge2Burner) {
        // Check for zero address
        if (_bridge2Burner == address(0)) {
            revert ZeroAddress();
        }

        bridge2Burner = _bridge2Burner;
    }

    /// @dev Transfer OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal virtual override {
        IToken(olas).transfer(bridge2Burner, amount);
    }
}
