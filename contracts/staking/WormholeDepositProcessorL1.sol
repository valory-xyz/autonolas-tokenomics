// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultDepositProcessorL1} from "./DefaultDepositProcessorL1.sol";
import {TokenBase, TokenSender} from "wormhole-solidity-sdk/TokenBase.sol";

interface IBridge {
    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L442
    // Doc: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/standard-relayer
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);
}

/// @title WormholeDepositProcessorL1 - Smart contract for sending tokens and data via Wormhole bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeDepositProcessorL1 is DefaultDepositProcessorL1, TokenSender {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 64;
    // Wormhole classification chain Id corresponding to L2 chain Id
    uint256 public immutable wormholeTargetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address (TokenBridge).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (Relayer).
    /// @param _l2TargetChainId L2 target chain Id.
    /// @param _wormholeCore L1 Wormhole Core contract address.
    /// @param _wormholeTargetChainId L2 wormhole format target chain Id.
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
        // Check for zero address
        if (_wormholeCore == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_wormholeTargetChainId == 0) {
            revert ZeroValue();
        }

        // Check for the overflow value
        if (_wormholeTargetChainId > type(uint16).max) {
            revert Overflow(_wormholeTargetChainId, type(uint16).max);
        }

        wormholeTargetChainId = _wormholeTargetChainId;
    }

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory bridgePayload,
        uint256 transferAmount,
        bytes32 batchHash
    ) internal override returns (uint256 sequence, uint256 leftovers) {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Decode required parameters
        (address refundAccount, uint256 gasLimitMessage) = abi.decode(bridgePayload, (address, uint256));

        // Check for refund account address
        if (refundAccount == address(0)) {
            revert ZeroAddress();
        }

        // Check for the message gas limit
        if (gasLimitMessage < MESSAGE_GAS_LIMIT) {
            gasLimitMessage = MESSAGE_GAS_LIMIT;
        }

        // Encode target addresses and amounts
        bytes memory data = abi.encode(targets, stakingIncentives, batchHash);

        // Get the message cost in order to adjust leftovers
        (uint256 cost, ) = IBridge(l1MessageRelayer).quoteEVMDeliveryPrice(uint16(wormholeTargetChainId), 0,
            gasLimitMessage);

        // Check fot msg.value to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/TokenBase.sol#L125
        // Additional token source: https://github.com/wormhole-foundation/wormhole/blob/b18a7e61eb9316d620c888e01319152b9c8790f4/ethereum/contracts/bridge/Bridge.sol#L203
        // Doc: https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-token
        // The token approval is done inside the function
        // Send tokens and / or message to L2
        sequence = sendTokenWithPayloadToEvm(uint16(wormholeTargetChainId), l2TargetDispenser, data, 0,
            gasLimitMessage, olas, transferAmount, uint16(wormholeTargetChainId), refundAccount);

        // Return value leftovers
        leftovers = msg.value - cost;
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
        // Check for the source chain Id
        if (sourceChain != wormholeTargetChainId) {
            revert WrongChainId(sourceChain, wormholeTargetChainId);
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        // Get L2 target dispenser address
        address l2Dispenser = address(uint160(uint256(sourceAddress)));

        _receiveMessage(msg.sender, l2Dispenser, data);
    }

    /// @dev Sets L2 target dispenser address.
    /// @param l2Dispenser L2 target dispenser address.
    function setL2TargetDispenser(address l2Dispenser) external override {
        setRegisteredSender(uint16(wormholeTargetChainId), bytes32(uint256(uint160(l2Dispenser))));
        _setL2TargetDispenser(l2Dispenser);
    }

    /// @inheritdoc DefaultDepositProcessorL1
    function getBridgingDecimals() external pure override returns (uint256) {
        return 8;
    }
}