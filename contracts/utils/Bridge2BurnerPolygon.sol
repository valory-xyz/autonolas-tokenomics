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

/// @title Bridge2BurnerPolygon - Smart contract for collecting OLAS on Polygon and routing it to the PolygonBurnForwarder.
/// @dev Polygon's PoS ERC20 child token only exposes `withdraw(uint256)` — no recipient parameter — so an L2 bridge-burn
///      would release the L1 tokens to the L1-mirror of `msg.sender`, i.e. this contract's address on L1, which has no
///      deployed code and would render the OLAS unrecoverable. Compare with the Optimism / Arbitrum / Gnosis variants
///      whose bridge primitives accept an explicit recipient (`withdrawTo` / `outboundTransfer` / `relayTokens`) and
///      route directly to OLAS_BURNER on L1.
///
///      On Polygon the OLAS is therefore forwarded to the PolygonBurnForwarder, which is deployed by CREATE2 at the same
///      address on Polygon and on Ethereum: it burns the OLAS on Polygon, and the PoS exit releases it to its own address
///      on Ethereum, from where it reaches OLAS_BURNER. The forwarder address is supplied at deployment as the second
///      constructor argument (the base class's `l2TokenRelayer` immutable storage is reused to hold it; on this chain
///      there is no separate L2 token relayer to talk to). This reuse keeps the base constructor signature symmetric
///      across chains while letting the deployment script record the chain-specific destination on a per-chain basis.
contract Bridge2BurnerPolygon is Bridge2Burner {
    /// @dev Bridge2BurnerPolygon constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _polygonBurnForwarder PolygonBurnForwarder address, the same on Polygon and on Ethereum.
    ///                              Stored in the inherited `l2TokenRelayer` immutable; no separate field is introduced.
    constructor(address _olas, address _polygonBurnForwarder) Bridge2Burner(_olas, _polygonBurnForwarder) {}

    /// @dev Forwards OLAS to the PolygonBurnForwarder.
    function relayToL1Burner() external virtual override {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS amount to bridge
        uint256 olasAmount = _getBalance();

        // Forward OLAS to the PolygonBurnForwarder (held in the inherited `l2TokenRelayer` immutable on this chain)
        bool success = IToken(olas).transfer(l2TokenRelayer, olasAmount);
        if (!success) {
            revert TransferFailed(olas, l2TokenRelayer, olasAmount);
        }

        _locked = 1;
    }
}
