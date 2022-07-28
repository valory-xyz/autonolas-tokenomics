// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/ITokenomics.sol";

/// @title Dispenser - Smart contract for rewards
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is IErrorsTokenomics, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event TokenomicsUpdated(address tokenomics);
    event TransferETHFailed(address account, uint256 amount);
    event ReceivedETH(address sender, uint amount);

    // OLAS token address
    address public immutable olas;
    // Tokenomics address
    address public tokenomics;
    // Mapping account => last reward block for staking
    mapping(address => uint256) public mapLastRewardEpochs;

    /// @dev Dispenser constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    constructor(address _olas, address _tokenomics) {
        olas = _olas;
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
    /// @return topUp Top-up amount in OLAS.
    /// @return success
    function withdrawOwnerRewards() external nonReentrant
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
            IERC20(olas).safeTransfer(msg.sender, topUp);
        }
    }

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function withdrawStakingRewards() external nonReentrant
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
            IERC20(olas).safeTransfer(msg.sender, topUp);
        }
    }

    /// @dev Receives ETH.
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
