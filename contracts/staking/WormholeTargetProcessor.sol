// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetProcessor.sol";

interface IWormhole {
    function quoteEVMDeliveryPrice() external;
    function sendPayloadToEvm() external payable;
}

abstract contract WormholeTargetProcessor is DefaultTargetProcessor {
    uint256 public immutable wormholeTargetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l2TargetDispenser,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        uint256 _wormholeTargetChainId
    ) DefaultTargetProcessor(_olas, _l1Dispenser, _l2TargetDispenser, _l1MessageRelayer, _l1MessageRelayer) {
        if (_wormholeTargetChainId == 0) {
            revert();
        }

        wormholeTargetChainId = _wormholeTargetChainId;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory amounts
    ) internal override payable {
        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(l1MessageRelayer).quoteEVMDeliveryPrice(wormholeTargetChainId, 0, GAS_LIMIT);

        // Send the message
        IWormhole(l1MessageRelayer).sendPayloadToEvm{value: cost}(
            wormholeTargetChainId,
            l2TargetDispenser,
            abi.encode(targets, amounts),
            0,
            GAS_LIMIT
        );
    }

    /// @dev Processes a message received from L1 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address.
    /// @param data Bytes message sent from L1 Wormhole Relayer contract.
    /// @param sourceAddress The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChain The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external {
        if (sourceChain != wormholeTargetChainId) {
            revert();
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        address messageSender = address(uint160(uint256(sourceAddress)));
        _receiveMessage(msg.sender, messageSender, l2TargetChainId, data);
    }
}