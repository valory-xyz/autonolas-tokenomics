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
    // Mapping Id => account address for veOLA
    mapping(address => uint256) private _mapLockedAccountIds;
    // Set of locking accounts for veOLA
    address[] private _lockedAccounts;

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

    /// @dev Distributes rewards between stakers.
    function _distributeStakerRewards(uint256 stakerRewards) internal {
        VotingEscrow veContract = VotingEscrow(ve);

        // Get the overall amount of rewards for stakers
        uint256 rewardLeft = stakerRewards;

        // Iterate over staker addresses and distribute
        uint256 numAccounts = _lockedAccounts.length;
        uint256 supply = veContract.totalSupply();
        if (supply > 0) {
            for (uint256 i = 0; i < numAccounts; ++i) {
                uint256 balance = veContract.balanceOf(_lockedAccounts[i]);
                // If the account has already unlocked, its balance will be zero
                // When they unstake, they will be removed from the set of locked accounts
                if (balance > 0) {
                    // Reward for this specific staker
                    uint256 reward = stakerRewards * balance / supply;

                    // If there is a rounding error, floor to the correct value
                    if (reward > rewardLeft) {
                        reward = rewardLeft;
                    }
                    rewardLeft -= reward;
                    mapStakerRewards[_lockedAccounts[i]] += reward;
                }
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

        // Distribute rewards for stakers
        _distributeStakerRewards(stakerRewards);
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
    /// @return balance Reward balance.
    function withdrawStakingRewards() external nonReentrant returns (uint256 balance) {
        balance = mapStakerRewards[msg.sender];
        if (balance > 0) {
            mapStakerRewards[msg.sender] = 0;
            IERC20(ola).safeTransfer(msg.sender, balance);

            // Clean up the veOLA-related account information
            uint256 id = _mapLockedAccountIds[msg.sender];
            uint256 numAccounts = _lockedAccounts.length;
            _lockedAccounts[id] = _lockedAccounts[numAccounts - 1];
            address addr = _lockedAccounts[id];
            _lockedAccounts.pop();
            _mapLockedAccountIds[addr] = id;
            _mapLockedAccountIds[msg.sender] = 0;
        }
    }

    /// @dev Gets the paused state.
    /// @return True, if paused.
    function isPaused() external view returns (bool) {
        return paused();
    }

    /// @dev Adds account to the set of current locked accounts.
    /// @param account Account address.
    function addLockedAccount(address account) external {
        uint256 id = _lockedAccounts.length;
        _mapLockedAccountIds[account] = id;
        _lockedAccounts.push(account);
    }
}
