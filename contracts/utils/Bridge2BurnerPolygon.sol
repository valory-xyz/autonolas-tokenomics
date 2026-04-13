// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Bridge2Burner} from "./Bridge2Burner.sol";

// Bridge interface
interface IBridge {
    // Source: https://github.com/maticnetwork/pos-portal/blob/master/contracts/child/ChildERC20.sol
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/ethereum-polygon/erc20/
    /// @notice Called when user wants to withdraw tokens back to root chain.
    /// @dev Should burn user's tokens. This transaction will be verified when exiting on root chain.
    /// @param amount Amount of tokens to withdraw.
    function withdraw(uint256 amount) external;
}

/// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title Bridge2BurnerPolygon - Smart contract for collecting OLAS on Polygon chain and relaying them back to L1 OLAS Burner contract.
/// @dev After calling relayToL1Burner(), the exit must be finalized on L1 via RootChainManager.exit() with the burn proof.
///      The withdrawn OLAS will be released to this contract's address on L1.
contract Bridge2BurnerPolygon is Bridge2Burner {
    /// @dev Bridge2BurnerPolygon constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address (OLAS child token on Polygon).
    constructor(address _olas, address _l2TokenRelayer) Bridge2Burner(_olas, _l2TokenRelayer) {}

    /// @dev Relays OLAS to L1 Burner contract.
    function relayToL1Burner() external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS amount to bridge
        uint256 olasAmount = _getBalance();

        // Withdraw OLAS to L1 via Polygon PoS bridge
        // Source: https://docs.polygon.technology/pos/how-to/bridging/ethereum-polygon/erc20/#withdraw-tokens
        // This burns tokens on L2; on L1, exit() via RootChainManager releases tokens to this contract's address
        IBridge(l2TokenRelayer).withdraw(olasAmount);

        _locked = 1;
    }
}
