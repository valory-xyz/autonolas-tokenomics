// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./GenericTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/ITokenomics.sol";

/// @title Dispenser - Smart contract for rewards
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is GenericTokenomics {
    event ReceivedETH(address sender, uint amount);

    // Mapping account => last reward block for staking
    mapping(address => uint256) public mapLastRewardEpochs;

    /// @dev Dispenser constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    constructor(address _olas, address _tokenomics)
        GenericTokenomics(_olas, _tokenomics, address(0), address(0), address(0))
    {
    }

    /// @dev Withdraws rewards for owners of components / agents.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success
    function withdrawOwnerRewards() external returns (uint256 reward, uint256 topUp, bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        success = true;
        (reward, topUp) = ITokenomics(tokenomics).accountOwnerRewards(msg.sender);
        if (reward > 0) {
            (success, ) = msg.sender.call{value: reward}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), msg.sender, reward);
            }
        }
        if (topUp > 0) {
            IOLAS(olas).transfer(msg.sender, topUp);
        }

        _locked = 1;
    }

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function withdrawStakingRewards() external returns (uint256 reward, uint256 topUp, bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        success = true;
        // Starting epoch number where the last time reward was not yet given
        uint256 startEpochNumber = mapLastRewardEpochs[msg.sender];
        uint256 endEpochNumber;
        // Get the reward and epoch number up to which the reward was calculated
        (reward, topUp, endEpochNumber) = ITokenomics(tokenomics).calculateStakingRewards(msg.sender, startEpochNumber);
        // Update the latest epoch number from which reward will be calculated the next time
        mapLastRewardEpochs[msg.sender] = endEpochNumber;

        if (reward > 0) {
            (success, ) = msg.sender.call{value: reward}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), msg.sender, reward);
            }
        }
        if (topUp > 0) {
            IOLAS(olas).transfer(msg.sender, topUp);
        }

        _locked = 1;
    }

    /// @dev Receives ETH.
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
