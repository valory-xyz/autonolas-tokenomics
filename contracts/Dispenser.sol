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
import "hardhat/console.sol";

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
    function distributeRewards(uint256 componentRewards, uint256 agentRewards) external onlyTreasury whenNotPaused
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
        returns (uint256 reward, uint256 startBlockNumber)
    {
        // Block number at which the reward was obtained last time
        startBlockNumber = _mapLastRewardBlocks[msg.sender];
        // Get the last block of a previous epoch, which is the very last block we have the tokenomics info about
        uint256 epochLen = ITokenomics(tokenomics).epochLen();
        uint256 endBlockNumber = (block.number / epochLen) * epochLen;
        // If we are in a zero's epoch, we don't have any rewards
        if (endBlockNumber == 0) {
            return (0, 0);
        }

        // Get account's history points with block number checkpoints and balances
        (, uint256[] memory accountBlocks, uint256[] memory accountBalances) =
        IVotingEscrow(ve).getHistoryAccountBalances(account, startBlockNumber, endBlockNumber);
        // Get overall history points of with block number checkpoints and supply balances
        (, uint256[] memory supplyBlocks, uint256[] memory supplyBalances) =
        IVotingEscrow(ve).getHistoryTotalSupply(startBlockNumber, endBlockNumber);
        if (startBlockNumber == 0) {
            startBlockNumber = accountBlocks[0];
        }

        // index 0: account, index 1: supply
        uint256[] memory balances = new uint256[](2);
        uint256[] memory counters = new uint256[](2);
        // Sync with supply blocks
        for (; counters[1] < supplyBlocks.length; ++counters[1]) {
            if (supplyBlocks[counters[1]] > startBlockNumber) {
                break;
            }
        }

//        console.log("account block length", accountBlocks.length);
//        console.log("account balances length", accountBalances.length);
//        console.log("account block", accountBlocks[0]);
//        console.log("account balance", accountBalances[0]);
//        console.log("supply block length", supplyBlocks.length);
//        console.log("supply balance length", supplyBalances.length);
//        console.log("supply block", supplyBlocks[0]);
//        console.log("supply balance", supplyBalances[0]);
//        for(uint256 i = 0; i < supplyBlocks.length; ++i) {
//            console.log("i", i);
//            console.log("supply block", supplyBlocks[i]);
//            console.log("supply balance", supplyBalances[i]);
//        }
        {
            uint256 rewardEpoch;
//            console.log("startBlockNumber", startBlockNumber);
//            console.log("endBlockNumber", endBlockNumber);
            uint256 epochNumber = startBlockNumber / epochLen;
            PointEcomonics memory pe = ITokenomics(tokenomics).getPoint(epochNumber);
            for (uint256 iBlock = startBlockNumber; iBlock < endBlockNumber; ++iBlock) {
//                console.log("iBlock", iBlock);
//                console.log("counter account", counters[0]);
//                console.log("counter supply", counters[1]);

                // As soon as the new checkpoint block number is reached, switch to its balance and continue until next one
                if (counters[0] < accountBlocks.length && iBlock == accountBlocks[counters[0]]) {
                    balances[0] = accountBalances[counters[0]];
                    counters[0]++;
                }
                // Same for the supply checkpoint
                if (counters[1] < supplyBlocks.length && iBlock == supplyBlocks[counters[1]]) {
                    balances[1] = supplyBalances[counters[1]];
                    counters[1]++;
                }

                // Add to the reward depending on the staker reward
                if (balances[1] > 0) {
                    rewardEpoch += balances[0] * pe.stakerRewards / (balances[1] * epochLen);
                    console.log("iBlock", iBlock);
                    console.log("rewardEpoch", rewardEpoch/10**18);
                    console.log("balances[0]", balances[0]/10**18);
                    console.log("balances[1]", balances[1]/10**18);
                }

                // Check for the end of epoch and get the tokenomics point
                if (iBlock % epochLen == 0) {
                    // Get the epoch number at that block and its tokenomics parameters
                    epochNumber = iBlock / epochLen;
                    pe = ITokenomics(tokenomics).getPoint(epochNumber);
                    reward += rewardEpoch;
                    console.log("iBlock", iBlock);
                    console.log("reward", reward);
                    console.log("epoch", epochNumber);
                    console.log("staking reward", pe.stakerRewards);
                    rewardEpoch = 0;
                }
            }
            // Add reward for the last considered epoch
            reward += rewardEpoch;
            console.log("total reward", reward);
        }

        // Check that we have traversed all the block checkpoints
        if (accountBlocks.length != counters[0]) {
            revert WrongArrayLength(accountBlocks.length, counters[0]);
        }
        if (supplyBlocks.length != counters[1]) {
            revert WrongArrayLength(supplyBlocks.length, counters[1]);
        }
        // Update the block number of the received reward as the one we started from
        startBlockNumber = endBlockNumber;
    }

    /// @dev Withdraws rewards for stakers.
    /// @return reward Reward balance.
    function withdrawStakingRewards() external nonReentrant returns (uint256 reward) {
        uint256 startBlockNumber;
        (reward, startBlockNumber) = calculateStakingRewards(msg.sender);
        if (reward > 0) {
            _mapLastRewardBlocks[msg.sender] = startBlockNumber;
            IERC20(ola).safeTransfer(msg.sender, reward);
        }
    }

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external view returns (bool) {
        return paused();
    }
}
