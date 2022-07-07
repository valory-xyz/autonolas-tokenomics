// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/// @dev Interface for tokenomics structs.
interface IStructsTokenomics {
    // TODO Pack these numbers into a single (double) uint256
    // Structure for component / agent tokenomics-related statistics
    struct PointUnits {
        // Total absolute number of components / agents
        uint256 numUnits;
        // Number of components / agents that were part of profitable services
        uint256 numProfitableUnits;
        // Allocated rewards for components / agents
        uint256 unitRewards;
        // Cumulative UCFc-s / UCFa-s
        uint256 ucfuSum;
        // Coefficient weight of units for the final UCF formula, set by the government
        uint256 ucfWeight;
        // Number of new units
        uint256 numNewUnits;
        // Number of new owners
        uint256 numNewOwners;
        // Component / agent weight for new valuable code
        uint256 unitWeight;
    }

    // Structure for tokenomics
    struct PointEcomonics {
        // UCFc
        PointUnits ucfc;
        // UCFa
        PointUnits ucfa;
        // Discount factor
        uint256 df;
        // Profitable number of services
        uint256 numServices;
        // Treasury rewards
        uint256 treasuryRewards;
        // Staking rewards
        uint256 stakerRewards;
        // Donation in ETH
        uint256 totalDonationETH;
        // Top-ups for component / agent owners
        uint256 ownerTopUps;
        // Top-ups for stakers
        uint256 stakerTopUps;
        // Number of valuable devs can be paid per units of capital per epoch
        uint256 devsPerCapital;
        // Timestamp
        uint256 ts;
        // Block number
        uint256 blockNumber;
    }
}
