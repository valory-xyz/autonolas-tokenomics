// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";
import "wormhole-solidity-sdk/TokenBase.sol";

error AlreadyDelivered(bytes32 deliveryHash);

interface IBridge {
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

contract WormholeTargetDispenserL2 is DefaultTargetDispenserL2, TokenReceiver {
    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1SourceProcessor,
        uint256 _l1SourceChainId,
        address _l2TokenRelayer,
        address _wormholeCore
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1SourceProcessor, _l1SourceChainId)
        TokenBase(_l2MessageRelayer, _l2TokenRelayer, _wormholeCore)
    {
        if (_l1SourceChainId > type(uint16).max) {
            revert();
        }

        if (_wormholeCore == address(0) || _l2TokenRelayer == address(0)) {
            revert();
        }

        l1SourceChainId = _l1SourceChainId;
    }

    function _sendMessage(uint256 amount, address refundAccount) internal override {
        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IBridge(l2MessageRelayer).quoteEVMDeliveryPrice(uint16(l1SourceChainId), 0, GAS_LIMIT);

        // Send the message
        uint64 sequence = IBridge(l2MessageRelayer).sendPayloadToEvm{value: cost}(
            uint16(l1SourceChainId),
            l1SourceProcessor,
            abi.encode(amount),
            0,
            GAS_LIMIT
        );

        emit MessageSent(sequence, msg.sender, l1SourceProcessor, amount);
    }
    
    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address.
    /// @param data Bytes message sent from L2 Wormhole Relayer contract.
    /// @param receivedTokens Tokens received on L2.
    /// @param sourceProcessor The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChainId The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receivePayloadAndTokens(
        bytes memory data,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceProcessor,
        uint16 sourceChainId,
        bytes32 deliveryHash
    ) internal override {
        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        // Inspired by: https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-token
        // Source code: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/TokenBase.sol#L187
        if (receivedTokens.length != 1) {
            revert(); //"Expected 1 token transfers"
        }

        // Get the source processor address
        address processor = address(uint160(uint256(sourceProcessor)));

        // Process the data
        _receiveMessage(msg.sender, processor, sourceChainId, data);
    }
}