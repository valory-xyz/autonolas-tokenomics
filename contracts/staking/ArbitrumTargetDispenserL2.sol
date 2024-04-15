// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Source (Go) and interface: https://docs.arbitrum.io/build-decentralized-apps/precompiles/reference#arbsys
    // Source for the possible utility contract: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/arbitrum/L2ArbitrumMessenger.sol#L30
    // Docs: https://docs.arbitrum.io/arbos/l2-to-l1-messaging
    /**
     * @notice Send a transaction to L1
     * @dev it is not possible to execute on the L1 any L2-to-L1 transaction which contains data
     * to a contract address without any code (as enforced by the Bridge contract).
     * @param destination recipient address on L1
     * @param data (optional) calldata for L1 contract call
     * @return a unique identifier for this L2-to-L1 transaction.
     */
    function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256);
}

contract ArbitrumTargetDispenserL2 is DefaultTargetDispenserL2 {
    // receiveMessage selector (Ethereum chain)
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1SourceProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1SourceProcessor, _l1SourceChainId) {}

    // TODO: where does the unspent gas go?
    function _sendMessage(uint256 amount, address) internal override {
        // TODO Shall we also pack address(this) and chain Id in order to verify on L1 upon receiving the message?
        // Assemble AMB data payload
        bytes memory data = abi.encode(RECEIVE_MESSAGE, amount);

        // TODO Dow we need to supply any value?
        // Send message to L1
        uint256 sequence = IBridge(l2MessageRelayer).sendTxToL1(l1SourceProcessor, data);

        emit MessageSent(sequence, msg.sender, l1SourceProcessor, amount);
    }

    /// @dev Processes a message received from the L1 source processor contract.
    /// @param data Bytes message sent from L1.
    function receiveMessage(bytes memory data) external {
        // TODO Is l2Dispenser somehow obtained or it's the msg.sender right away?
        // Get the L1 source processor address
        address l1Processor = l1SourceProcessor;

        // Process the data
        _receiveMessage(msg.sender, l1Processor, l1SourceChainId, data);
    }
}