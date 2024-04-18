// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultDepositProcessorL1} from "./DefaultDepositProcessorL1.sol";
import {TokenBase, TokenSender} from "wormhole-solidity-sdk/TokenBase.sol";
import "../interfaces/IToken.sol";

error AlreadyDelivered(bytes32 deliveryHash);

contract WormholeDepositProcessorL1 is DefaultDepositProcessorL1, TokenSender {
    uint256 public immutable wormholeTargetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address (WormholeRelayer).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (WormholeRelayer).
    /// @param _l2TargetChainId L2 target chain Id.
    /// @param _wormholeCore L1 Wormhole Core contract address.
    /// @param _wormholeTargetChainId L2 wormhole standard target chain Id.
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

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal override returns (uint256 sequence) {
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
        sequence = sendTokenWithPayloadToEvm(uint16(wormholeTargetChainId), l2TargetDispenser, data, 0,
            gasLimit, olas, transferAmount, uint16(refundChainId), refundAccount);
    }

    /// @dev Processes a message received from L2 via the L1 Wormhole Relayer contract.
    /// @notice The sender must be the L2 target dispenser address.
    /// @param data Bytes data message sent from L2.
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

        // Get L2 dispenser address
        address l2Dispenser = address(uint160(uint256(sourceAddress)));

        _receiveMessage(msg.sender, l2Dispenser, data);
    }
}