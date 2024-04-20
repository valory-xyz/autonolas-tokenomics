// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L259
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging
    /**
     * @notice Sends a message to some target address on the other chain. Note that if the call
     *         always reverts, then the message will be unrelayable, and any ETH sent will be
     *         permanently locked. The same will occur if the target on the other chain is
     *         considered unsafe (see the _isUnsafeTarget() function).
     *
     * @param _target      Target contract or wallet address.
     * @param _message     Message to trigger the target address with.
     * @param _minGasLimit Minimum gas limit that the message can be executed with.
     */
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _minGasLimit
    ) external payable;

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L422
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#accessing-msgsender
    /**
     * @notice Retrieves the address of the contract or wallet that initiated the currently
     *         executing message on the other chain. Will throw an error if there is no message
     *         currently being executed. Allows the recipient of a call to see who triggered it.
     *
     * @return Address of the sender of the currently executing message on the other chain.
     */
    function xDomainMessageSender() external view returns (address);
}

contract OptimismTargetDispenserL2 is DefaultTargetDispenserL2 {

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId) {}

    // TODO: where does the unspent gas go?
    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal override {
        // Assemble data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount));

        // Send message to L1
        // TODO Account for 20% more on L2 as well?
        // Reference: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l1-to-l2-transactions-1
        uint256 cost = abi.decode(bridgePayload, (uint256));

        if (cost > msg.value) {
            return();
        }

        IBridge(l2MessageRelayer).sendMessage{value: cost}(l1DepositProcessor, data, uint32(GAS_LIMIT));

        emit MessageSent(0, msg.sender, l1DepositProcessor, amount);
    }

    function receiveMessage(bytes memory data) external payable {
        // Check for the target dispenser address
        address l1Processor = IBridge(l2MessageRelayer).xDomainMessageSender();

        // Process the data
        _receiveMessage(msg.sender, l1Processor, l1SourceChainId, data);
    }
}