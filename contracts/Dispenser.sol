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
    // maxBondFraction + topUpComponentFraction + topUpAgentFraction + serviceStakingFraction <= 100%
    uint8 serviceStakingFraction;
}

interface IVoteWeighting {
    function checkpointNominee(address nominee, uint256 chainId) external;
    function nomineeRelativeWeight(address nominee, uint256 chainId, uint256 time) external;
}

interface ITokenomicsInfo {
    function epochCounter() external returns (uint32);
    // TODO Create a better getter in Tokenomics
    function mapEpochTokenomics(uint256 eCounter) external returns (EpochPoint memory);
    function mapEpochServiceStakingPoints(uint256 eCounter) external returns (ServiceStakingPoint memory);
    function refundFromServiceStaking(uint256 amount) external;
}

interface ITargetProcessor {
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
    event SetTargetProcessorChainIds(address[] memory targetProcessors, uint256[] memory chainIds);
    event WithheldAmountSynced(uint256 chainId, uint256 amount);

    enum Pause {
        Unpaused,
        DevIncentivesPaused,
        StakingIncentivesPaused,
        AllPaused
    }

    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;

    // Owner address
    address public owner;
    // Reentrancy lock
    uint8 internal _locked;
    // Pause state
    Pause public paused;

    // Tokenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;
    // Vote Weighting contract address
    address public voteWeighting;

    // Mapping for (chainId | target) service staking pair => last claimed epochs
    mapping(uint256 => uint256) public mapLastClaimedStakingServiceEpochs;
    // Mapping for epoch => remaining service staking amount
    mapping(uint256 => uint256) public mapEpochRemainingServiceStakingAmounts;
    // Mapping for L2 chain Id => dedicated target processors
    mapping(uint256 => address) public mapChainIdTargetProcessors;
    // Mapping for L2 chain Id => withheld OLAS amounts
    mapping(uint256 => uint256) public mapChainIdWithheldAmounts;

