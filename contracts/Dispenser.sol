// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/ITreasury.sol";

// Structure for epoch point with tokenomics-related statistics during each epoch
// The size of the struct is 96 * 2 + 64 + 32 * 2 + 8 * 2 = 256 + 80 (2 slots)
struct EpochPoint {
    // Total amount of ETH donations accrued by the protocol during one epoch
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 totalDonationsETH;
    // Amount of OLAS intended to fund top-ups for the epoch based on the inflation schedule
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 totalTopUpsOLAS;
    // Inverse of the discount factor
    // IDF is bound by a factor of 18, since (2^64 - 1) / 10^18 > 18
    // IDF uses a multiplier of 10^18 by default, since it is a rational number and must be accounted for divisions
    // The IDF depends on the epsilonRate value, idf = 1 + epsilonRate, and epsilonRate is bound by 17 with 18 decimals
    uint64 idf;
    // Number of new owners
    // Each unit has at most one owner, so this number cannot be practically bigger than numNewUnits
    uint32 numNewOwners;
    // Epoch end timestamp
    // 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970, which is safe until the year of 2106
    uint32 endTime;
    // Parameters for rewards and top-ups (in percentage)
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    // treasuryFraction + rewardComponentFraction + rewardAgentFraction = 100%
    // Treasury fraction
    uint8 rewardTreasuryFraction;
    // maxBondFraction + topUpComponentFraction + topUpAgentFraction <= 100%
    // Amount of OLAS (in percentage of inflation) intended to fund bonding incentives during the epoch
    uint8 maxBondFraction;
}

// Struct for service staking epoch info
struct ServiceStakingPoint {
    // Amount of OLAS that funds service staking for the epoch based on the inflation schedule
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 totalServiceStakingOLAS;
    // Service staking vote weighting threshold
    uint16 serviceStakingWeightingThreshold;
    // Service staking fraction
    // This number cannot be practically bigger than 100 as it sums up to 100% with others
    // treasuryFraction + rewardComponentFraction + rewardAgentFraction + serviceStakingFraction = 100%
    uint8 serviceStakingFraction;
}

interface IVoteWeighting {
    function stakingTargetCheckpoint(uint256 stakingTarget) external;
    function stakingTargetRelativeWeigh(uint256 stakingTarget, uint256 time) external;
}

interface ITokenomicsInfo {
    function epochCounter() external returns (uint32);
    // TODO Create a better getter in Tokenomics
    function mapEpochTokenomics(uint256 eCounter) external returns (EpochPoint memory);
    function mapEpochServiceStakingPoints(uint256 eCounter) external returns (ServiceStakingPoint memory);
}

interface ITargetDispenser {
    function distribute(uint256[] memory stakingTargets) external;
}

