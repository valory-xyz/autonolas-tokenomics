// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetProcessorL1.sol";
import "wormhole-solidity-sdk/TokenBase.sol";

error AlreadyDelivered(bytes32 deliveryHash);

contract WormholeTargetProcessorL1 is DefaultTargetProcessorL1, TokenSender {
    address public immutable refundAddress;
    uint256 public immutable wormholeTargetChainId;
    uint256 public immutable refundChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _wormholeCore,
        address _refundAddress,
        uint256 _wormholeTargetChainId,
        uint256 _refundChainId
    )
        DefaultTargetProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
        TokenBase(_l1MessageRelayer, _l1TokenRelayer, _wormholeCore)
    {
        if (_wormholeCore == address(0) || refundAddress == address(0)) {
            revert();
        }
        if (_wormholeTargetChainId == 0 || _refundChainId == 0) {
            revert();
        }

        if (_wormholeTargetChainId > type(uint16).max || _refundChainId > type(uint16).max) {
            revert();
        }

        refundAddress = _refundAddress;
        wormholeTargetChainId = _wormholeTargetChainId;
        refundChainId = _refundChainId;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes[] memory,
        uint256 transferAmount
    ) internal override {
        //
        bytes memory data = abi.encode(targets, stakingAmounts);

        uint64 sequence = sendTokenWithPayloadToEvm(uint16(wormholeTargetChainId), l2TargetDispenser, data, 0,
            GAS_LIMIT, olas, transferAmount, uint16(refundChainId), refundAddress);

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