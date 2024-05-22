// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L259
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging
    /// @notice Sends a message to some target address on the other chain. Note that if the call
    ///         always reverts, then the message will be unrelayable, and any ETH sent will be
    ///         permanently locked. The same will occur if the target on the other chain is
    ///         considered unsafe (see the _isUnsafeTarget() function).
    ///
    /// @param _target      Target contract or wallet address.
    /// @param _message     Message to trigger the target address with.
    /// @param _minGasLimit Minimum gas limit that the message can be executed with.
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _minGasLimit
    ) external payable;

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L422
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#accessing-msgsender
    /// @notice Retrieves the address of the contract or wallet that initiated the currently
    ///         executing message on the other chain. Will throw an error if there is no message
    ///         currently being executed. Allows the recipient of a call to see who triggered it.
    ///
    /// @return Address of the sender of the currently executing message on the other chain.
    function xDomainMessageSender() external view returns (address);
}

/// @title OptimismTargetDispenserL2 - Smart contract for processing tokens and data received on Optimism L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract OptimismTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 64;

    /// @dev OptimismTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (L2CrossDomainMessengerProxy).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId) {}

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal override {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Extract bridge cost and gas limit from the bridge payload
        (uint256 cost, uint256 gasLimitMessage) = abi.decode(bridgePayload, (uint256, uint256));

        // Check for zero value
        if (cost == 0) {
            revert ZeroValue();
        }

        // Check that provided msg.value is enough to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Check the gas limit values for both ends
        if (gasLimitMessage < GAS_LIMIT) {
            gasLimitMessage = GAS_LIMIT;
        }

        if (gasLimitMessage > MAX_GAS_LIMIT) {
            gasLimitMessage = MAX_GAS_LIMIT;
        }

        // Assemble data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount));

        // Send the message to L1 deposit processor
        // Reference: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l1-to-l2-transactions-1
        IBridge(l2MessageRelayer).sendMessage{value: cost}(l1DepositProcessor, data, uint32(gasLimitMessage));

        emit MessagePosted(0, msg.sender, l1DepositProcessor, amount);
    }

    /// @dev Processes a message received from L1 deposit processor contract.
    /// @param data Bytes message data sent from L1.
    function receiveMessage(bytes memory data) external payable {
        // Check for the target dispenser address
        address l1Processor = IBridge(l2MessageRelayer).xDomainMessageSender();

        // Process the data
        _receiveMessage(msg.sender, l1Processor, data);
    }
}