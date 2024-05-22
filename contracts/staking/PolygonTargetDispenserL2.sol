// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";
import {FxBaseChildTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";

/// @title PolygonTargetDispenserL2 - Smart contract for processing tokens and data received on Polygon L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract PolygonTargetDispenserL2 is DefaultTargetDispenserL2, FxBaseChildTunnel {
    event FxRootTunnelUpdated(address indexed fxRootTunnel);

    /// @dev PolygonTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (fxChild).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
        FxBaseChildTunnel(_l2MessageRelayer)
    {}

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(uint256 amount, bytes memory) internal override {
        // Assemble AMB data payload
        bytes memory data = abi.encode(amount);

        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L50
        // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
        // Send message to L1
        _sendMessageToRoot(data);

        emit MessagePosted(0, msg.sender, l1DepositProcessor, amount);
    }

    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L63
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
    /// @dev Processes message received from L1 Root Tunnel.
    /// @notice Function needs to be implemented to handle message as per requirement.
    ///      This is called by onStateReceive function.
    ///      Since it is called via a system call, any event will not be emitted during its execution.
    /// @param sender Root message sender.
    /// @param data Bytes message that was sent from L1 Root Tunnel.
    function _processMessageFromRoot(uint256, address sender, bytes memory data) internal override {
        // Process the data
        _receiveMessage(l2MessageRelayer, sender, data);
    }

    /// @dev Set l1DepositProcessor, aka fxRootTunnel.
    /// @param l1Processor L1 deposit processor address.
    function setFxRootTunnel(address l1Processor) external override {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (l1Processor == address(0)) {
            revert ZeroAddress();
        }

        // Set L1 deposit processor address
        fxRootTunnel = l1Processor;

        emit FxRootTunnelUpdated(l1Processor);
    }
}