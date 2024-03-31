// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";

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

contract WormholeTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2Relayer,
        address _l1SourceProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2Relayer, _l1SourceProcessor, _l1SourceChainId) {}

    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address.
    /// @param data Bytes message sent from L2 Wormhole Relayer contract.
    /// @param sourceProcessor The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChainId The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceProcessor,
        uint16 sourceChainId,
        bytes32 deliveryHash
    ) external {
        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        // Get the source processor address
        address processor = address(uint160(uint256(sourceProcessor)));

        // Process the data
        _receiveMessage(msg.sender, processor, uint256(sourceChainId), data);
    }

    // TODO: implement wormhole function that receives ERC20 with payload as well?
    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceProcessor,
        uint16 sourceChainId,
        bytes32 deliveryHash
    ) internal virtual {}
}