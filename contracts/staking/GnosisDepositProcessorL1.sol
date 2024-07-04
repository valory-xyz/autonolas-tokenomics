// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultDepositProcessorL1, IToken} from "./DefaultDepositProcessorL1.sol";

interface IBridge {
    // Contract: AMB Contract Proxy Foreign
    // Source: https://github.com/omni/tokenbridge-contracts/blob/908a48107919d4ab127f9af07d44d47eac91547e/contracts/upgradeable_contracts/arbitrary_message/MessageDelivery.sol#L22
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    /// @dev Requests message relay to the opposite network
    /// @param target Executor address on the other side.
    /// @param data Calldata passed to the executor on the other side.
    /// @param maxGasLimit Gas limit used on the other network for executing a message.
    /// @return Message Id.
    function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external returns (bytes32);

    // Contract: Omnibridge Multi-Token Mediator Proxy
    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/components/common/TokensRelayer.sol#L54
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
    function relayTokens(address token, address receiver, uint256 amount) external;

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#security-considerations-for-receiving-a-call
    function messageSender() external returns (address);
}

/// @title GnosisDepositProcessorL1 - Smart contract for sending tokens and data via Gnosis bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract GnosisDepositProcessorL1 is DefaultDepositProcessorL1 {

    /// @dev GnosisDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address (OmniBridge).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (AMB Proxy Foreign).
    /// @param _l2TargetChainId L2 target chain Id.
    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId
    ) DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId) {}

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory,
        uint256 transferAmount
    ) internal override returns (uint256 sequence, uint256 leftovers) {
        // Transfer OLAS tokens
        if (transferAmount > 0) {
            // Approve tokens for the bridge contract
            IToken(olas).approve(l1TokenRelayer, transferAmount);

            // Transfer tokens
            IBridge(l1TokenRelayer).relayTokens(olas, l2TargetDispenser, transferAmount);
        }

        // Assemble AMB data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives));

        // Send message to L2
        // In the current configuration, maxGasPerTx is set to 4000000 on Ethereum and 2000000 on Gnosis Chain.
        // Source: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#how-to-check-if-amb-is-down-not-relaying-message
        bytes32 iMsg = IBridge(l1MessageRelayer).requireToPassMessage(l2TargetDispenser, data, MESSAGE_GAS_LIMIT);

        sequence = uint256(iMsg);

        // Return msg.value, if provided by mistake
        leftovers = msg.value;
    }

    /// @dev Process message received from L2.
    /// @param data Bytes message data sent from L2.
    function receiveMessage(bytes memory data) external {
        // Get L2 dispenser address
        address l2Dispenser = IBridge(l1MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, l2Dispenser, data);
    }
}