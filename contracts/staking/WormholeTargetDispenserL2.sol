// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";
import {TokenBase, TokenReceiver} from "wormhole-solidity-sdk/TokenBase.sol";

error AlreadyDelivered(bytes32 deliveryHash);
error OneTokenOnly();
/// @dev Provided token address is incorrect.
/// @param provided Provided token address.
/// @param expected Expected token address.
error WrongTokenAddress(address provided, address expected);

interface IBridge {
    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L442
    // Doc: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/standard-relayer
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L122
    /**
     * @notice Publishes an instruction for the default delivery provider
     * to relay a payload to the address `targetAddress` on chain `targetChain`
     * with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
     *
     * Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
     * `targetAddress` must implement the IWormholeReceiver interface
     *
     * This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
     *
     * @param targetChain in Wormhole Chain ID format
     * @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
     * @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
     * @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
     * @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
     *        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
     * @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
     * @param refundAddress The address on `refundChain` to deliver any refund to
     * @return sequence sequence number of published VAA containing delivery instructions
     */
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

contract WormholeTargetDispenserL2 is DefaultTargetDispenserL2, TokenReceiver {
    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId,
        address _wormholeCore,
        address _l2TokenRelayer
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
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

    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal override {
        // Get a quote for the cost of gas for delivery
        (uint256 cost, ) = IBridge(l2MessageRelayer).quoteEVMDeliveryPrice(uint16(l1SourceChainId), 0, GAS_LIMIT);

        if (cost > msg.value) {
            revert();
        }

        address refundAccount;
        if (bridgePayload.length == 0) {
            refundAccount = msg.sender;
        }
        // TODO: Shall we need to check for the bridgePayload length?
        refundAccount = abi.decode(bridgePayload, (address));
        if (refundAccount == address(0)) {
            refundAccount = msg.sender;
        }

        // Send the message
        uint64 sequence = IBridge(l2MessageRelayer).sendPayloadToEvm{value: cost}(
            uint16(l1SourceChainId),
            l1DepositProcessor,
            abi.encode(amount),
            0,
            GAS_LIMIT,
            uint16(l1SourceChainId),
            refundAccount
        );

        emit MessageSent(sequence, msg.sender, l1DepositProcessor, amount, cost);
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

        // Inspired by: https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-token
        // Source code: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/TokenBase.sol#L187
        if (receivedTokens.length != 1) {
            revert OneTokenOnly();
        }

        if (receivedTokens[0].tokenAddress != olas) {
            revert WrongTokenAddress(receivedTokens[0].tokenAddress, olas);
        }

        // Get the deposit processor address
        address processor = address(uint160(uint256(sourceProcessor)));

        // Process the data
        _receiveMessage(msg.sender, processor, sourceChainId, data);
    }
}