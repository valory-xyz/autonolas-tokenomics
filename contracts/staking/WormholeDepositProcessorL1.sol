// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultDepositProcessorL1} from "./DefaultDepositProcessorL1.sol";
import {TokenBase, TokenSender} from "wormhole-solidity-sdk/TokenBase.sol";
import "../interfaces/IToken.sol";

error TargetRelayerOnly(address messageSender, address l1MessageRelayer);
error WrongMessageSender(address l2Dispenser, address l2TargetDispenser);
error AlreadyDelivered(bytes32 deliveryHash);

contract WormholeDepositProcessorL1 is DefaultDepositProcessorL1, TokenSender {
    uint256 public immutable wormholeTargetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _wormholeCore,
        uint256 _wormholeTargetChainId
    )
        DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
        TokenBase(_l1MessageRelayer, _l1TokenRelayer, _wormholeCore)
    {
        if (_wormholeCore == address(0)) {
            revert();
        }
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
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal override {
        // TODO Do we need to check for the refund info validity or the bridge is going to revert this?
        (address refundAccount, uint256 refundChainId, uint256 gasLimit) = abi.decode(bridgePayload,
            (address, uint256, uint256));

        // Approve tokens for the token bridge contract
        IToken(olas).approve(address(tokenBridge), transferAmount);

        // Encode target addresses and amounts
        bytes memory data = abi.encode(targets, stakingAmounts);

        // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/TokenBase.sol#L125
        // Additional token source: https://github.com/wormhole-foundation/wormhole/blob/b18a7e61eb9316d620c888e01319152b9c8790f4/ethereum/contracts/bridge/Bridge.sol#L203
        // Doc: https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-token
        uint64 sequence = sendTokenWithPayloadToEvm(uint16(wormholeTargetChainId), l2TargetDispenser, data, 0,
            gasLimit, olas, transferAmount, uint16(refundChainId), refundAccount);

        emit MessageSent(sequence, targets, stakingAmounts, transferAmount);
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
        // Check L1 Relayer address
        if (msg.sender != l1MessageRelayer) {
            revert TargetRelayerOnly(msg.sender, l1MessageRelayer);
        }

        // Get the L2 target dispenser address
        address l2Dispenser = address(uint160(uint256(sourceAddress)));
        if (l2Dispenser != l2TargetDispenser) {
            revert WrongMessageSender(l2Dispenser, l2TargetDispenser);
        }

        if (sourceChain != wormholeTargetChainId) {
            revert();
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        emit MessageReceived(l2TargetDispenser, l2TargetChainId, data);

        _receiveMessage(data);
    }
}