// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultTargetDispenserL2} from "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Source (Go) and interface: https://docs.arbitrum.io/build-decentralized-apps/precompiles/reference#arbsys
    // Source for the possible utility contract: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/arbitrum/L2ArbitrumMessenger.sol#L30
    // Docs: https://docs.arbitrum.io/arbos/l2-to-l1-messaging
    /// @notice Send a transaction to L1
    /// @dev it is not possible to execute on the L1 any L2-to-L1 transaction which contains data
    /// to a contract address without any code (as enforced by the Bridge contract).
    /// @param destination recipient address on L1
    /// @param data (optional) calldata for L1 contract call
    /// @return a unique identifier for this L2-to-L1 transaction.
    function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256);
}

contract ArbitrumTargetDispenserL2 is DefaultTargetDispenserL2 {
    address public immutable l1AliasedDepositProcessor;

    /// @dev ArbitrumTargetDispenserL2 constructor.
    /// @notice _l1AliasedDepositProcessor must be correctly aliased from the address on L1.
    ///         Reference: https://docs.arbitrum.io/arbos/l1-to-l2-messaging#address-aliasing
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (ArbSys).
    /// @param _l1DepositProcessor L1 deposit processor address (NOT aliased).
    /// @param _l1SourceChainId L1 source chain Id.
    /// @param _l1AliasedDepositProcessor Aliased deposit processor address.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId,
        address _l1AliasedDepositProcessor
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {
        // Check for zero address
        if (_l1AliasedDepositProcessor == address(0)) {
            revert ZeroAddress();
        }
        l1AliasedDepositProcessor = _l1AliasedDepositProcessor;
    }

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(uint256 amount, bytes memory) internal override {
        // Assemble data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount));

        // Send message to L1
        uint256 sequence = IBridge(l2MessageRelayer).sendTxToL1(l1DepositProcessor, data);

        emit MessagePosted(sequence, msg.sender, l1DepositProcessor, amount);
    }

    /// @dev Processes a message received from L1 deposit processor contract.
    /// @notice msg.sender is an aliased L1 l1DepositProcessor address.
    /// @param data Bytes message data sent from L1.
    function receiveMessage(bytes memory data) external payable {
        // Check that msg.sender is the aliased L1 deposit processor
        if (msg.sender != l1AliasedDepositProcessor) {
            revert WrongMessageSender(msg.sender, l1AliasedDepositProcessor);
        }

        // Process the message data
        _receiveMessage(l2MessageRelayer, l1DepositProcessor, data);
    }
}