// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IStructs.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IVotingEscrow.sol";

/// @title Dispenser - Smart contract for rewards
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is IStructs, IErrors, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event VotingEscrowUpdated(address ve);
    event TreasuryUpdated(address treasury);
    event TokenomicsUpdated(address tokenomics);

    // OLA token address
    address public immutable ola;
    // Voting Escrow address
    address public ve;
    // Treasury address
    address public treasury;
    // Tokenomics address
    address public tokenomics;
    // Mapping account => last taken reward block for staking
    mapping(address => uint256) public mapLastRewardBlocks;

    constructor(address _ola, address _ve, address _treasury, address _tokenomics) {
        ola = _ola;
        ve = _ve;
        treasury = _treasury;
        tokenomics = _tokenomics;
    }

    // Only treasury has a privilege to manipulate a dispenser
    modifier onlyTreasury() {
        if (treasury != msg.sender) {
            revert ManagerOnly(msg.sender, treasury);
        }
        _;
    }

    // Only voting escrow has a privilege to manipulate a dispenser
    modifier onlyVotingEscrow() {
        if (ve != msg.sender) {
            revert ManagerOnly(msg.sender, ve);
        }
        _;
    }

    function changeVotingEscrow(address newVE) external onlyOwner {
        ve = newVE;
        emit VotingEscrowUpdated(newVE);
    }

    function changeTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function changeTokenomics(address newTokenomics) external onlyOwner {
        tokenomics = newTokenomics;
        emit TokenomicsUpdated(newTokenomics);
    }

    /// @dev Withdraws rewards for owners of components / agents.
    function withdrawOwnerRewards() external nonReentrant {
        uint256 reward = ITokenomics(tokenomics).accountOwnerRewards(msg.sender);
        if (reward > 0) {
            IERC20(ola).safeTransfer(msg.sender, reward);
        }
    }

    /// @dev Calculates staking rewards.
    /// @param account Account address.
    /// @return reward Reward amount up to the last possible epoch.
    /// @return startBlockNumber Starting block number of the next reward request.
    function calculateStakingRewards(address account) public view
        returns (uint256 reward, uint256 startBlockNumber)
    {
        // Epoch length
        uint256 epochLen = ITokenomics(tokenomics).epochLen();
        // Block number at which the reward was obtained last time
        startBlockNumber = mapLastRewardBlocks[account];
        if (startBlockNumber == 0) {
            startBlockNumber = epochLen - 1;
        }
        // Get the last block of a previous epoch, which is the very last block we have the tokenomics info about
        uint256 endBlockNumber = (block.number / epochLen) * epochLen - 1;
        // Start block number must be smaller than the last block number of a previous epoch minus one epoch length
        // Also, at least two epochs should pass to get the reward for the first one
        if (startBlockNumber > endBlockNumber - epochLen || endBlockNumber < 2 * epochLen) {
            return (0, 0);
        }

        for (uint256 iBlock = startBlockNumber; iBlock < endBlockNumber; iBlock += epochLen) {
            // Get account's balance at the end of epoch
            (uint256 balance, ) = IVotingEscrow(ve).balanceOfAt(account, iBlock);
            // If there was no locking / staking, we skip the reward computation
            if (balance > 0) {
                // Get the total supply at the last block of the epoch
                (uint256 supply, ) = IVotingEscrow(ve).totalSupplyAt(iBlock);

                // Last block plus one gives us the next epoch where the previous epoch info is recorded
                uint256 epochNumber = (iBlock + 1) / epochLen;
                PointEcomonics memory pe = ITokenomics(tokenomics).getPoint(epochNumber);

                // Add to the reward depending on the staker reward
                if (supply > 0) {
                    reward += balance * pe.stakerRewards / supply;
                }
            }
        }
        // Update the block number of the received reward as the one we started from
        startBlockNumber = endBlockNumber;
    }

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount.
    function withdrawStakingRewards() external nonReentrant returns (uint256 reward) {
        uint256 startBlockNumber;
        (reward, startBlockNumber) = calculateStakingRewards(msg.sender);
        if (reward > 0) {
            mapLastRewardBlocks[msg.sender] = startBlockNumber;
            IERC20(ola).safeTransfer(msg.sender, reward);
        }
    }

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external view returns (bool) {
        return paused();
    }
}
