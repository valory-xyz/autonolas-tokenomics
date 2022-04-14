// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Interface for dispenser management.
interface IDispenser {
    /// @dev Distributes rewards.
    function distributeRewards(
        uint256 componentFraction,
        uint256 agentFraction,
        uint256 stakerFraction,
        uint256 amountOLA
    ) external;

    /// @dev Withdraws rewards for stakers.
    /// @param account Account address.
    /// @return balance Reward balance.
    function withdrawStakingReward(address account) external returns (uint256 balance);
}
