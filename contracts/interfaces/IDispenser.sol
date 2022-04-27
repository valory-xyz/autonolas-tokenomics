// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Interface for dispenser management.
interface IDispenser {
    /// @dev Distributes rewards.
    function distributeRewards(
        uint256 stakerReward,
        uint256 componentReward,
        uint256 agentReward
    ) external;

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external returns (bool);
}