    /// @dev Dispenser constructor.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    constructor(address _tokenomics, address _treasury)
    {
        owner = msg.sender;
        _locked = 1;
        // TODO Define final behavior before deployment
        paused = Pause.DevIncentivesPaused;

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

    function setRemainingServiceStakingAmount(uint256 epochNumber, uint256 amount) {
        // Check for the tokenomics
        if (msg.sender != tokenomics) {
            revert ManagerOnly(msg.sender, tokenomics);
        }
        mapEpochRemainingServiceStakingAmounts[epochNumber] = amount;
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

        Pause currentPause = paused;
        if (currentPause == Pause.DevIncentivesPaused || currentPause == Pause.AllPaused) {
            revert();
        }

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
        uint256 chainId,
        address stakingTarget,
        uint256 stakingAmount,
        bytes memory stakingPayload,
        uint256 transferAmount
    ) internal payable {
        if (chainId == 1) {
            // TODO Inject factory verification here
            // TODO Check for the numEpochs(Tokenomics) * rewardsPerSecond * numServices * epochLength(Tokenomics)
            // Get hash of target.code, check if the hash is present in the registered factory
            // Approve the OLAS amount for the staking target
            IOLAS(olas).approve(stakingTarget, stakingAmount);
            IServiceStaking(stakingTarget).deposit(stakingAmount);
            // stakingPayload is ignored
        } else {
            address targetProcessor = mapChainIdTargetProcessors[chainId];
            // TODO: mint directly or mint to dispenser and approve one by one?
            // Approve the OLAS amount for the staking target
            IOLAS(olas).transfer(targetProcessor, transferAmount);
            // TODO Inject factory verification on the L2 side
            // TODO If L2 implementation address is the same as on L1, the check can be done locally as well
            ITargetProcessor(targetProcessor).sendMessage(stakingTarget, stakingAmount, stakingPayload, transferAmount);
        }
    }

    function _distributeBatch(
        uint256[] memory chainIds,
        address[][] memory stakingTargets,
        uint256[][] memory stakingAmounts,
        bytes[] memory stakingPayloads,
        uint256[] memory transferAmounts
    ) internal payable {
        // Traverse all staking targets
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Unpack chain Id and target addresses
            uint256 chainId = chainIds[i];

            if (chainId == 1) {
                for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                    // TODO Inject factory verification here
                    // TODO Check for the numEpochs(Tokenomics) * rewardsPerSecond * numServices * epochLength(Tokenomics)
                    // Get hash of target.code, check if the hash is present in the registered factory
                    // Approve the OLAS amount for the staking target
                    IOLAS(olas).approve(stakingTargets[i][j], stakingAmounts[i][j]);
                    IServiceStaking(stakingTargets[i][j]).deposit(stakingAmounts[i][j]);
                    // stakingPayloads[i] is ignored
                }
            } else {
                address targetProcessor = mapChainIdTargetProcessors[chainId];
                // TODO: mint directly or mint to dispenser and approve one by one?
                // Approve the OLAS amount for the staking target
                IOLAS(olas).transfer(targetProcessor, transferAmounts[i]);
                // TODO Inject factory verification on the L2 side
                // TODO If L2 implementation address is the same as on L1, the check can be done locally as well
                ITargetProcessor(targetProcessor).sendMessageBatch(stakingTargets[i], stakingAmounts[i],
                    stakingPayloads[i], transferAmounts[i]);
            }
        }
    }

    function _calculateServiceStakingIncentives(
        uint256 chainId,
        address target
    ) internal returns (uint256 totalStakingAmount, uint256 totalAmountReturn) {
        // Check for the correct chain Id
        if (chainId == 0 || chainId > MAX_CHAIN_ID) {
            revert L2ChainIdNotSupported(chainId);
        }

        // Check for the zero address
        if (target == address(0)) {
            revert ZeroAddress();
        }

        // Checkpoint the vote wighting for a target on a specific chain Id
        IVoteWeighting(voteWeighting).checkpointNominee(target, chainId);

        uint256 eCounter = ITokenomicsInfo(tokenomics).epochCounter();
        // TODO: Write initial lastClaimedEpoch when the staking contract is added for voting
        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        targetChainId |= chainId << 160;
        uint256 lastClaimedEpoch = mapLastClaimedStakingServiceEpochs[targetChainId];
        // Shall not claim in the same epoch
        if (eCounter == lastClaimedEpoch) {
            revert();
        }

        // TODO: Register lastClaimedEpoch for the first time? Here or via VoteWeighting?
        for (uint256 j = lastClaimedEpoch; j < eCounter; ++j) {
            // TODO: optimize not to read several times in a row same epoch info
            // Get service staking info
            ServiceStakingPoint memory serviceStakingPoint = mapEpochServiceStakingPoints(j);

            EpochPoint memory ep = ITokenomicsInfo(tokenomics).mapEpochTokenomics(j);
            uint256 endTime = ep.endTime;

            // Get the staking weight for each epoch
            // TODO math from where we need to get the weight - endTime or endTime + WEEK
            uint256 stakingWeight = IVoteWeighting(voteWeighting).targetRelativeWeight(target,
                chainId, endTime);

            // Compare the staking weight
            uint256 stakingAmount;
            if (stakingWeight < serviceStakingPoint.serviceStakingWeightingThreshold) {
                // If vote weighting staking weight is lower than the defined threshold - return the staking amount
                stakingAmount = (serviceStakingPoint.totalServiceStakingOLAS * stakingWeight) / 1e18;
                totalAmountReturn += stakingAmount;
                // Adjust remaining service staking amounts
                mapEpochRemainingServiceStakingAmounts[j] -= stakingAmount;
            } else {
                // Otherwise, allocate staking amount to corresponding contracts
                stakingAmount = (serviceStakingPoint.totalServiceStakingOLAS * stakingWeight) / 1e18;
                if (stakingAmount > serviceStakingPoint.maxStakingAmount) {
                    // Adjust the refund amount
                    totalAmountReturn += stakingAmount - serviceStakingPoint.maxStakingAmount;
                    // Adjust the staking amount
                    stakingAmount = serviceStakingPoint.maxStakingAmount;
                }
                totalStakingAmount += stakingAmount;
                // Check that the claimed amounts are within the remaining service staking balances
                uint256 remainingServiceStakingOLAS = mapEpochRemainingServiceStakingAmounts[j];
                if (stakingAmount > remainingServiceStakingOLAS) {
                    revert();
                }
            }
        }

        // Write current epoch counter to start claiming with the next time
        mapLastClaimedStakingServiceEpochs[target] = eCounter;
    }

    // TODO: Let choose epochs to claim for - set last epoch as eCounter or as last claimed.
    // TODO: We need to come up with the solution such that we are able to return unclaimed below threshold values back to effective staking.
    function claimServiceStakingIncentives(
        uint256 chainId,
        address target,
        bytes memory payload
    ) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused) {
            revert();
        }

        // Staking amount to send as a deposit with, and the amount to return back to effective staking
        (uint256 stakingAmount, uint256 returnAmount) = _calculateServiceStakingIncentives(chainId, target);

        // Account for possible withheld OLAS amounts
        uint256 transferAmount = stakingAmount;
        uint256 withheldAmount = mapChainIdWithheldAmounts[chainId];
        if (withheldAmount >= transferAmount) {
            withheldAmount -= transferAmount;
            transferAmount = 0;
        } else {
            transferAmount -= withheldAmount;
            withheldAmount = 0;
        }
        mapChainIdWithheldAmounts[chainId] = withheldAmount;

        if (transferAmount > 0) {
            // Mint tokens to the staking target dispenser
            ITreasury(treasury).withdrawToAccount(address(this), 0, transferAmount);
        }

        // Dispense to a service staking target
        _distribute(chainId, stakingTarget, stakingAmount, stakingPayload, transferAmount);

        // TODO: Tokenomics - return totalReturnAmount into EffectiveSatking (or another additional variable tracking returns to redistribute further)
        ITokenomicsInfo(tokenomics).refundFromServiceStaking(returnAmount);

        emit ServiceStakingIncentivesClaimed(msg.sender, stakingAmount, returnAmount);

        _locked = 1;
    }

    // TODO: Let choose epochs to claim for - set last epoch as eCounter or as last claimed.
    // TODO: We need to come up with the solution such that we are able to return unclaimed below threshold values back to effective staking.
    // Ascending order of chain Ids
    function claimServiceStakingIncentivesBatch(
        uint256[] memory chainIds,
        address[][] memory stakingTargets,
        bytes[] memory stakingTargetPayloads
    ) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        if (chainIds.length != stakingTargets.length || chainIds.length != stakingTargetPayloads.length) {
            revert WrongArrayLength(chainIds.length, stakingTargets.length);
        }

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused) {
            revert();
        }

        // Staking amount across all the targets to send as a deposit
        uint256 totalStakingAmount;
        // Staking amount to return back to effective staking
        uint256 totalReturnAmount;

        // Allocate the array of staking and transfer amounts
        uint256[][] memory stakingAmounts = new uint256[][](chainIds.length);
        uint256[][] memory transferAmounts = new uint256[][](chainIds.length);

        uint256 lastChainId;
        address lastTarget;
        // Traverse all staking targets
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check that chain Ids are strictly in ascending non-repeatable order
            if (lastChainId >= chainIds[i]) {
                revert();
            }
            lastChainId = chainIds[i];

            // Staking targets must not be an empty array
            if (stakingTargets[i].length == 0) {
                revert ZeroValue();
            }

            stakingAmounts[i] = new uint256[](stakingTargets[i].length);
            transferAmounts[i] = new uint256[](stakingTargets[i].length);
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Enforce ascending non-repeatable order of targets
                if (uint256(uint160(lastTarget)) >= uint256(uint160(stakingTargets[i][j]))) {
                    revert();
                }
                lastTarget = stakingTargets[i][j];

                // Staking amount to send as a deposit with, and the amount to return back to effective staking
                (uint256 stakingAmount, uint256 returnAmount) = _calculateServiceStakingIncentives(chainIds[i],
                    stakingTargets[i][j]);

                stakingAmounts[i] += stakingAmount;
                totalReturnAmount += returnAmount;
            }

            // Account for possible withheld OLAS amounts
            transferAmounts[i] = stakingAmounts[i];
            uint256 withheldAmount = mapChainIdWithheldAmounts[chainIds[i]];
            if (withheldAmount >= transferAmounts[i]) {
                withheldAmount -= transferAmounts[i];
                transferAmounts[i] = 0;
            } else {
                transferAmounts[i] -= withheldAmount;
                withheldAmount = 0;
            }
            mapChainIdWithheldAmounts[chainIds[i]] = withheldAmount;

            // Add to the total staking amount
            totalStakingAmount += transferAmounts[i];
        }

        // TODO mint here or mint separately to each instead of a transfer
        if (totalStakingAmount > 0) {
            // Mint tokens to the staking target dispenser
            ITreasury(treasury).withdrawToAccount(address(this), 0, totalStakingAmount);
        }

        // Dispense all the service staking targets
        _distributeBatch(stakingTargets, stakingAmounts, stakingTargetPayloads, transferAmounts);

        // TODO: Tokenomics - return totalReturnAmount into EffectiveSatking (or another additional variable tracking returns to redistribute further)
        ITokenomicsInfo(tokenomics).refundFromServiceStaking(totalReturnAmount);

        emit ServiceStakingIncentivesClaimed(msg.sender, totalStakingAmount, totalReturnAmount);

        _locked = 1;
    }

    /// @dev Sets target processor contracts addresses and L2 chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 target processor contracts
    ///         and corresponding supported L2 chain Ids.
    /// @param targetProcessors Set of target processor contract addresses on L1.
    /// @param chainIds Set of corresponding L2 chain Ids.
    function setTargetProcessorChainIds(
        address[] memory targetProcessors,
        uint256[] memory chainIds
    ) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array correctness
        if (targetProcessors.length != chainIds.length) {
            revert WrongArrayLength(targetProcessors.length, chainIds.length);
        }

        // Link L1 and L2 bridge mediators, set L2 chain Ids
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check supported chain Ids on L2
            if (chainIds[i] == 0 || chainIds[i] > MAX_CHAIN_ID) {
                revert L2ChainIdNotSupported(chainIds[i]);
            }

            // Note: targetProcessors[i] might be zero if there is a need to stop processing a specific L2 chain Id
            mapChainIdTargetProcessors[chainIds[i]] = targetProcessors[i];
        }

        emit SetTargetProcessorChainIds(targetProcessors, chainIds);
    }

    function syncWithheldAmount(uint256 chainId, uint256 amount) external {
        address targetProcessor = mapChainIdTargetProcessors[chainId];

        // Check L1 Wormhole Relayer address
        if (msg.sender != targetProcessor) {
            revert TargetProcessorOnly(msg.sender, targetProcessor);
        }

        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }
}
