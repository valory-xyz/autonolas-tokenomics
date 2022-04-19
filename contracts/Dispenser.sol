// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./governance/VotingEscrow.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IStructs.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITokenomics.sol";


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
    // Mapping of staker address => reward amount
    mapping(address => uint256) public mapStakerRewards;

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
    function _distributeOwnerRewards(uint256 componentReward, uint256 agentReward) internal {
        uint256 componentRewardLeft = componentReward;
        uint256 agentRewardLeft = agentReward;

        // Get components owners and their UCFc-s
        (address[] memory profitableComponents, uint256[] memory ucfcs) =
        ITokenomics(tokenomics).getProfitableComponents();

        uint256 numComponents = profitableComponents.length;
        uint256 sumProfits;
        if (numComponents > 0) {
            // Calculate overall profits of UCFc-s
            for (uint256 i = 0; i < numComponents; ++i) {
                sumProfits += ucfcs[i];
            }

            // Calculate reward per component owner
            for (uint256 i = 0; i < numComponents; ++i) {
                uint256 rewardPerComponent = componentReward * ucfcs[i] / sumProfits;
                // If there is a rounding error, floor to the correct value
                if (rewardPerComponent > componentRewardLeft) {
                    rewardPerComponent = componentRewardLeft;
                }
                componentRewardLeft -= rewardPerComponent;
                mapOwnerRewards[profitableComponents[i]] += rewardPerComponent;
            }
        }

        // Get components owners and their UCFa-s
        (address[] memory profitableAgents, uint256[] memory ucfas) = ITokenomics(tokenomics).getProfitableAgents();
        uint256 numAgents = profitableAgents.length;
        if (numAgents > 0) {
            // Calculate overall profits of UCFa-s
            sumProfits = 0;
            for (uint256 i = 0; i < numAgents; ++i) {
                sumProfits += ucfas[i];
            }

            uint256 rewardPerAgent;
            for (uint256 i = 0; i < numAgents; ++i) {
                rewardPerAgent = agentReward * ucfas[i] / sumProfits;
                // If there is a rounding error, floor to the correct value
                if (rewardPerAgent > agentRewardLeft) {
                    rewardPerAgent = agentRewardLeft;
                }
                agentRewardLeft -= rewardPerAgent;
                mapOwnerRewards[profitableAgents[i]] += rewardPerAgent;
            }
        }
    }

    /// @dev Distributes rewards between stakers.
    function _distributeStakerRewards(uint256 stakerReward) internal {
        VotingEscrow veContract = VotingEscrow(ve);
        address[] memory accounts = veContract.getLockAccounts();

        // Get the overall amount of rewards for stakers
        uint256 rewardLeft = stakerReward;

        // Iterate over staker addresses and distribute
        uint256 numAccounts = accounts.length;
        uint256 supply = veContract.totalSupply();
        if (supply > 0) {
            for (uint256 i = 0; i < numAccounts; ++i) {
                uint256 balance = veContract.balanceOf(accounts[i]);
                // Reward for this specific staker
                uint256 reward = stakerReward * balance / supply;

                // If there is a rounding error, floor to the correct value
                if (reward > rewardLeft) {
                    reward = rewardLeft;
                }
                rewardLeft -= reward;
                mapStakerRewards[accounts[i]] += reward;
            }
        }
    }

    /// @dev Distributes rewards.
    function distributeRewards(
        uint256 stakerReward,
        uint256 componentReward,
        uint256 agentReward
    ) external onlyTreasury whenNotPaused
    {
        // Distribute rewards between component and agent owners
        _distributeOwnerRewards(componentReward, agentReward);

        // Distribute rewards for stakers
        _distributeStakerRewards(stakerReward);
    }

    /// @dev Withdraws rewards for owners of components / agents.
    function withdrawOwnerRewards() external nonReentrant {
        uint256 balance = mapOwnerRewards[msg.sender];
        if (balance > 0) {
            mapOwnerRewards[msg.sender] = 0;
            IERC20(ola).safeTransfer(msg.sender, balance);
        }
    }

    /// @dev Withdraws rewards for stakers.
    /// @param account Account address.
    /// @return balance Reward balance.
    function withdrawStakingRewards(address account) external onlyVotingEscrow returns (uint256 balance) {
        balance = mapStakerRewards[account];
        if (balance > 0) {
            mapStakerRewards[account] = 0;
            IERC20(ola).safeTransfer(ve, balance);
        }
    }

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external returns (bool) {
        return paused();
    }
}
