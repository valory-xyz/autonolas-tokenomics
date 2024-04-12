// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDispenser {
    function syncWithheldAmount(uint256 chainId, uint256 amount) external;
}

error TargetRelayerOnly(address messageSender, address l1MessageRelayer);

error WrongMessageSender(address l2Dispenser, address l2TargetDispenser);

abstract contract DefaultTargetProcessorL1 {
    uint256 public constant GAS_LIMIT = 2_000_000;
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
        bytes[] memory,
        uint256 transferAmount
    ) internal virtual;

    function _receiveMessage(
        address messageSender,
        address l2Dispenser,
        uint256 chainId,
        bytes memory data
    ) internal virtual {
        // Check L1 Relayer address
        if (messageSender != l1MessageRelayer) {
            revert TargetRelayerOnly(messageSender, l1MessageRelayer);
        }

        if (l2Dispenser != l2TargetDispenser) {
            revert WrongMessageSender(l2Dispenser, l2TargetDispenser);
        }
        
        if (l2TargetChainId != chainId) {
            revert();
        }

        // Extract the amount of OLAS to sync
        (uint256 amount) = abi.decode(data, (uint256));

        IDispenser(l1Dispenser).syncWithheldAmount(l2TargetChainId, amount);
    }

    function sendMessage(
        address target,
        uint256 stakingAmount,
        bytes memory payload,
        uint256 transferAmount
    ) external virtual payable {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[0] = stakingAmount;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        _sendMessage(targets, stakingAmounts, payloads, transferAmount);
    }

    // Send a message to the staking dispenser contract to reflect the transferred OLAS amounts
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes[] memory payloads,
        uint256 transferAmount
    ) external virtual payable {
        _sendMessage(targets, stakingAmounts, payloads, transferAmount);
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