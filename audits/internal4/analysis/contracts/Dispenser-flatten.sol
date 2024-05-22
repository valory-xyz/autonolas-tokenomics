// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Deposit Processor interface
interface IDepositProcessor {
    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingAmount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(address target, uint256 stakingAmount, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    function sendMessageBatch(address[] memory targets, uint256[] memory stakingAmounts, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a single message to the non-EVM chain.
    function sendMessageNonEVM(bytes32 target, uint256 stakingAmount, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a batch message to the non-EVM chain.
    function sendMessageBatchNonEVM(bytes32[] memory targets, uint256[] memory stakingAmounts,
        bytes memory bridgePayload, uint256 transferAmount) external payable;

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @return Number of supported decimals.
    function getBridgingDecimals() external pure returns (uint256);
}

// ERC20 token interface
interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

// Tokenomics interface
interface ITokenomics {
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
    struct StakingPoint {
        // Amount of OLAS that funds service staking for the epoch based on the inflation schedule
        // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
        uint96 stakingAmount;
        // Max allowed service staking amount threshold
        // This value is never bigger than the stakingAmount
        uint96 maxStakingAmount;
        // Service staking vote weighting threshold
        // This number is bound by 10_000, ranging from 0 to 100% with the step of 0.01%
        uint16 minStakingWeight;
        // Service staking fraction
        // This number cannot be practically bigger than 100 as it sums up to 100% with others
        // maxBondFraction + topUpComponentFraction + topUpAgentFraction + stakingFraction <= 100%
        uint8 stakingFraction;
    }

    /// @dev Gets component / agent owner incentives and clears the balances.
    /// @notice `account` must be the owner of components / agents Ids, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `account` were provided, they will be untouched and keep accumulating.
    /// @notice Component and agent Ids must be provided in the ascending order and must not repeat.
    /// @param account Account address.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerIncentives(address account, uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp);

    /// @dev Gets tokenomics epoch counter.
    /// @return Epoch counter.
    function epochCounter() external view returns (uint32);

    /// @dev Gets epoch end time.
    /// @param epoch Epoch number.
    /// @return endTime Epoch end time.
    function getEpochEndTime(uint256 epoch) external view returns (uint256 endTime);

    /// @dev Gets tokenomics epoch service staking point.
    /// @param eCounter Epoch number.
    /// @return Staking point.
    function mapEpochStakingPoints(uint256 eCounter) external view returns (StakingPoint memory);

    /// @dev Records the amount returned back to the inflation from staking.
    /// @param amount OLAS amount returned from staking.
    function refundFromStaking(uint256 amount) external;
}

// Treasury interface
interface ITreasury {
    /// @dev Withdraws ETH and / or OLAS amounts to the requested account address.
    /// @notice Only dispenser contract can call this function.
    /// @notice Reentrancy guard is on a dispenser side.
    /// @notice Zero account address is not possible, since the dispenser contract interacts with msg.sender.
    /// @param account Account address.
    /// @param accountRewards Amount of account rewards.
    /// @param accountTopUps Amount of account top-ups.
    /// @return success True if the function execution is successful.
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external
        returns (bool success);
}

// Vote Weighting nterface
interface IVoteWeighting {
    // Nominee struct
    struct Nominee {
        bytes32 account;
        uint256 chainId;
    }

    /// @dev Gets the nominee Id by its hash.
    /// @param nomineeHash Nominee hash derived from its account address and chainId.
    /// @return Nominee Id.
    function mapNomineeIds(bytes32 nomineeHash) external returns (uint256);

    /// @dev Checkpoint to fill data for both a specific nominee and common for all nominees.
    /// @param account Address of the nominee.
    /// @param chainId Chain Id.
    function checkpointNominee(bytes32 account, uint256 chainId) external;

    /// @dev Get Nominee relative weight (not more than 1.0) normalized to 1e18 and the sum of weights.
    ///         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    ///         inflation_rate * relativeWeight / 1e18.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    /// @return Sum of nominee weights.
    function nomineeRelativeWeight(bytes32 account, uint256 chainId, uint256 time) external view returns (uint256, uint256);
}

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @dev Wrong amount received / provided.
/// @param provided Provided amount.
/// @param expected Expected amount.
error WrongAmount(uint256 provided, uint256 expected);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev The contract is paused.
error Paused();

/// @dev Incentives claim has failed.
/// @param account Account address.
/// @param reward Reward amount.
/// @param topUp Top-up amount.
error ClaimIncentivesFailed(address account, uint256 reward, uint256 topUp);

/// @dev Only the deposit processor is able to call the function.
/// @param sender Actual sender address.
/// @param depositProcessor Required deposit processor.
error DepositProcessorOnly(address sender, address depositProcessor);

/// @dev Chain Id is incorrect.
/// @param chainId Chain Id.
error WrongChainId(uint256 chainId);

// TODO Names and titles in all the deployed contracts
/// @title Dispenser - Smart contract for distributing incentives
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract Dispenser {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event VoteWeightingUpdated(address indexed voteWeighting);
    event IncentivesClaimed(address indexed owner, uint256 reward, uint256 topUp);
    event StakingIncentivesClaimed(address indexed account, uint256 stakingAmount, uint256 transferAmount,
        uint256 returnAmount);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event WithheldAmountSynced(uint256 chainId, uint256 amount);

    enum Pause {
        Unpaused,
        DevIncentivesPaused,
        StakingIncentivesPaused,
        AllPaused
    }

    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_EVM_CHAIN_ID = type(uint64).max / 2 - 36;
    // OLAS token address
    address public immutable olas;

    // Max number of epochs to claim staking incentives for
    uint256 public maxNumClaimingEpochs;
    // Max number of targets for a specific chain to claim staking incentives for
    uint256 public maxNumStakingTargets;
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
    // Retainer address in bytes32 form
    bytes32 public retainer;

    // Mapping for hash(Nominee struct) service staking pair => last claimed epochs
    mapping(bytes32 => uint256) public mapLastClaimedStakingEpochs;
    // Mapping for hash(Nominee struct) service staking pair => epoch number when the staking contract is removed
    mapping(bytes32 => uint256) public mapRemovedNomineeEpochs;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;
    // Mapping for L2 chain Id => withheld OLAS amounts
    mapping(uint256 => uint256) public mapChainIdWithheldAmounts;

    /// @dev Dispenser constructor.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    /// @param _voteWeighting Vote Weighting address.
    constructor(address _tokenomics, address _treasury, address _voteWeighting) {
        owner = msg.sender;
        _locked = 1;
        // TODO Define final behavior before deployment
        paused = Pause.StakingIncentivesPaused;

        // Check for at least one zero contract address
        if (_tokenomics == address(0) || _treasury == address(0) || _voteWeighting == address(0)) {
            revert ZeroAddress();
        }

        tokenomics = _tokenomics;
        treasury = _treasury;
        voteWeighting = _voteWeighting;
        // TODO initial max number of epochs to claim staking incentives for
        maxNumClaimingEpochs = 10;
    }

    /// @dev Checkpoints specified staking target (nominee in Vote Weighting) and gets claimed epoch counters.
    /// @param target Staking target contract address.
    /// @param chainId Corresponding chain Id.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @return firstClaimedEpoch First claimed epoch number.
    /// @return lastClaimedEpoch Last claimed epoch number (not included in claiming).
    function _checkpointNomineeAndGetClaimedEpochCounters(
        bytes32 target,
        uint256 chainId,
        uint256 numClaimedEpochs
    ) internal returns (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) {
        // Checkpoint the vote weighting for the retainer on L1
        IVoteWeighting(voteWeighting).checkpointNominee(target, chainId);

        // Get the current epoch number
        uint256 eCounter = ITokenomics(tokenomics).epochCounter();

        // Construct the nominee struct
        IVoteWeighting.Nominee memory nominee = IVoteWeighting.Nominee(target, chainId);
        // Get the nominee hash
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        // Get the first claimed epoch, which is equal to the last claiming one
        firstClaimedEpoch = mapLastClaimedStakingEpochs[nomineeHash];

        // This must never happen as the nominee gets enabled when added to Vote Weighting
        // This is only possible if the dispenser has been unset in Vote Weighting for some time
        // In that case the check is correct and those nominees must not be considered
        if (firstClaimedEpoch == 0) {
            revert ZeroValue();
        }

        // Must not claim in the ongoing epoch
        if (firstClaimedEpoch == eCounter) {
            revert Overflow(firstClaimedEpoch, eCounter - 1);
        }

        // We still need to claim for the epoch number following the one when the nominee was removed
        uint256 epochAfterRemoved = mapRemovedNomineeEpochs[nomineeHash] + 1;
        // If the nominee is not removed, its value in the map is always zero, unless removed
        // The nominee cannot be removed in the zero-th epoch by default
        if (epochAfterRemoved > 1 && firstClaimedEpoch >= epochAfterRemoved) {
            revert Overflow(firstClaimedEpoch, epochAfterRemoved - 1);
        }

        // Get a number of epochs to claim for based on the maximum number of epochs claimed
        lastClaimedEpoch = firstClaimedEpoch + numClaimedEpochs;

        // Limit last claimed epoch by the number following the nominee removal epoch
        // The condition for is lastClaimedEpoch strictly > because the lastClaimedEpoch is not included in claiming
        if (epochAfterRemoved > 1 && lastClaimedEpoch > epochAfterRemoved) {
            lastClaimedEpoch = epochAfterRemoved;
        }

        // Also limit by the current counter, if the nominee was removed in the current epoch
        if (lastClaimedEpoch > eCounter) {
            lastClaimedEpoch = eCounter;
        }

        // Write last claimed epoch counter to start claiming / retaining from the next time
        mapLastClaimedStakingEpochs[nomineeHash] = lastClaimedEpoch;
    }

    /// @dev Distributes staking incentives to a corresponding staking target.
    /// @param chainId Chain Id.
    /// @param stakingTarget Staking target corresponding to the chain Id.
    /// @param stakingAmount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function _distributeStakingIncentives(
        uint256 chainId,
        bytes32 stakingTarget,
        uint256 stakingAmount,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal {
        // Get the deposit processor contract address
        address depositProcessor = mapChainIdDepositProcessors[chainId];

        // Transfer corresponding OLAS amounts to the deposit processor
        IToken(olas).transfer(depositProcessor, transferAmount);

        if (chainId <= MAX_EVM_CHAIN_ID) {
            address stakingTargetEVM = address(uint160(uint256(stakingTarget)));
            IDepositProcessor(depositProcessor).sendMessage{value:msg.value}(stakingTargetEVM, stakingAmount,
                bridgePayload, transferAmount);
        } else {
            // Send to non-EVM
            IDepositProcessor(depositProcessor).sendMessageNonEVM{value:msg.value}(stakingTarget,
                stakingAmount, bridgePayload, transferAmount);
        }
    }

    /// @dev Distributes staking incentives to corresponding staking targets.
    /// @param chainIds Set of chain Ids.
    /// @param stakingTargets Set of staking target addresses corresponding to each chain Id.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayloads Bridge payloads (if) necessary for a specific bridge relayer depending on chain Id.
    /// @param transferAmounts Set of actual total OLAS amounts across all the targets to be transferred.
    /// @param valueAmounts Set of value amounts required to provide to some of the bridges.
    function _distributeStakingIncentivesBatch(
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        uint256[][] memory stakingAmounts,
        bytes[] memory bridgePayloads,
        uint256[] memory transferAmounts,
        uint256[] memory valueAmounts
    ) internal {
        // Traverse all staking targets
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Get the deposit processor contract address
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            // Transfer corresponding OLAS amounts to deposit processors
            IToken(olas).transfer(depositProcessor, transferAmounts[i]);

            // Find zero staking amounts
            uint256 numActualTargets;
            bool[] memory positions = new bool[](stakingTargets[i].length);
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                if (stakingAmounts[i][j] > 0) {
                    positions[j] = true;
                    ++numActualTargets;
                }
            }

            // Allocate updated arrays accounting only for nonzero staking amounts
            bytes32[] memory updatedStakingTargets = new bytes32[](numActualTargets);
            uint256[] memory updatedStakingAmounts = new uint256[](numActualTargets);
            uint256 numPos;
            for (uint256 j = 0; j < stakingTargets[j].length; ++j) {
                if (positions[j]) {
                    updatedStakingTargets[numPos] = stakingTargets[i][j];
                    updatedStakingAmounts[numPos] = stakingAmounts[i][j];
                    ++numPos;
                }
            }

            // Address conversion depending on chain Ids
            if (chainIds[i] <= MAX_EVM_CHAIN_ID) {
                // Convert to EVM addresses
                address[] memory stakingTargetsEVM = new address[](updatedStakingTargets.length);
                for (uint256 j = 0; j < updatedStakingTargets.length; ++j) {
                    stakingTargetsEVM[j] = address(uint160(uint256(updatedStakingTargets[j])));
                }

                // Send to EVM chains
                IDepositProcessor(depositProcessor).sendMessageBatch{value:valueAmounts[i]}(stakingTargetsEVM,
                    updatedStakingAmounts, bridgePayloads[i], transferAmounts[i]);
            } else {
                // Send to non-EVM chains
                IDepositProcessor(depositProcessor).sendMessageBatchNonEVM{value:valueAmounts[i]}(updatedStakingTargets,
                    updatedStakingAmounts, bridgePayloads[i], transferAmounts[i]);
            }
        }
    }

    /// @dev Checks strict ascending order of chain Ids and staking targets to ensure the absence of duplicates.
    /// @param chainIds Set of chain Ids.
    /// @notice The function is not view deliberately such that all the reverts are executed correctly.
    /// @param stakingTargets Set of staking target addresses corresponding to each chain Id.
    /// @param bridgePayloads Set of bridge payloads (if) necessary for a specific bridge relayer depending on chain Id.
    /// @param valueAmounts Set of value amounts required to provide to some of the bridges.
    function _checkOrderAndValues(
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        bytes[] memory bridgePayloads,
        uint256[] memory valueAmounts
    ) internal {
        // Check array sizes
        if (chainIds.length != stakingTargets.length) {
            revert WrongArrayLength(chainIds.length, stakingTargets.length);
        }
        if (chainIds.length != bridgePayloads.length) {
            revert WrongArrayLength(chainIds.length, bridgePayloads.length);
        }
        if (chainIds.length != valueAmounts.length) {
            revert WrongArrayLength(chainIds.length, valueAmounts.length);
        }

        uint256 lastChainId;
        uint256 totalValueAmount;
        // Traverse all chains
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check that chain Ids are strictly in ascending non-repeatable order
            // Also protects from the initial chainId == 0
            if (lastChainId >= chainIds[i]) {
                revert Overflow(lastChainId, chainIds[i] - 1);
            }
            lastChainId = chainIds[i];

            // Staking targets must not be an empty array
            if (stakingTargets[i].length == 0) {
                revert ZeroValue();
            }

            // Add to the total value amount
            totalValueAmount += valueAmounts[i];

            // Check for the maximum number of staking targets
            if (stakingTargets[i].length > maxNumStakingTargets) {
                revert Overflow(stakingTargets[i].length, maxNumStakingTargets);
            }

            bytes32 lastTarget;
            // Traverse all staking targets
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Enforce ascending non-repeatable order of targets
                // Also protects from the initial stakingTargets[i][j] == 0
                if (uint256(lastTarget) >= uint256(stakingTargets[i][j])) {
                    revert Overflow(uint256(lastTarget), uint256(stakingTargets[i][j]) - 1);
                }
                lastTarget = stakingTargets[i][j];
            }
        }

