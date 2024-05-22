// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

/// @title GnosisTargetDispenserL2 - Smart contract for processing tokens and data received on Gnosis L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract GnosisTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 32;
    // L2 token relayer address
    address public immutable l2TokenRelayer;

    /// @dev GnosisTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (AMBHomeProxy).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    /// @param _l2TokenRelayer L2 token relayer address (HomeOmniBridgeProxy).
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId,
        address _l2TokenRelayer
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {
        // Check for zero address
        if (_l2TokenRelayer == address(0)) {
            revert ZeroAddress();
        }

        l2TokenRelayer = _l2TokenRelayer;
    }

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal override {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Get the gas limit from the bridge payload
        uint256 gasLimitMessage = abi.decode(bridgePayload, (uint256));

        // Check the gas limit values for both ends
        if (gasLimitMessage < GAS_LIMIT) {
            gasLimitMessage = GAS_LIMIT;
        }

        if (gasLimitMessage > MAX_GAS_LIMIT) {
            gasLimitMessage = MAX_GAS_LIMIT;
        }

        // Assemble AMB data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount));

        // Send message to L1
        bytes32 iMsg = IBridge(l2MessageRelayer).requireToPassMessage(l1DepositProcessor, data, gasLimitMessage);

        emit MessagePosted(uint256(iMsg), msg.sender, l1DepositProcessor, amount);
    }

    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
    /// @param data Bytes message data sent from the AMB Contract Proxy (Home) contract.
    function receiveMessage(bytes memory data) external {
        // Get L1 deposit processor address
        address processor = IBridge(l2MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, processor, data);
    }

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/BasicOmnibridge.sol#L464
    // Source: https://github.com/omni/omnibridge/blob/master/contracts/interfaces/IERC20Receiver.sol
    /// @dev Processes the data received together with the token transfer from L1.
    /// @param data Bytes message data sent from L1.
    function onTokenBridged(address, uint256, bytes calldata data) external {
        // Check for the message to come from the L2 token relayer
        if (msg.sender != l2TokenRelayer) {
            revert TargetRelayerOnly(msg.sender, l2TokenRelayer);
        }

        // Process the data
        _receiveMessage(l2MessageRelayer, l1DepositProcessor, data);
    }
}