// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetProcessorL1.sol";

interface IWormhole {
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    function sendPayloadToEvm(
        // Chain ID in Wormhole format
        uint16 targetChain,
        // Contract Address on target chain we're sending a message to
        address targetAddress,
        // The payload, encoded as bytes
        bytes memory payload,
        // How much value to attach to the delivery transaction
        uint256 receiverValue,
        // The gas limit to set on the delivery transaction
        uint256 gasLimit
    ) external payable returns (
        // Unique, incrementing ID, used to identify a message
        uint64 sequence
    );
}

error AlreadyDelivered(bytes32 deliveryHash);

abstract contract WormholeTargetProcessorL1 is DefaultTargetProcessorL1 {
    uint256 public immutable wormholeTargetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        uint256 _wormholeTargetChainId
    ) DefaultTargetProcessorL1(_olas, _l1Dispenser, _l1MessageRelayer, _l1MessageRelayer, _l2TargetChainId) {
        if (_wormholeTargetChainId == 0) {
            revert();
        }

        if (_wormholeTargetChainId > type(uint16).max) {
            revert();
        }

        wormholeTargetChainId = _wormholeTargetChainId;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes[] memory,
        uint256 transferAmount
    ) internal override {
        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(l1MessageRelayer).quoteEVMDeliveryPrice(uint16(wormholeTargetChainId), 0, GAS_LIMIT);

        // Send the message
        IWormhole(l1MessageRelayer).sendPayloadToEvm{value: cost}(
            uint16(wormholeTargetChainId),
            l2TargetDispenser,
            abi.encode(targets, stakingAmounts),
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