// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";

interface IBridge {
//    function messageSender() external returns (address);
    function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external;
}

contract GnosisTargetDispenserL2 is DefaultTargetDispenserL2 {
    // processMessageFromHome selector (Ethereum chain)
    bytes4 public constant PROCESS_MESSAGE_FROM_HOME = bytes4(keccak256(bytes("processMessageFromHome(bytes)")));

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
        // Assemble AMB data payload
        bytes memory data = abi.encode(PROCESS_MESSAGE_FROM_HOME, amount);

        // Send message to L1
        IBridge(l2MessageRelayer).requireToPassMessage(l1SourceProcessor, data, GAS_LIMIT);

        emit MessageSent(0, msg.sender, l1SourceProcessor, amount);
    }

//    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
//    /// @param data Bytes message sent from the AMB Contract Proxy (Home) contract.
//    function processMessageFromForeign(bytes memory data) external {
//        // Get the processor address
//        address processor = IBridge(l2MessageRelayer).messageSender();
//
//        // Process the data
//        _receiveMessage(msg.sender, processor, l1SourceChainId, data);
//    }

    // TODO If the data is transferred together with the token
    function onTokenBridged(address, uint256, bytes calldata data) external {
        // TODO: also separate l2MessageRelayer for token and messages? As l2MessageRelayer now is for messages only
        // Process the data
        _receiveMessage(l2MessageRelayer, l1SourceProcessor, l1SourceChainId, data);
    }
}