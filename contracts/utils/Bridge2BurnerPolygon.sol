// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Bridge2Burner} from "./Bridge2Burner.sol";

// ERC20 token interface
interface IToken {
    /// @dev Transfers `amount` tokens from the caller's account to `to`.
    /// @param to Recipient address.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Reentrancy guard.
error ReentrancyGuard();

/// @dev Token transfer failed.
/// @param token Token address.
/// @param to Recipient.
/// @param amount Amount.
error TransferFailed(address token, address to, uint256 amount);

/// @title Bridge2BurnerPolygon - Smart contract for collecting OLAS on Polygon and routing it to the L1-governance
///        bridge mediator on L2.
/// @dev Polygon's PoS ERC20 child token only exposes `withdraw(uint256)` — no recipient parameter — so an L2 bridge-burn
///      would release the L1 tokens to the L1-mirror of `msg.sender`, i.e. this contract's address on L1, which has no
///      deployed code and would render the OLAS unrecoverable. Compare with the Optimism / Arbitrum / Gnosis variants
///      whose bridge primitives accept an explicit recipient (`withdrawTo` / `outboundTransfer` / `relayTokens`) and
///      route directly to OLAS_BURNER on L1.
///
///      The chosen workaround on Polygon: forward OLAS to the bridge mediator on L2 — the contract that L1 governance
///      reaches over fx-portal — and let governance decide the final disposition (keep, transfer, or trigger a
///      PoS-bridge burn from the mediator, whose L1-mirror at the same address is recoverable). The bridge mediator
///      address is supplied at deployment as the second constructor argument (the base class's `l2TokenRelayer`
///      immutable storage is reused to hold it; on this chain there is no separate L2 token relayer to talk to).
///      This reuse keeps the base constructor signature symmetric across chains while letting the deployment script
///      record the chain-specific destination on a per-chain basis.
contract Bridge2BurnerPolygon is Bridge2Burner {
    /// @dev Bridge2BurnerPolygon constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _bridgeMediator Polygon L2 bridge mediator address — the contract L1 governance reaches over fx-portal.
    ///                        Stored in the inherited `l2TokenRelayer` immutable; no separate field is introduced.
    constructor(address _olas, address _bridgeMediator) Bridge2Burner(_olas, _bridgeMediator) {}

    /// @dev Forwards OLAS to the Polygon bridge mediator (L2 governance custody).
    function relayToL1Burner() external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS amount to bridge
        uint256 olasAmount = _getBalance();

        // Forward OLAS to the bridge mediator (held in the inherited `l2TokenRelayer` immutable on this chain)
        bool success = IToken(olas).transfer(l2TokenRelayer, olasAmount);
        if (!success) {
            revert TransferFailed(olas, l2TokenRelayer, olasAmount);
        }

        _locked = 1;
    }
}
