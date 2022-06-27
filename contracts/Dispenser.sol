// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IStructsTokenomics.sol";
import "./interfaces/ITokenomics.sol";

/// @title Dispenser - Smart contract for rewards
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is IStructsTokenomics, IErrorsTokenomics, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event TokenomicsUpdated(address tokenomics);
    event TransferETHFailed(address account, uint256 amount);
    event ReceivedETH(address sender, uint amount);

    // OLA token address
    address public immutable ola;
    // Tokenomics address
    address public tokenomics;
    // Mapping account => last reward block for staking
    mapping(address => uint256) public mapLastRewardEpochs;

    constructor(address _ola, address _tokenomics) {
        ola = _ola;
        tokenomics = _tokenomics;
    }

    /// @dev Changes the tokenomics addess.
    /// @param _tokenomics Tokenomics address.
    function changeTokenomics(address _tokenomics) external onlyOwner {
        tokenomics = _tokenomics;
        emit TokenomicsUpdated(_tokenomics);
    }

    /// @dev Withdraws rewards for owners of components / agents.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLA.
    /// @return success
    function withdrawOwnerRewards() external nonReentrant whenNotPaused
        returns (uint256 reward, uint256 topUp, bool success)
    {
        success = true;
        (reward, topUp) = ITokenomics(tokenomics).accountOwnerRewards(msg.sender);
        if (reward > 0) {
            (success, ) = msg.sender.call{value: reward}("");
            if (!success) {
                emit TransferETHFailed(msg.sender, reward);
            }
        }
        if (topUp > 0) {
            IERC20(ola).safeTransfer(msg.sender, topUp);
        }
    }

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLA.
    function withdrawStakingRewards() external nonReentrant whenNotPaused
        returns (uint256 reward, uint256 topUp, bool success)
    {
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
                emit TransferETHFailed(msg.sender, reward);
            }
        }
        if (topUp > 0) {
            IERC20(ola).safeTransfer(msg.sender, topUp);
        }
    }

    /// @dev Receives ETH.
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
