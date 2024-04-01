// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";

interface IBridge {
    function messageSender() external;
    function requireToPassMessage(address target, bytes data, uint256 maxGasLimit) external;
}

contract WormholeTargetDispenserL2 is DefaultTargetDispenserL2 {
    // processMessageFromHome selector (Ethereum chain)
    bytes4 public constant PROCESS_MESSAGE_FROM_HOME = bytes4(keccak256(bytes("processMessageFromHome(bytes)")));

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2Relayer,
        address _l1SourceProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2Relayer, _l1SourceProcessor, _l1SourceChainId) {}

    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
    /// @param data Bytes message sent from the AMB Contract Proxy (Home) contract.
    function processMessageFromForeign(bytes memory data) external {
        // Get the processor address
        address processor = IBridge(l2Relayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, processor, l1SourceChainId, data);
    }

    // TODO If the data is transferred together with the token
    function onTokenBridged(address, uint256, bytes calldata data) external {
        // TODO: also separate l2Relayer for token and messages? As l2Relayer now is for messages only
        // Process the data
        _receiveMessage(l2Relayer, l1SourceProcessor, l1SourceChainId, data);
    }

    function _sendMessage(uint256 amount) internal override {
        // Assemble AMB data payload
        bytes memory data = abi.encode(PROCESS_MESSAGE_FROM_HOME, amount);

        // Send message to L2
        IBridge(l1SourceProcessor).requireToPassMessage(l2TargetDispenser, data, GAS_LIMIT);
    }
}