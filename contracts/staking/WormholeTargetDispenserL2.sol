// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";
import {TokenBase, TokenReceiver} from "wormhole-solidity-sdk/TokenBase.sol";

interface IBridge {
    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L442
    // Doc: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/standard-relayer
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L122
    /// @notice Publishes an instruction for the default delivery provider
    /// to relay a payload to the address `targetAddress` on chain `targetChain`
    /// with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
    ///
    /// Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
    /// `targetAddress` must implement the IWormholeReceiver interface
    ///
    /// This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    ///        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
    /// @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
    /// @param refundAddress The address on `refundChain` to deliver any refund to
    /// @return sequence sequence number of published VAA containing delivery instructions
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) external payable returns (uint64 sequence);
}

/// @title WormholeTargetDispenserL2 - Smart contract for processing tokens and data received via Wormhole on L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeTargetDispenserL2 is DefaultTargetDispenserL2, TokenReceiver {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 64;
    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (Relayer).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 wormhole standard source chain Id.
    /// @param _wormholeCore L2 Wormhole Core contract address.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address (Token Bridge).
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId,
        address _wormholeCore,
        address _l2TokenRelayer
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
        TokenBase(_l2MessageRelayer, _l2TokenRelayer, _wormholeCore)
    {
        // Check for zero addresses
        if (_wormholeCore == address(0) || _l2TokenRelayer == address(0)) {
            revert ZeroAddress();
        }

        // Check for the overflow value
        if (_l1SourceChainId > type(uint16).max) {
            revert Overflow(_l1SourceChainId, type(uint16).max);
        }

        l1SourceChainId = _l1SourceChainId;
    }

    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal override {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Extract refundAccount and gasLimitMessage from bridgePayload
        (address refundAccount, uint256 gasLimitMessage) = abi.decode(bridgePayload, (address, uint256));
        // If refundAccount is zero, default to msg.sender
        if (refundAccount == address(0)) {
            refundAccount = msg.sender;
        }

        // Check the gas limit values for both ends
        if (gasLimitMessage < GAS_LIMIT) {
            gasLimitMessage = GAS_LIMIT;
        }

        if (gasLimitMessage > MAX_GAS_LIMIT) {
            gasLimitMessage = MAX_GAS_LIMIT;
        }

        // Get a quote for the cost of gas for delivery
        (uint256 cost, ) = IBridge(l2MessageRelayer).quoteEVMDeliveryPrice(uint16(l1SourceChainId), 0, gasLimitMessage);

        // Check that provided msg.value is enough to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Send the message to L1
        uint64 sequence = IBridge(l2MessageRelayer).sendPayloadToEvm{value: cost}(uint16(l1SourceChainId),
            l1DepositProcessor, abi.encode(amount), 0, gasLimitMessage, uint16(l1SourceChainId), refundAccount);

        emit MessagePosted(sequence, msg.sender, l1DepositProcessor, amount);
    }
    
    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the deposit processor address.
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

        // Check for the source chain Id
        if (sourceChainId != l1SourceChainId) {
            revert WrongChainId(sourceChainId, l1SourceChainId);
        }

        // Inspired by: https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-token
        // Source code: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/TokenBase.sol#L187
        // Check that only one token is received
        if (receivedTokens.length != 1) {
            revert WrongAmount(receivedTokens.length, 1);
        }

        // Check that the received token is OLAS
        if (receivedTokens[0].tokenAddress != olas) {
            revert WrongTokenAddress(receivedTokens[0].tokenAddress, olas);
        }

        // Get the deposit processor address
        address processor = address(uint160(uint256(sourceProcessor)));

        // Process the data
        _receiveMessage(msg.sender, processor, data);
    }
}