/// @title Dispenser - Smart contract for distributing incentives
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event IncentivesClaimed(address indexed owner, uint256 reward, uint256 topUp);
    event ServiceStakingIncentivesClaimed(address indexed account, uint256 serviceStakingAmount);

    // Owner address
    address public owner;
    // Reentrancy lock
    uint8 internal _locked;

    // Tokenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;
    // Vote Weighting contract address
    address public voteWeighting;
    // Service staking weighting threshold
    uint256 public serviceStakingWeightingThreshold;

    // Mapping for last claimed service staking epochs
    mapping(uint256 => uint256) public lastClaimedStakingServiceEpoch;
    // Mapping for target processors based on chain Ids
    mapping(uint256 => address) public mapChainIdTargetProcessors;

    /// @dev Dispenser constructor.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    constructor(address _tokenomics, address _treasury)
    {
        owner = msg.sender;
        _locked = 1;

        // Check for at least one zero contract address
        if (_tokenomics == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }

        tokenomics = _tokenomics;
        treasury = _treasury;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes various managing contract addresses.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    function changeManagers(address _tokenomics, address _treasury) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Change Tokenomics contract address
        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
        // Change Treasury contract address
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
    }

    /// @dev Claims incentives for the owner of components / agents.
    /// @notice `msg.sender` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `msg.sender` were provided, they will be untouched and keep accumulating.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function claimOwnerIncentives(uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Calculate incentives
        (reward, topUp) = ITokenomics(tokenomics).accountOwnerIncentives(msg.sender, unitTypes, unitIds);

        bool success;
        // Request treasury to transfer funds to msg.sender if reward > 0 or topUp > 0
        if ((reward + topUp) > 0) {
            success = ITreasury(treasury).withdrawToAccount(msg.sender, reward, topUp);
        }

        // Check if the claim is successful and has at least one non-zero incentive.
        if (!success) {
            revert ClaimIncentivesFailed(msg.sender, reward, topUp);
        }

        emit IncentivesClaimed(msg.sender, reward, topUp);

        _locked = 1;
    }

    function _distribute(
        uint256[] memory stakingTargets,
        uint256[] memory stakingAmounts,
        bytes[] memory stakingTargetPayloads
    ) internal payable {
        // Traverse all staking targets
        for (uint256 i = 0; i < stakingTargets.length; ++i) {
            // Unpack chain Id and target addresses
            uint64 chainId;
            address target;

            if (chainId == 1) {
                // TODO Inject factory verification here
                // Get hash of target.code, check if the hash is present in the registered factory
                // Check the allowance
                uint256 allowance = IOLAS(olas).allowance(msg.sender, target);
                if (stakingAmounts[i] > allowance) {
                    revert();
                }
                IServiceStaking(target).deposit(stakingAmounts[i]);
                // stakingTargetPayloads[i] is ignored
            } else {
                address targetProcessor = mapChainIdTargetProcessors[chainId];
                // TODO Inject factory verification on the L2 side
                // TODO If L2 implementation address is the same as on L1, the check can be done locally as well
                ITargetProcessor(targetProcessor).deposit(target, stakingAmounts[i], stakingTargetPayloads[i]);
            }
        }
    }

    // TODO: Let choose epochs to claim for - set last epoch as eCounter or as last claimed.
    // TODO: We need to come up with the solution such that we are able to return unclaimed below threshold values back to effective staking.
    function claimServiceStakingIncentives(uint256[] memory stakingTargets, bytes[] memory stakingTargetPayloads) payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // TODO: account for stakingTargetRelativeWeight from epoch point
        uint256 weightingThreshold = serviceStakingWeightingThreshold;
        // Staking amount to send as a deposit
        uint256 stakingAmountDeposit;
        // Staking amount to return back to effective staking
        uint256 stakingAmountReturn;

        // Allocate the array of staking amounts
        uint256[] memory stakingAmounts = new uint256[](stakingTargets.length);

        // Traverse all staking targets
        for (uint256 i = 0; i < stakingTargets.length; ++i) {
            stakingTargetCheckpoint(stakingTargets[i]);

            uint256 eCounter = ITokenomicsInfo(tokenomics).epochCounter();
            // TODO: Write initial lastClaimedEpoch when the staking contract is added for voting
            uint256 lastClaimedEpoch = lastClaimedStakingServiceEpoch[stakingTargets[i]];
            // Shall not claim in the same epoch
            if (eCounter == lastClaimedEpoch) {
                revert();
            }
            
            // TODO: check the math
            for (j = lastClaimedEpoch; j < eCounter; ++j) {
                // TODO: optimize not to read several times in a row same epoch info
                // Get service staking info
                ServiceStakingPoint memory serviceStakingPoint = mapEpochServiceStakingPoints(j);
                
                EpochPoint memory ep = ITokenomicsInfo(tokenomics).mapEpochTokenomics(j);
                uint256 endTime = ep.endTime;
                
                // Get the staking weight for each epoch
                // TODO math from where we need to get the weight - endTime or endTime + WEEEK
                uint256 stakingWeight = IVoteWeighting(voteWeighting).stakingTargetRelativeWeight(stakingTargets[i], endTime);
                
                if (stakingWeight < serviceStakingPoint.serviceStakingWeightingThreshold) {
                    stakingAmountReturn += (serviceStakingPoint.totalServiceStakingOLAS * stakingWeight) / 1e18;
                } else {
                    stakingAmounts[i] += (serviceStakingPoint.totalServiceStakingOLAS * stakingWeight) / 1e18;
                    stakingAmountDeposit += stakingAmounts[i];
                }
            }

            // Write current epoch counter to start claiming with the next time
            lastClaimedStakingServiceEpoch[stakingTargets[i]] = eCounter;
        }

        // Mint tokens to the staking target dispenser
        ITreasury(treasury).withdrawToAccount(address(this), 0, stakingAmountDeposit);

        // Dispense all the service staking targets
        _distribute(stakingTargets, stakingAmounts, stakingTargetPayloads);

        // TODO: Tokenomics - subrtract EffectiveSatking to the stakingAmountDeposit - probably not needed as
        //       EffectiveSatking probably should only account for returned staking amount. Or come up with another variable
        // TODO: Tokenomics - return stakingAmountReturn into EffectiveSatking (or another additional variable tracking returns to redistribute further)
        // ITokenomics(tokenomics).returnServiceStaking(stakingAmountReturn);

        emit ServiceStakingIncentivesClaimed(msg.sender, stakingAmountDeposit, stakingAmountReturn);

        _locked = 1;
    }

    // TODO: Function to whitelist L2 processors
}
