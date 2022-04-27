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
contract Dispenser is IErrors, IStructs, Ownable, Pausable, ReentrancyGuard {
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
    // Mapping of owner of component / agent address => reward amount
    mapping(address => uint256) public mapOwnerRewards;
    // Mapping account => last taken reward block for staking
    mapping(address => uint256) private _mapLastRewardBlocks;

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

    /// @dev Distributes rewards between component and agent owners.
    function _distributeOwnerRewards(uint256 totalComponentRewards, uint256 totalAgentRewards) internal {
        uint256 componentRewardLeft = totalComponentRewards;
        uint256 agentRewardLeft = totalAgentRewards;

        // Get component owners and their rewards
        (address[] memory profitableComponentOwners, uint256[] memory componentRewards) =
            ITokenomics(tokenomics).getProfitableComponents();
        uint256 numComponents = profitableComponentOwners.length;
        if (numComponents > 0) {
            // Calculate reward per component owner
            for (uint256 i = 0; i < numComponents; ++i) {
                // If there is a rounding error, floor to the correct value
                if (componentRewards[i] > componentRewardLeft) {
                    componentRewards[i] = componentRewardLeft;
                }
                componentRewardLeft -= componentRewards[i];
                mapOwnerRewards[profitableComponentOwners[i]] += componentRewards[i];
            }
        }

        // Get agent owners and their rewards
        (address[] memory profitableAgentOwners, uint256[] memory agentRewards) =
            ITokenomics(tokenomics).getProfitableAgents();
        uint256 numAgents = profitableAgentOwners.length;
        if (numAgents > 0) {
            for (uint256 i = 0; i < numAgents; ++i) {
                // If there is a rounding error, floor to the correct value
                if (agentRewards[i] > agentRewardLeft) {
                    agentRewards[i] = agentRewardLeft;
                }
                agentRewardLeft -= agentRewards[i];
                mapOwnerRewards[profitableAgentOwners[i]] += agentRewards[i];
            }
        }
    }

    /// @dev Distributes rewards.
    function distributeRewards(
        uint256 stakerRewards,
        uint256 componentRewards,
        uint256 agentRewards
    ) external onlyTreasury whenNotPaused
    {
        // Distribute rewards between component and agent owners
        _distributeOwnerRewards(componentRewards, agentRewards);
    }

    /// @dev Withdraws rewards for owners of components / agents.
    function withdrawOwnerRewards() external nonReentrant {
        uint256 balance = mapOwnerRewards[msg.sender];
        if (balance > 0) {
            mapOwnerRewards[msg.sender] = 0;
            IERC20(ola).safeTransfer(msg.sender, balance);
        }
    }

    function calculateStakingRewards(address account) public view
        returns (uint256 reward, uint256 lastRewardBlockNumber)
    {
        // Block number at which the reward was obtained last time
        lastRewardBlockNumber = _mapLastRewardBlocks[msg.sender];
        // Get the last block of a previous epoch, which is the very first block we have the tokenomics info about
        uint256 prevEpoch = ITokenomics(tokenomics).getEpoch(block.number) - 1;
        uint256 initialBlockNumber = prevEpoch * ITokenomics(tokenomics).epochLen() - 1;
        uint256 prevBlockNumber = initialBlockNumber;
        // Get account's history points with balances
        (uint256 numPoints, PointVoting[] memory points) = IVotingEscrow(ve).getHistoryPoints(account);
        // Go back in blocks of points until we reach the last block we start calculating rewards from
        uint256 i;
        for (i = numPoints; i > 0; --i) {
            if (points[i-1].blockNumber <= prevBlockNumber) {
                break;
            }
        }

        // This is done to enter the if condition the first time
        if (prevBlockNumber == points[i].blockNumber) {
            prevBlockNumber++;
        }
        for (; i > 0; --i) {
            uint256 blockNumber = points[i].blockNumber;
            // Skip all the other points with the same block number
            if (prevBlockNumber > blockNumber) {
                // If we reached the point where the last reward was taken, no more reward can be accumulated
                if (blockNumber == lastRewardBlockNumber) {
                    break;
                }
                // Get the total supply at that block number and the account balance
                uint256 supply = IVotingEscrow(ve).totalSupplyAt(blockNumber);
                uint256 balance = points[i].balance;

                // Get the epoch number at that block and its tokenomics parameters
                uint256 epochNumber = ITokenomics(tokenomics).getEpoch(blockNumber);
                PointEcomonics memory pe = ITokenomics(tokenomics).getPoint(epochNumber);

                // Add to the reward depending on the staker reward
                reward += balance * pe.stakerRewards / supply;

                // Checkpoint of the last block number
                prevBlockNumber = blockNumber;
            }
        }
        // Update the block number of the received reward as the one we started from
        lastRewardBlockNumber = initialBlockNumber;
    }

    /// @dev Withdraws rewards for stakers.
    /// @return reward Reward balance.
    function withdrawStakingRewards() external nonReentrant returns (uint256 reward) {
        uint256 lastRewardBlockNumber;
        (reward, lastRewardBlockNumber) = calculateStakingRewards(msg.sender);
        if (reward > 0) {
            _mapLastRewardBlocks[msg.sender] = lastRewardBlockNumber;
            IERC20(ola).safeTransfer(msg.sender, reward);
        }
    }

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external view returns (bool) {
        return paused();
    }
}
