// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IToken{
    function mint(address account, uint256 amount) external;
}

interface IDepositProcessor {
    function sendMessage(address target, uint256 stakingIncentive, bytes memory bridgePayload,
        uint256 transferAmount) external payable;
    function sendMessageBatch(address[] memory targets, uint256[] memory stakingIncentives, bytes memory bridgePayload,
        uint256 transferAmount) external payable;
}

/// @title MockStakingDispenser - Smart contract for mocking the service staking part of a Dispenser contract
contract MockStakingDispenser {
    event WithheldAmountSynced(uint256 chainId, uint256 amount);

    // Token contract address
    address public immutable token;

    // Mapping for L2 chain Id => withheld OLAS amounts
    mapping(uint256 => uint256) public mapChainIdWithheldAmounts;

    constructor(address _token) {
        token = _token;
    }

    /// @dev Mints a specified amount and sends to staking dispenser on L2.
    /// @param depositProcessor Deposit processor bridge mediator.
    /// @param stakingTarget Service staking target address on L2.
    /// @param stakingIncentive Token amount to stake.
    /// @param bridgePayload Bridge payload, if necessary.
    /// @param transferAmount Actual token transfer amount.
    function mintAndSend(
        address depositProcessor,
        address stakingTarget,
        uint256 stakingIncentive,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external payable {
        IToken(token).mint(depositProcessor, transferAmount);
        IDepositProcessor(depositProcessor).sendMessage{value:msg.value}(stakingTarget, stakingIncentive, bridgePayload,
            transferAmount);
    }

    /// @dev Mints specified amounts and sends a batch message to the L2 side via a corresponding bridge.
    /// @param depositProcessor Deposit processor bridge mediator.
    /// @param stakingTargets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual token transfer amount.
    function sendMessageBatch(
        address depositProcessor,
        address[] memory stakingTargets,
        uint256[] memory stakingIncentives,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external payable {
        IToken(token).mint(depositProcessor, transferAmount);
        IDepositProcessor(depositProcessor).sendMessageBatch{value:msg.value}(stakingTargets, stakingIncentives,
            bridgePayload, transferAmount);
    }

    function syncWithheldAmount(uint256 chainId, uint256 amount) external {
        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }
}