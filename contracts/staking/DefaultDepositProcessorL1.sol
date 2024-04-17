// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDispenser {
    function syncWithheldAmount(uint256 chainId, uint256 amount) external;
}

error TargetRelayerOnly(address l1Relayer, address l1MessageRelayer);
error WrongMessageSender(address l2Dispenser, address l2TargetDispenser);

abstract contract DefaultDepositProcessorL1 {
    event MessageSent(uint256 indexed sequence, address[] targets, uint256[] stakingAmounts, uint256 transferAmount);
    event MessageReceived(address indexed l1Relayer, uint256 indexed chainId, bytes data);

    // TODO Calculate min maxGas required on L2 side
    // Token transfer gas limit
    uint256 public constant TOKEN_GAS_LIMIT = 200_000;
    // Message transfer gas limit
    uint256 public constant MESSAGE_GAS_LIMIT = 2_000_000;
    // OLAS token address
    address public immutable olas;
    // L1 tokenomics dispenser address
    address public immutable l1Dispenser;
    // L1 token relayer bridging contract address
    address public immutable l1TokenRelayer;
    // L1 message relayer bridging contract address
    address public immutable l1MessageRelayer;
    // L2 target chain Id
    uint256 public immutable l2TargetChainId;
    // L2 target dispenser address, set by the deploying owner
    address public l2TargetDispenser;
    // Contract owner until the time when the l2TargetDispenser is set
    address public owner;

    /// @dev DefaultDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address.
    /// @param _l1MessageRelayer L1 message relayer bridging contract address.
    /// @param _l2TargetChainId L2 target chain Id.
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

    /// @dev Sends message to the L2 side via a corresponding bridge.
    /// @notice Message is sent to the target dispenser contract to reflect transferred OLAS and staking amounts.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual total OLAS amount to be transferred.
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal virtual;

    /// @dev Receives a message on L1 sent from L2 target dispenser side.
    /// @param l1Relayer L1 source relayer.
    /// @param l2Dispenser L2 target dispenser that originated the message.
    /// @param data Message data payload sent from L2.
    function _receiveMessage(address l1Relayer, address l2Dispenser, bytes memory data) internal virtual {
        // Check L1 Relayer address to be the msg.sender, where applicable
        if (l1Relayer != l1MessageRelayer) {
            revert TargetRelayerOnly(msg.sender, l1MessageRelayer);
        }

        // Check L2 dispenser address originating the message on L2
        if (l2Dispenser != l2TargetDispenser) {
            revert WrongMessageSender(l2Dispenser, l2TargetDispenser);
        }

        // Extract the amount of OLAS to sync
        (uint256 amount) = abi.decode(data, (uint256));

        IDispenser(l1Dispenser).syncWithheldAmount(l2TargetChainId, amount);
    }

    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingAmount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
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


    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
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

    /// @dev Sets L2 target dispenser address and zero-s the owner.
    /// @param l2Dispenser L2 target dispenser address.
    function setL2TargetDispenser(address l2Dispenser) external {
        if (owner != msg.sender) {
            revert();
        }

        if (l2Dispenser == address(0)) {
            revert();
        }
        l2TargetDispenser = l2Dispenser;

        owner = address(0);
    }
}