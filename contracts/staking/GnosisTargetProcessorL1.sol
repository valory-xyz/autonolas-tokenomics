// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetProcessorL1.sol";

interface IOmniBridge {
    function relayTokens(address token, address receiver, uint256 value) external;
}

interface IAMB {
    function requireToPassMessage(address target, bytes data, uint256 maxGasLimit) external;
}

contract GnosisTargetProcessorL1 is DefaultTargetProcessorL1 {
    // processMessageFromForeign selector (Gnosis chain)
    bytes4 public constant PROCESS_MESSAGE_FROM_FOREIGN = bytes4(keccak256(bytes("processMessageFromForeign(bytes)")));

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l2TargetDispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer
    ) DefaultTargetProcessorL1(_olas, _l1Dispenser, _l2TargetDispenser, _l1TokenRelayer, _l1MessageRelayer) {}

    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmount,
        bytes[] memory,
        uint256 transferAmount
    ) internal override {
        // Deposit OLAS
        // Approve tokens for the bridge contract
        IOLAS(olas).approve(l1TokenRelayer, transferAmount);

        // Transfer OLAS to the staking dispenser contract across the bridge
        IOmniBridge(l1TokenRelayer).relayTokens(olas, l2TargetDispenser, transferAmount);

        // Assemble AMB data payload
        bytes memory data = abi.encode(PROCESS_MESSAGE_FROM_FOREIGN, targets, stakingAmounts);

        // Send message to L2
        IAMB(l1MessageRelayer).requireToPassMessage(l2TargetDispenser, data, GAS_LIMIT);
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function sendMessage(address target, uint256 stakingAmount, uint256 transferAmount) external {
        address[] memory targets = new address[](1);
        targets[i] = target;
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[i] = stakingAmount;

        _deposit(targets, stakingAmounts, new bytes[](0), transferAmount);
    }

    // Send a message to the staking dispenser contract to reflect the transferred OLAS amount
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingAmount,
        bytes[] memory payloads,
        uint256 transferAmount
    ) external {
        _deposit(targets, stakingAmounts, new bytes[](0), transferAmount);
    }

    function receiveMessage(address messageSender, uint256 chainId, bytes memory data) external {
        _receiveMessage(messageSender, chainId, data);
    }
}