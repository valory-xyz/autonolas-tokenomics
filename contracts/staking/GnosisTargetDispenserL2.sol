// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Contract: AMB Contract Proxy Home
    // Source: https://github.com/omni/tokenbridge-contracts/blob/908a48107919d4ab127f9af07d44d47eac91547e/contracts/upgradeable_contracts/arbitrary_message/MessageDelivery.sol#L22
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    /// @dev Requests message relay to the opposite network
    /// @param target Executor address on the other side.
    /// @param data Calldata passed to the executor on the other side.
    /// @param maxGasLimit Gas limit used on the other network for executing a message.
    /// @return Message Id.
    function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external returns (bytes32);

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#security-considerations-for-receiving-a-call
    function messageSender() external returns (address);
}

contract GnosisTargetDispenserL2 is DefaultTargetDispenserL2 {
    address public immutable l2TokenRelayer;

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId,
        address _l2TokenRelayer
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _owner, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {
        if (_l2TokenRelayer == address(0)) {
            revert ZeroAddress();
        }

        l2TokenRelayer = _l2TokenRelayer;
    }

    function _sendMessage(uint256 amount, bytes memory) internal override {
        // Assemble AMB data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount));

        // Send message to L1
        bytes32 iMsg = IBridge(l2MessageRelayer).requireToPassMessage(l1DepositProcessor, data, GAS_LIMIT);

        emit MessageSent(uint256(iMsg), msg.sender, l1DepositProcessor, amount, 0);
    }

    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
    /// @param data Bytes message sent from the AMB Contract Proxy (Home) contract.
    function receiveMessage(bytes memory data) external {
        // Get L1 processor address
        address processor = IBridge(l2MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, processor, l1SourceChainId, data);
    }

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/BasicOmnibridge.sol#L464
    // Source: https://github.com/omni/omnibridge/blob/master/contracts/interfaces/IERC20Receiver.sol
    function onTokenBridged(address, uint256, bytes calldata data) external {
        // Check for the message to come from the L2 token relayer
        if (msg.sender != l2TokenRelayer) {
            revert TargetRelayerOnly(msg.sender, l2TokenRelayer);
        }

        // Process the data
        _receiveMessage(l2MessageRelayer, l1DepositProcessor, l1SourceChainId, data);
    }
}