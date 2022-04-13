// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IStructs.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITokenomics.sol";


/// @title Bond Depository - Smart contract for OLA Bond Depository
/// @author AL
contract Depository is IErrors, IStructs, Ownable, ReentrancyGuard {
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
    // Mapping of owner of component / agent address => revenue amount
    mapping(address => uint256) public mapOwnersRevenue;

    constructor(address _ola, address _ve, address _treasury, address _tokenomics) {
        ola = _ola;
        ve = _ve;
        treasury = _treasury;
        tokenomics = _tokenomics;
    }

    function changeVeotingEscrow(address newVE) external onlyOwner {
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

    /// @dev Starts a new epoch.
    function startNewEpoch() external onlyOwner {
        // Gets the latest economical point of epoch
        PointEcomonics memory point = ITokenomics(tokenomics).getLastPoint();

        // If the point exists, it was already started and there is no need to continue
        if (!point.exists) {
            // Process the epoch data
            ITokenomics(tokenomics).checkpoint();

            // Request OLA funds from treasury for the last epoch
            uint256 amountOLA = point.totalRevenue;
            ITreasury(treasury).requestFunds(amountOLA);

            // Distribute rewards information between component and agent owners
            uint256 componentReward = point.componentFraction * amountOLA / 100;
            uint256 agentReward = point.agentFraction * amountOLA / 100;

            // Iterating over components
            address[] memory profitableComponents = ITokenomics(tokenomics).getProfitableComponents();
            uint256 numComponents = profitableComponents.length;
            if (numComponents > 0) {
                uint256 rewardPerComponent = componentReward / numComponents;
                for (uint256 i = 0; i < numComponents; ++i) {
                    mapOwnersRevenue[profitableComponents[i]] += rewardPerComponent;
                }
            }

            // Iterating over agents
            address[] memory profitableAgents = ITokenomics(tokenomics).getProfitableAgents();
            uint256 numAgents = profitableAgents.length;
            if (numAgents > 0) {
                uint256 rewardPerAgent = agentReward / numAgents;
                for (uint256 i = 0; i < numAgents; ++i) {
                    mapOwnersRevenue[profitableAgents[i]] += rewardPerAgent;
                }
            }
        }
    }

    /// @dev Withdraws rewards for owners of components / agents.
    /// @param account Account address.
    function withdrawOwnerReward(address account) external nonReentrant {
        uint256 balance = mapOwnersRevenue[account];
        if (balance > 0) {
            mapOwnersRevenue[account] = 0;
            IERC20(ola).safeTransferFrom(address(this), account, balance);
        }
    }

    /// @dev Withdraws rewards for stakers.
    /// @param account Account address.
    function withdrawStakingReward(address account) external nonReentrant {

    }
}