        // Check if the total transferred amount corresponds to the sum of value amounts
        if (msg.value != totalValueAmount) {
            revert WrongAmount(msg.value, totalValueAmount);
        }
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
    /// @param _voteWeighting Vote Weighting address.
    function changeManagers(address _tokenomics, address _treasury, address _voteWeighting) external {
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

        // Change Vote Weighting contract address
        if (_voteWeighting != address(0)) {
            voteWeighting = _voteWeighting;
            emit VoteWeightingUpdated(_voteWeighting);
        }
    }

    /// @dev Changes a retainer address.
    /// @notice Prerequisites:
    ///         1. Remove retainer from the nominees set (Vote Weighting);
    ///         2. Call retain() up until the epoch number following the removal epoch number.
    ///         Or, have a zero address retainer for the very first time.
    /// @param newRetainer New retainer address.
    function changeRetainer(bytes32 newRetainer) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newRetainer == 0) {
            revert ZeroAddress();
        }

        // Check if the new retainer exists as a nominee
        IVoteWeighting.Nominee memory nominee = IVoteWeighting.Nominee(newRetainer, block.chainid);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        uint256 id = IVoteWeighting(voteWeighting).mapNomineeIds(nomineeHash);
        if (id == 0) {
            revert ZeroValue();
        }

        // Get the current retainer nominee hash
        bytes32 currentRetainer = retainer;
        // Check that current retainer has a nonzero address
        if (currentRetainer != 0) {
            // Get current retainer nominee hash
            nominee = IVoteWeighting.Nominee(currentRetainer, block.chainid);
            nomineeHash = keccak256(abi.encode(nominee));

            // The current retainer must be removed from nominees before switching to a new one
            uint256 removedEpochCounter = mapRemovedNomineeEpochs[nomineeHash];
            // Check that the retainer is removed
            if (removedEpochCounter == 0) {
                revert ZeroValue();
            }

            // Check that all the funds have been retained for previous epochs
            // The retainer must be removed in one of previous epochs
            uint256 lastClaimedEpoch = mapLastClaimedStakingEpochs[nomineeHash];
            if (removedEpochCounter >= lastClaimedEpoch) {
                revert Overflow(removedEpochCounter, lastClaimedEpoch - 1);
            }
        }

        retainer = newRetainer;
    }

    /// @dev Changes staking params by the DAO.
    /// @param _maxNumClaimingEpochs Maximum number of epochs to claim staking incentives for.
    /// @param _maxNumStakingTargets Maximum number of staking targets available to claim for on a single chain Id.
    function changeStakingParams(uint256 _maxNumClaimingEpochs, uint256 _maxNumStakingTargets) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (_maxNumClaimingEpochs > 0) {
            maxNumClaimingEpochs = _maxNumClaimingEpochs;
        }

        if (_maxNumStakingTargets > 0) {
            maxNumStakingTargets = _maxNumStakingTargets;
        }
    }

    /// @dev Records nominee starting epoch number.
    /// @param nomineeHash Nominee hash.
    function addNominee(bytes32 nomineeHash) external {
        // Check for the contract ownership
        if (msg.sender != voteWeighting) {
            revert ManagerOnly(msg.sender, voteWeighting);
        }

        mapLastClaimedStakingEpochs[nomineeHash] = ITokenomics(tokenomics).epochCounter();
    }

    /// @dev Records nominee removal epoch number.
    /// @param nomineeHash Nominee hash.
    function removeNominee(bytes32 nomineeHash) external {
        // Check for the contract ownership
        if (msg.sender != voteWeighting) {
            revert ManagerOnly(msg.sender, voteWeighting);
        }

        mapRemovedNomineeEpochs[nomineeHash] = ITokenomics(tokenomics).epochCounter();
    }

    /// @dev Retains staking incentives according to the retainer address to return it back to the staking inflation.
    function retain() external {
        // Go over epochs and retain funds to return back to the tokenomics
        bytes32 localRetainer = retainer;

        // Check for zero retainer address
        if (localRetainer == 0) {
            revert ZeroAddress();
        }

        (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) =
            _checkpointNomineeAndGetClaimedEpochCounters(localRetainer, block.chainid, maxNumClaimingEpochs);

        uint256 totalReturnAmount;

        // Traverse all the claimed epochs
        for (uint256 j = firstClaimedEpoch; j < lastClaimedEpoch; ++j) {
            // Get service staking info
            ITokenomics.StakingPoint memory stakingPoint =
                ITokenomics(tokenomics).mapEpochStakingPoints(j);

            // Get epoch end time
            uint256 endTime = ITokenomics(tokenomics).getEpochEndTime(j);

            // Get the staking weight for each epoch
            (uint256 stakingWeight, ) =
                IVoteWeighting(voteWeighting).nomineeRelativeWeight(localRetainer, block.chainid, endTime);

            totalReturnAmount += stakingPoint.stakingAmount * stakingWeight;
        }
        totalReturnAmount /= 1e18;
    }

    /// @dev Claims incentives for the owner of components / agents.
    /// @notice `msg.sender` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `msg.sender` were provided, they will be untouched and keep accumulating.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function claimOwnerIncentives(
        uint256[] memory unitTypes,
        uint256[] memory unitIds
    ) external returns (uint256 reward, uint256 topUp) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        Pause currentPause = paused;
        if (currentPause == Pause.DevIncentivesPaused || currentPause == Pause.AllPaused) {
            revert Paused();
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

    /// @dev Calculates staking incentives for a specific staking target.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @param chainId Chain Id.
    /// @param stakingTarget Staking target corresponding to the chain Id.
    /// @param bridgingDecimals Number of supported token decimals able to be transferred across the bridge.
    /// @return totalStakingAmount Total staking amount across all the claimed epochs.
    /// @return totalReturnAmount Total return amount across all the claimed epochs.
    function calculateStakingIncentives(
        uint256 numClaimedEpochs,
        uint256 chainId,
        bytes32 stakingTarget,
        uint256 bridgingDecimals
    ) public returns (uint256 totalStakingAmount, uint256 totalReturnAmount) {
        // Check for the correct chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }

        // Check for the zero address
        if (stakingTarget == 0) {
            revert ZeroAddress();
        }

        (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) =
            _checkpointNomineeAndGetClaimedEpochCounters(stakingTarget, chainId, numClaimedEpochs);

        // Traverse all the claimed epochs
        for (uint256 j = firstClaimedEpoch; j < lastClaimedEpoch; ++j) {
            // TODO: optimize not to read several times in a row same epoch info
            // Get service staking info
            ITokenomics.StakingPoint memory stakingPoint =
                ITokenomics(tokenomics).mapEpochStakingPoints(j);

            uint256 endTime = ITokenomics(tokenomics).getEpochEndTime(j);

            // Get the staking weight for each epoch and the total weight
            // Epoch endTime is used to get the weights info, since otherwise there is a risk of having votes
            // accounted for from the next epoch
            // totalWeightSum is the overall veOLAS power (bias) across all the voting nominees
            (uint256 stakingWeight, uint256 totalWeightSum) =
                IVoteWeighting(voteWeighting).nomineeRelativeWeight(stakingTarget, chainId, endTime);

            uint256 stakingAmount;
            uint256 returnAmount;

            // Adjust the inflation by the maximum amount of veOLAS voted for service staking contracts
            // If veOLAS power is lower, it reflects the maximum amount of OLAS allocated for staking
            // such that all the inflation is not distributed for a minimal veOLAS power
            uint256 availableStakingAmount = stakingPoint.stakingAmount;
            uint256 stakingDiff = availableStakingAmount - totalWeightSum;
            if (stakingDiff > 0) {
                availableStakingAmount = totalWeightSum;
            }

            // TODO Optimize division by 1e18 after summing all staking / return up
            // Compare the staking weight
            if (stakingWeight < stakingPoint.minStakingWeight) {
                // If vote weighting staking weight is lower than the defined threshold - return the staking amount
                returnAmount = (stakingDiff + availableStakingAmount) * stakingWeight;
                returnAmount /= 1e18;
                totalReturnAmount += returnAmount;
            } else {
                // Otherwise, allocate staking amount to corresponding contracts
                stakingAmount = (availableStakingAmount * stakingWeight) / 1e18;
                returnAmount = (stakingDiff * stakingWeight) / 1e18;
                if (stakingAmount > stakingPoint.maxStakingAmount) {
                    // Adjust the return amount
                    returnAmount += stakingAmount - stakingPoint.maxStakingAmount;
                    totalReturnAmount += returnAmount;
                    // Adjust the staking amount
                    stakingAmount = stakingPoint.maxStakingAmount;
                }

                // Normalize staking amount if there is a bridge decimals limiting condition
                // Note: only OLAS decimals must be considered
                if (bridgingDecimals < 18) {
                    uint256 normalizedStakingAmount = stakingAmount / (10 ** (18 - bridgingDecimals));
                    normalizedStakingAmount *= 10 ** (18 - bridgingDecimals);
                    // Update return amounts
                    returnAmount += stakingAmount - normalizedStakingAmount;
                    // Downsize staking amount to a specified number of bridging decimals
                    stakingAmount = normalizedStakingAmount;
                }

                totalStakingAmount += stakingAmount;
            }
        }
    }

    /// @dev Claims staking incentives for a specific staking target.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @param chainId Chain Id.
    /// @param stakingTarget Staking target corresponding to the chain Id.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    function claimStakingIncentives(
        uint256 numClaimedEpochs,
        uint256 chainId,
        bytes32 stakingTarget,
        bytes memory bridgePayload
    ) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check the number of claimed epochs
        if (numClaimedEpochs > maxNumClaimingEpochs) {
            revert Overflow(numClaimedEpochs, maxNumClaimingEpochs);
        }

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused) {
            revert Paused();
        }

        // Get deposit processor bridging decimals corresponding to a chain Id
        address depositProcessor = mapChainIdDepositProcessors[chainId];
        uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

        // Get the staking amount to send as a deposit with, and the amount to return back to staking inflation
        (uint256 stakingAmount, uint256 returnAmount) = calculateStakingIncentives(numClaimedEpochs, chainId,
            stakingTarget, bridgingDecimals);

        // Refund returned amount back to tokenomics inflation
        if (returnAmount > 0) {
            ITokenomics(tokenomics).refundFromStaking(returnAmount);
        }

        uint256 transferAmount;

        // Check if staking amount is deposited
        if (stakingAmount > 0) {
            transferAmount = stakingAmount;
            // Account for possible withheld OLAS amounts
            // Note: in case of normalized staking amounts with bridging decimals, this is correctly managed
            // as normalized amounts are returned from another side
            uint256 withheldAmount = mapChainIdWithheldAmounts[chainId];
            if (withheldAmount > 0) {
                // If withheld amount is enough to cover all the staking amounts, the transfer of OLAS is not needed
                if (withheldAmount >= transferAmount) {
                    withheldAmount -= transferAmount;
                    transferAmount = 0;
                } else {
                    // Otherwise, reduce the transfer of tokens for the OLAS withheld amount
                    transferAmount -= withheldAmount;
                    withheldAmount = 0;
                }
                mapChainIdWithheldAmounts[chainId] = withheldAmount;
            }

            // Check if minting is needed as the actual OLAS transfer is required
            if (transferAmount > 0) {
                uint256 balanceBefore = IToken(olas).balanceOf(address(this));

                // Mint tokens to self in order to distribute to the staking deposit processor
                ITreasury(treasury).withdrawToAccount(address(this), 0, transferAmount);

                // Check the balance after the mint
                if (IToken(olas).balanceOf(address(this)) - balanceBefore != transferAmount) {
                    revert WrongAmount(IToken(olas).balanceOf(address(this)) - balanceBefore, transferAmount);
                }
            }

            // Dispense to a service staking target
            _distributeStakingIncentives(chainId, stakingTarget, stakingAmount, bridgePayload, transferAmount);
        }

        emit StakingIncentivesClaimed(msg.sender, stakingAmount, transferAmount, returnAmount);

        _locked = 1;
    }

    /// @dev Claims staking incentives for sets staking targets corresponding to a set of chain Ids.
    /// @notice Mind the gas spending depending on the max number of numChains * numTargetsPerChain * numEpochs to claim.
    ///         Also note that in order to avoid duplicates, there is a requirement for a strict ascending order
    ///         of chain Ids and stakingTargets.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @param chainIds Set of chain Ids.
    /// @param stakingTargets Set of staking target addresses corresponding to each chain Id.
    /// @param bridgePayloads Set of bridge payloads (if) necessary for a specific bridge relayer depending on chain Id.
    /// @param valueAmounts Set of value amounts required to provide to some of the bridges.
    function claimStakingIncentivesBatch(
        uint256 numClaimedEpochs,
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        bytes[] memory bridgePayloads,
        uint256[] memory valueAmounts
    ) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        _checkOrderAndValues(chainIds, stakingTargets, bridgePayloads, valueAmounts);

        // Check the number of claimed epochs
        if (numClaimedEpochs > maxNumClaimingEpochs) {
            revert Overflow(numClaimedEpochs, maxNumClaimingEpochs);
        }

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused) {
            revert Paused();
        }

        // Total staking amounts
        // 0: Staking amount across all the targets to send as a deposit
        // 1: Actual OLAS transfer amount across all the targets
        // 2: Staking amount to return back to effective staking
        uint256[] memory totalAmounts = new uint256[](3);

        // Allocate the array of staking and transfer amounts
        uint256[][] memory stakingAmounts = new uint256[][](chainIds.length);
        uint256[] memory transferAmounts = new uint256[](chainIds.length);

        // Traverse all chains
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Get deposit processor bridging decimals corresponding to a chain Id
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

            stakingAmounts[i] = new uint256[](stakingTargets[i].length);
            // Traverse all staking targets
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Get the staking amount to send as a deposit with, and the amount to return back to staking inflation
                (uint256 stakingAmount, uint256 returnAmount) = calculateStakingIncentives(numClaimedEpochs, chainIds[i],
                    stakingTargets[i][j], bridgingDecimals);

                stakingAmounts[i][j] = stakingAmount;
                transferAmounts[i] += stakingAmount;
                totalAmounts[0] += stakingAmount;
                totalAmounts[2] += returnAmount;
            }

            // Account for possible withheld OLAS amounts
            uint256 withheldAmount = mapChainIdWithheldAmounts[chainIds[i]];
            if (withheldAmount > 0) {
                if (withheldAmount >= transferAmounts[i]) {
                    withheldAmount -= transferAmounts[i];
                    transferAmounts[i] = 0;
                } else {
                    transferAmounts[i] -= withheldAmount;
                    withheldAmount = 0;
                }
                mapChainIdWithheldAmounts[chainIds[i]] = withheldAmount;
            }

            // Add to the total transfer amount
            totalAmounts[1] += transferAmounts[i];
        }

        // Refund returned amount back to tokenomics inflation
        if (totalAmounts[2] > 0) {
            ITokenomics(tokenomics).refundFromStaking(totalAmounts[2]);
        }

        // Check if minting is needed as the actual OLAS transfer is required
        if (totalAmounts[1] > 0) {
            uint256 balanceBefore = IToken(olas).balanceOf(address(this));

            // Mint tokens to self in order to distribute to staking deposit processors
            ITreasury(treasury).withdrawToAccount(address(this), 0, totalAmounts[1]);

            // Check the balance after the mint
            if (IToken(olas).balanceOf(address(this)) - balanceBefore != totalAmounts[1]) {
                revert WrongAmount(IToken(olas).balanceOf(address(this)) - balanceBefore, totalAmounts[1]);
            }
        }

        // Dispense all the service staking targets
        _distributeStakingIncentivesBatch(chainIds, stakingTargets, stakingAmounts, bridgePayloads, transferAmounts,
            valueAmounts);

        emit StakingIncentivesClaimed(msg.sender, totalAmounts[0], totalAmounts[1], totalAmounts[2]);

        _locked = 1;
    }

    /// @dev Sets deposit processor contracts addresses and L2 chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 deposit processor contracts
    ///         and corresponding supported L2 chain Ids.
    /// @param depositProcessors Set of deposit processor contract addresses on L1.
    /// @param chainIds Set of corresponding L2 chain Ids.
    function setDepositProcessorChainIds(
        address[] memory depositProcessors,
        uint256[] memory chainIds
    ) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array correctness
        if (depositProcessors.length != chainIds.length) {
            revert WrongArrayLength(depositProcessors.length, chainIds.length);
        }

        // Link L1 and L2 bridge mediators, set L2 chain Ids
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check supported chain Ids on L2
            if (chainIds[i] == 0) {
                revert ZeroValue();
            }

            // Note: depositProcessors[i] might be zero if there is a need to stop processing a specific L2 chain Id
            mapChainIdDepositProcessors[chainIds[i]] = depositProcessors[i];
        }

        emit SetDepositProcessorChainIds(depositProcessors, chainIds);
    }

    /// @dev Syncs the withheld amount according to the data received from L2.
    /// @notice Only a corresponding chain Id deposit processor is able to communicate the withheld amount data.
    /// @param chainId L2 chain Id the withheld amount data is communicated from.
    /// @param amount Withheld OLAS token amount.
    function syncWithheldAmount(uint256 chainId, uint256 amount) external {
        address depositProcessor = mapChainIdDepositProcessors[chainId];

        // Check L1 Wormhole Relayer address
        if (msg.sender != depositProcessor) {
            revert DepositProcessorOnly(msg.sender, depositProcessor);
        }

        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }

    /// @dev Syncs the withheld amount manually by the DAO in order to restore the data that was not delivered from L2.
    /// @notice The possible bridge failure scenario that requires to act via the DAO vote includes:
    ///         - Message from L2 to L1 fails: need to call this function.
    /// @param chainId L2 chain Id.
    /// @param amount Withheld amount that was not delivered from L2.
    function syncWithheldAmountMaintenance(uint256 chainId, uint256 amount) external {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // The sync must never happen for the L1 chain Id itself, as dispenser exists strictly on L1-s
        if (chainId == block.chainid) {
            revert WrongChainId(chainId);
        }

        // Get bridging decimals for a specified chain Id
        address depositProcessor = mapChainIdDepositProcessors[chainId];
        uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

        // Normalize the synced withheld amount via maintenance is correct
        if (bridgingDecimals < 18) {
            uint256 normalizedAmount = amount / (10 ** (18 - bridgingDecimals));
            normalizedAmount *= 10 ** (18 - bridgingDecimals);
            // Downsize staking amount to a specified number of bridging decimals
            amount = normalizedAmount;
        }

        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }

    /// @dev Sets the pause state.
    /// @param pauseState Pause state.
    function setPause(Pause pauseState) external {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = pauseState;
    }
}
