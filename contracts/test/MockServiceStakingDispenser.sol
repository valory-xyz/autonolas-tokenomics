// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IToken{
    function mint(address account, uint256 amount) external;
}

interface IDepositProcessor {
    function sendMessage(address target, uint256 stakingAmount, bytes memory bridgePayload,
        uint256 transferAmount) external payable;
    function sendMessageBatch(address[] memory targets, uint256[] memory stakingAmounts, bytes memory bridgePayload,
        uint256 transferAmount) external payable;
}

/// @title MockServiceStakingDispenser - Smart contract for mocking the service staking part of a Dispenser contract
contract MockServiceStakingDispenser {
    event WithheldAmountSynced(uint256 chainId, uint256 amount);

    // Token contract address
    address public immutable token;

    // Mapping for L2 chain Id => withheld OLAS amounts
    mapping(uint256 => uint256) public mapChainIdWithheldAmounts;

    constructor(address _token) {
        token = _token;
    }

    /// @dev Mints a specified amount and sends to staking dispenser on L2.
    /// @param stakingTarget Service staking target address on L2.
    /// @param stakingAmount Token amount to stake.
    /// @param depositProcessor Deposit processor bridge mediator.
    /// @param bridgePayload Bridge payload, if necessary.
    function mintAndSend(
        address stakingTarget,
        uint256 stakingAmount,
        address depositProcessor,
        bytes memory bridgePayload
    ) external payable {
        IToken(token).mint(depositProcessor, stakingAmount);
        IDepositProcessor(depositProcessor).sendMessage{value:msg.value}(stakingTarget, stakingAmount, bridgePayload,
            stakingAmount);
    }

    /// @dev Mints specified amounts and sends a batch message to the L2 side via a corresponding bridge.
    /// @param stakingTargets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param depositProcessor Deposit processor bridge mediator.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    function sendMessageBatch(
        address[] memory stakingTargets,
        uint256[] memory stakingAmounts,
        address depositProcessor,
        bytes memory bridgePayload
    ) external payable {
        uint256 transferAmount;
        for (uint256 i = 0; i < stakingAmounts.length; ++i) {
            transferAmount += stakingAmounts[i];
        }
        IToken(token).mint(depositProcessor, transferAmount);
        IDepositProcessor(depositProcessor).sendMessageBatch{value:msg.value}(stakingTargets, stakingAmounts,
            bridgePayload, transferAmount);
    }

    function syncWithheldAmount(uint256 chainId, uint256 amount) external {
        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }
}