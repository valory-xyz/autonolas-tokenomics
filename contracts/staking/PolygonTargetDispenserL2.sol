// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";
import {FxBaseChildTunnel} from "fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";

contract PolygonTargetDispenserL2 is DefaultTargetDispenserL2, FxBaseChildTunnel {
    // _l2MessageRelayer is fxChild

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
        FxBaseChildTunnel(_l2MessageRelayer)
    {}

    // TODO: where does the unspent gas go?
    function _sendMessage(uint256 amount, address) internal override {
        // Assemble AMB data payload
        bytes memory data = abi.encode(amount);

        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L50
        // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
        // Send message to L1
        _sendMessageToRoot(data);

        emit MessageSent(0, msg.sender, l1DepositProcessor, amount);
    }

    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L63
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
    /**
     * @notice Process message received from Root Tunnel
     * @dev function needs to be implemented to handle message as per requirement
     * This is called by onStateReceive function.
     * Since it is called via a system call, any event will not be emitted during its execution.
     * @param sender root message sender
     * @param data bytes message that was sent from Root Tunnel
     */
    function _processMessageFromRoot(uint256, address sender, bytes memory data) internal override {
        // TODO: Check if stateId is needed (first unused parameter)

        // Process the data
        _receiveMessage(l2MessageRelayer, sender, l1SourceChainId, data);
    }
}