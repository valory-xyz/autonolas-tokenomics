// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDispenser {
    function syncWithheldAmount(uint256 chainId, uint256 amount) external;
}

abstract contract DefaultTargetProcessorL1 {
    event MessageSent(uint256 indexed sequence, address[] targets, uint256[] stakingAmounts, uint256 transferAmount);
    event MessageReceived(address indexed messageSender, uint256 indexed chainId, bytes data);

    address public immutable olas;
    address public immutable l1Dispenser;
    address public immutable l1TokenRelayer;
    address public immutable l1MessageRelayer;
    uint256 public immutable l2TargetChainId;
    address public l2TargetDispenser;
    address public owner;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId
    ) {
        if (_l1Dispenser == address(0) || _l1TokenRelayer == address(0) || _l1MessageRelayer == address(0)) {
            revert();
        }

        if (_l2TargetChainId == 0) {
            revert();
        }

        olas = _olas;
        l1Dispenser = _l1Dispenser;
        l1TokenRelayer = _l1TokenRelayer;
        l1MessageRelayer = _l1MessageRelayer;
        l2TargetChainId = _l2TargetChainId;
        owner = msg.sender;
    }

    // TODO Check where payable is needed
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal virtual;

    function _receiveMessage(bytes memory data) internal virtual {
        // Extract the amount of OLAS to sync
        (uint256 amount) = abi.decode(data, (uint256));

        IDispenser(l1Dispenser).syncWithheldAmount(l2TargetChainId, amount);
    }

    function sendMessage(
        address target,
        uint256 stakingAmount,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external virtual payable {
        if (msg.sender != l1Dispenser) {
            revert();
        }

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[0] = stakingAmount;

        _sendMessage(targets, stakingAmounts, bridgePayload, transferAmount);
    }

    // Send a message to the staking dispenser contract to reflect the transferred OLAS amounts
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external virtual payable {
        if (msg.sender != l1Dispenser) {
            revert();
        }

        _sendMessage(targets, stakingAmounts, bridgePayload, transferAmount);
    }

    function setL2TargetDispenser(address _l2TargetDispenser) external {
        if (owner != msg.sender) {
            revert();
        }

        if (_l2TargetDispenser == address(0)) {
            revert();
        }
        l2TargetDispenser = _l2TargetDispenser;

        owner = address(0);
    }
}