// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Deposit Processor interface
interface IDepositProcessor {
    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingIncentive Corresponding staking incentive.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(address target, uint256 stakingIncentive, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    function sendMessageBatch(address[] memory targets, uint256[] memory stakingIncentives, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a single message to the non-EVM chain.
    /// @param target Staking target addresses.
    /// @param stakingIncentive Corresponding staking incentive.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessageNonEVM(bytes32 target, uint256 stakingIncentive, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a batch message to the non-EVM chain.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    function sendMessageBatchNonEVM(bytes32[] memory targets, uint256[] memory stakingIncentives,
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
        uint96 stakingIncentive;
        // Max allowed service staking incentive threshold
        // This value is never bigger than the stakingIncentive
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

    /// @dev Gets tokenomics epoch length.
    /// @return Epoch length.
    function epochLen() external view returns (uint32);

    /// @dev Gets epoch end time.
    /// @param epoch Epoch number.
    /// @return endTime Epoch end time.
    function getEpochEndTime(uint256 epoch) external view returns (uint256 endTime);

    /// @dev Gets tokenomics epoch service staking point.
    /// @param eCounter Epoch number.
    /// @return Staking point.
    function mapEpochStakingPoints(uint256 eCounter) external view returns (StakingPoint memory);

    /// @dev Records amount returned back from staking to the inflation.
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

    /// @dev Returns the paused state.
    /// @return Paused state.
    function paused() external returns (uint8);
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

/// @dev Account address is incorrect.
/// @param account Account address.
error WrongAccount(bytes32 account);

/// @title Dispenser - Smart contract for distributing incentives
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract Dispenser {
    enum Pause {
        Unpaused,
        DevIncentivesPaused,
        StakingIncentivesPaused,
        AllPaused
    }

    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event VoteWeightingUpdated(address indexed voteWeighting);
    event StakingParamsUpdated(uint256 maxNumClaimingEpochs, uint256 maxNumStakingTargets);
    event IncentivesClaimed(address indexed owner, uint256 reward, uint256 topUp);
    event StakingIncentivesClaimed(address indexed account, uint256 stakingIncentive, uint256 transferAmount,
        uint256 returnAmount);
    event Retained(address indexed account, uint256 returnAmount);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event WithheldAmountSynced(uint256 chainId, uint256 amount, uint256 updatedWithheldAmount);
    event PauseDispenser(Pause pauseState);

    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_EVM_CHAIN_ID = type(uint64).max / 2 - 36;
    // OLAS token address
    address public immutable olas;
    // Retainer address in bytes32 form
    bytes32 public immutable retainer;
    // Retainer hash of a Nominee struct composed of retainer address with block.chainid
    bytes32 public immutable retainerHash;

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

    // Mapping for hash(Nominee struct) service staking pair => last claimed epochs
    mapping(bytes32 => uint256) public mapLastClaimedStakingEpochs;
    // Mapping for hash(Nominee struct) service staking pair => epoch number when the staking contract is removed
    mapping(bytes32 => uint256) public mapRemovedNomineeEpochs;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;
    // Mapping for L2 chain Id => withheld OLAS amounts
    mapping(uint256 => uint256) public mapChainIdWithheldAmounts;

    /// @dev Dispenser constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    /// @param _voteWeighting Vote Weighting address.
    constructor(
        address _olas,
        address _tokenomics,
        address _treasury,
        address _voteWeighting,
        bytes32 _retainer,
        uint256 _maxNumClaimingEpochs,
        uint256 _maxNumStakingTargets
    ) {
        owner = msg.sender;
        _locked = 1;
        // TODO Define final behavior before deployment
        paused = Pause.StakingIncentivesPaused;

        // Check for at least one zero contract address
        if (_olas == address(0) || _tokenomics == address(0) || _treasury == address(0) ||
            _voteWeighting == address(0) || _retainer == 0) {
            revert ZeroAddress();
        }

        // Check for zero value staking parameters
        if (_maxNumClaimingEpochs == 0 || _maxNumStakingTargets == 0) {
            revert ZeroValue();
        }

        olas = _olas;
        tokenomics = _tokenomics;
        treasury = _treasury;
        voteWeighting = _voteWeighting;

        retainer = _retainer;
        retainerHash = keccak256(abi.encode(IVoteWeighting.Nominee(retainer, block.chainid)));
        maxNumClaimingEpochs = _maxNumClaimingEpochs;
        maxNumStakingTargets = _maxNumStakingTargets;
    }

    /// @dev Checkpoints specified staking target (nominee in Vote Weighting) and gets claimed epoch counters.
    /// @param nomineeHash Hash of a Nominee(stakingTarget, chainId).
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @return firstClaimedEpoch First claimed epoch number.
    /// @return lastClaimedEpoch Last claimed epoch number (not included in claiming).
    function _checkpointNomineeAndGetClaimedEpochCounters(
        bytes32 nomineeHash,
        uint256 numClaimedEpochs
    ) internal returns (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) {
        // Get the current epoch number
        uint256 eCounter = ITokenomics(tokenomics).epochCounter();

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
    }

    /// @dev Distributes staking incentives to a corresponding staking target.
    /// @param chainId Chain Id.
    /// @param stakingTarget Staking target corresponding to the chain Id.
    /// @param stakingIncentive Corresponding staking incentive.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function _distributeStakingIncentives(
        uint256 chainId,
        bytes32 stakingTarget,
        uint256 stakingIncentive,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal {
        // Get the deposit processor contract address
        address depositProcessor = mapChainIdDepositProcessors[chainId];

        // Transfer corresponding OLAS amounts to the deposit processor
        if (transferAmount > 0) {
            IToken(olas).transfer(depositProcessor, transferAmount);
        }

        if (chainId <= MAX_EVM_CHAIN_ID) {
            address stakingTargetEVM = address(uint160(uint256(stakingTarget)));
            IDepositProcessor(depositProcessor).sendMessage{value:msg.value}(stakingTargetEVM, stakingIncentive,
                bridgePayload, transferAmount);
        } else {
            // Send to non-EVM
            IDepositProcessor(depositProcessor).sendMessageNonEVM{value:msg.value}(stakingTarget,
                stakingIncentive, bridgePayload, transferAmount);
        }
    }

    /// @dev Distributes staking incentives to corresponding staking targets.
    /// @param chainIds Set of chain Ids.
    /// @param stakingTargets Set of staking target addresses corresponding to each chain Id.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayloads Bridge payloads (if) necessary for a specific bridge relayer depending on chain Id.
    /// @param transferAmounts Set of actual total OLAS amounts across all the targets to be transferred.
    /// @param valueAmounts Set of value amounts required to provide to some of the bridges.
    function _distributeStakingIncentivesBatch(
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        uint256[][] memory stakingIncentives,
        bytes[] memory bridgePayloads,
        uint256[] memory transferAmounts,
        uint256[] memory valueAmounts
    ) internal {
        // Traverse all staking targets
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Get the deposit processor contract address
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];

            // Transfer corresponding OLAS amounts to deposit processors
            if (transferAmounts[i] > 0) {
                IToken(olas).transfer(depositProcessor, transferAmounts[i]);
            }

            // Find zero staking incentives
            uint256 numActualTargets;
            bool[] memory positions = new bool[](stakingTargets[i].length);
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                if (stakingIncentives[i][j] > 0) {
                    positions[j] = true;
                    ++numActualTargets;
                }
            }

            // Allocate updated arrays accounting only for nonzero staking incentives
            bytes32[] memory updatedStakingTargets = new bytes32[](numActualTargets);
            uint256[] memory updatedStakingAmounts = new uint256[](numActualTargets);
            uint256 numPos;
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                if (positions[j]) {
                    updatedStakingTargets[numPos] = stakingTargets[i][j];
                    updatedStakingAmounts[numPos] = stakingIncentives[i][j];
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
                revert WrongChainId(chainIds[i]);
            }
            lastChainId = chainIds[i];

            // Staking targets must not be an empty array
            if (stakingTargets[i].length == 0) {
                revert ZeroValue();
            }

            // Add to the total value amount
            totalValueAmount += valueAmounts[i];

            // Check for the maximum number of staking targets
            uint256 localMaxNumStakingTargets = maxNumStakingTargets;
            if (stakingTargets[i].length > localMaxNumStakingTargets) {
                revert Overflow(stakingTargets[i].length, localMaxNumStakingTargets);
            }

            bytes32 lastTarget;
            // Traverse all staking targets
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Enforce ascending non-repeatable order of targets
                // Also protects from the initial stakingTargets[i][j] == 0
                if (uint256(lastTarget) >= uint256(stakingTargets[i][j])) {
                    revert WrongAccount(stakingTargets[i][j]);
                }
                lastTarget = stakingTargets[i][j];
            }
        }

        // Check if the total transferred amount corresponds to the sum of value amounts
        if (msg.value != totalValueAmount) {
            revert WrongAmount(msg.value, totalValueAmount);
        }
    }

    /// @dev Calculates staking incentives for sets of staking targets corresponding to a set of chain Ids.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @param chainIds Set of chain Ids.
    /// @param stakingTargets Set of staking target addresses corresponding to each chain Id.
    /// @return totalAmounts Total calculated amounts: staking, transfer, return.
    /// @return stakingIncentives Sets of staking incentives.
    /// @return transferAmounts Set of transfer amounts.
    function _calculateStakingIncentivesBatch(
        uint256 numClaimedEpochs,
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets
    ) internal returns (
        uint256[] memory totalAmounts,
        uint256[][] memory stakingIncentives,
        uint256[] memory transferAmounts
    ) {
        // Total staking incentives
        // 0: Staking incentive across all the targets to send as a deposit
        // 1: Actual OLAS transfer amount across all the targets
        // 2: Staking incentive to return back to staking inflation
        totalAmounts = new uint256[](3);

        // Allocate the array of staking and transfer amounts
        stakingIncentives = new uint256[][](chainIds.length);
        transferAmounts = new uint256[](chainIds.length);

        // Traverse all chains
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Get deposit processor bridging decimals corresponding to a chain Id
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

            stakingIncentives[i] = new uint256[](stakingTargets[i].length);
            // Traverse all staking targets
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Get the staking incentive to send as a deposit with, and the amount to return back to staking inflation
                (uint256 stakingIncentive, uint256 returnAmount, uint256 lastClaimedEpoch, bytes32 nomineeHash) =
                    calculateStakingIncentives(numClaimedEpochs, chainIds[i], stakingTargets[i][j], bridgingDecimals);

                // Write last claimed epoch counter to start claiming from the next time
                mapLastClaimedStakingEpochs[nomineeHash] = lastClaimedEpoch;

                stakingIncentives[i][j] = stakingIncentive;
                transferAmounts[i] += stakingIncentive;
                totalAmounts[0] += stakingIncentive;
                totalAmounts[2] += returnAmount;
            }

            // Account for possible withheld OLAS amounts
            if (transferAmounts[i] > 0) {
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
            }

            // Add to the total transfer amount
            totalAmounts[1] += transferAmounts[i];
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

    /// @dev Changes staking params by the DAO.
    /// @param _maxNumClaimingEpochs Maximum number of epochs to claim staking incentives for.
    /// @param _maxNumStakingTargets Maximum number of staking targets available to claim for on a single chain Id.
    function changeStakingParams(uint256 _maxNumClaimingEpochs, uint256 _maxNumStakingTargets) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check if values are zero
        if (_maxNumClaimingEpochs == 0 || _maxNumStakingTargets == 0) {
            revert ZeroValue();
        }

        maxNumClaimingEpochs = _maxNumClaimingEpochs;
        maxNumStakingTargets = _maxNumStakingTargets;

        emit StakingParamsUpdated(_maxNumClaimingEpochs, _maxNumStakingTargets);
    }

    /// @dev Sets deposit processor contracts addresses and L2 chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 deposit processor contracts
    ///         and corresponding supported L2 chain Ids.
    /// @param depositProcessors Set of deposit processor contract addresses on L1.
    /// @param chainIds Set of corresponding L2 chain Ids.
    function setDepositProcessorChainIds(address[] memory depositProcessors, uint256[] memory chainIds) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array length correctness
        if (depositProcessors.length == 0 || depositProcessors.length != chainIds.length) {
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

    /// @dev Records nominee starting epoch number.
    /// @param nomineeHash Nominee hash.
    function addNominee(bytes32 nomineeHash) external {
        // Check for the contract ownership
        if (msg.sender != voteWeighting) {
            revert ManagerOnly(msg.sender, voteWeighting);
        }

        // Check for the paused state
        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused ||
            ITreasury(treasury).paused() == 2) {
            revert Paused();
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

        // Check for the retainer hash
        if (retainerHash == nomineeHash) {
            revert WrongAccount(retainer);
        }

        // Get the epoch counter
        uint256 eCounter = ITokenomics(tokenomics).epochCounter();

        // Get the previous epoch end time
        uint256 endTime = ITokenomics(tokenomics).getEpochEndTime(eCounter - 1);

        // Get the epoch length
        uint256 epochLen = ITokenomics(tokenomics).epochLen();

        // Check that there is more than one week before the end of the ongoing epoch
        uint256 maxAllowedTime = endTime + epochLen - 1 weeks;
        if (block.timestamp >= maxAllowedTime) {
            revert Overflow(block.timestamp, maxAllowedTime);
        }

        // Set the removed nominee epoch number
        mapRemovedNomineeEpochs[nomineeHash] = eCounter;
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

        // Check for the paused state
        Pause currentPause = paused;
        if (currentPause == Pause.DevIncentivesPaused || currentPause == Pause.AllPaused ||
            ITreasury(treasury).paused() == 2) {
            revert Paused();
        }

        // Calculate incentives
        (reward, topUp) = ITokenomics(tokenomics).accountOwnerIncentives(msg.sender, unitTypes, unitIds);

        bool success;
        // Request treasury to transfer funds to msg.sender if reward > 0 or topUp > 0
        if ((reward + topUp) > 0) {
            // Get the current OLAS balance
            uint256 balanceBefore;
            if (topUp > 0) {
                balanceBefore = IToken(olas).balanceOf(msg.sender);
            }

            success = ITreasury(treasury).withdrawToAccount(msg.sender, reward, topUp);

            // Check the balance after the OLAS mint, if applicable
            if (topUp > 0){
                uint256 balanceDiff = IToken(olas).balanceOf(msg.sender) - balanceBefore;
                if (balanceDiff != topUp) {
                    revert WrongAmount(balanceDiff, topUp);
                }
            }
        }

        // Check if the claim is successful and has at least one non-zero incentive.
        if (!success) {
            revert ClaimIncentivesFailed(msg.sender, reward, topUp);
        }

        emit IncentivesClaimed(msg.sender, reward, topUp);

        _locked = 1;
    }

    /// @dev Calculates staking incentives for a specific staking target.
    /// @notice Call this function via staticcall in order not to write in the nominee checkpoint map.
    /// @param numClaimedEpochs Specified number of claimed epochs.
    /// @param chainId Chain Id.
    /// @param stakingTarget Staking target corresponding to the chain Id.
    /// @param bridgingDecimals Number of supported token decimals able to be transferred across the bridge.
    /// @return totalStakingIncentive Total staking incentive across all the claimed epochs.
    /// @return totalReturnAmount Total return amount across all the claimed epochs.
    /// @return lastClaimedEpoch Last claimed epoch number (not included in claiming).
    /// @return nomineeHash Hash of a Nominee(stakingTarget, chainId).
    function calculateStakingIncentives(
        uint256 numClaimedEpochs,
        uint256 chainId,
        bytes32 stakingTarget,
        uint256 bridgingDecimals
    ) public returns (
        uint256 totalStakingIncentive,
        uint256 totalReturnAmount,
        uint256 lastClaimedEpoch,
        bytes32 nomineeHash
    ) {
        // Check for the correct chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }

        // Check for the zero address
        if (stakingTarget == 0) {
            revert ZeroAddress();
        }

        // Get the nominee hash
        nomineeHash = keccak256(abi.encode(IVoteWeighting.Nominee(stakingTarget, chainId)));

        uint256 firstClaimedEpoch;
        (firstClaimedEpoch, lastClaimedEpoch) =
            _checkpointNomineeAndGetClaimedEpochCounters(nomineeHash, numClaimedEpochs);

        // Checkpoint the vote weighting for the retainer on L1
        IVoteWeighting(voteWeighting).checkpointNominee(stakingTarget, chainId);

        // Traverse all the claimed epochs
        for (uint256 j = firstClaimedEpoch; j < lastClaimedEpoch; ++j) {
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

            uint256 stakingIncentive;
            uint256 returnAmount;

            // Adjust the inflation by the maximum amount of veOLAS voted for service staking contracts
            // If veOLAS power is lower, it reflects the maximum amount of OLAS allocated for staking
            // such that all the inflation is not distributed for a minimal veOLAS power
            uint256 availableStakingAmount = stakingPoint.stakingIncentive;
            uint256 stakingDiff = availableStakingAmount - totalWeightSum;
            if (stakingDiff > 0) {
                availableStakingAmount = totalWeightSum;
            }

            // Compare the staking weight
            // 100% = 1e18, in order to compare with minStakingWeight we need to bring it from the range of 0 .. 10_000
            if (stakingWeight < uint256(stakingPoint.minStakingWeight) * 1e14) {
                // If vote weighting staking weight is lower than the defined threshold - return the staking incentive
                returnAmount = ((stakingDiff + availableStakingAmount) * stakingWeight) / 1e18;
                totalReturnAmount += returnAmount;
            } else {
                // Otherwise, allocate staking incentive to corresponding contracts
                stakingIncentive = (availableStakingAmount * stakingWeight) / 1e18;
                returnAmount = (stakingDiff * stakingWeight) / 1e18;
                if (stakingIncentive > stakingPoint.maxStakingAmount) {
                    // Adjust the return amount
                    returnAmount += stakingIncentive - stakingPoint.maxStakingAmount;
                    totalReturnAmount += returnAmount;
                    // Adjust the staking incentive
                    stakingIncentive = stakingPoint.maxStakingAmount;
                }

                // Normalize staking incentive if there is a bridge decimals limiting condition
                // Note: only OLAS decimals must be considered
                if (bridgingDecimals < 18) {
                    uint256 normalizedStakingAmount = stakingIncentive / (10 ** (18 - bridgingDecimals));
                    normalizedStakingAmount *= 10 ** (18 - bridgingDecimals);
                    // Update return amounts
                    returnAmount += stakingIncentive - normalizedStakingAmount;
                    // Downsize staking incentive to a specified number of bridging decimals
                    stakingIncentive = normalizedStakingAmount;
                }

                totalStakingIncentive += stakingIncentive;
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

        // Check for zero chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }

        // Check for zero target address
        if (stakingTarget == 0) {
            revert ZeroAddress();
        }

        // Check the number of claimed epochs
        uint256 localMaxNumClaimingEpochs = maxNumClaimingEpochs;
        if (numClaimedEpochs > localMaxNumClaimingEpochs) {
            revert Overflow(numClaimedEpochs, localMaxNumClaimingEpochs);
        }

        // Check for the paused state
        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused ||
            ITreasury(treasury).paused() == 2) {
            revert Paused();
        }

        // Get deposit processor bridging decimals corresponding to a chain Id
        address depositProcessor = mapChainIdDepositProcessors[chainId];
        uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

        // Get the staking incentive to send as a deposit with, and the amount to return back to staking inflation
        (uint256 stakingIncentive, uint256 returnAmount, uint256 lastClaimedEpoch, bytes32 nomineeHash) =
            calculateStakingIncentives(numClaimedEpochs, chainId, stakingTarget, bridgingDecimals);

        // Write last claimed epoch counter to start claiming from the next time
        mapLastClaimedStakingEpochs[nomineeHash] = lastClaimedEpoch;

        // Refund returned amount back to tokenomics inflation
        if (returnAmount > 0) {
            ITokenomics(tokenomics).refundFromStaking(returnAmount);
        }

        uint256 transferAmount;

        // Check if staking incentive is deposited
        if (stakingIncentive > 0) {
            transferAmount = stakingIncentive;
            // Account for possible withheld OLAS amounts
            // Note: in case of normalized staking incentives with bridging decimals, this is correctly managed
            // as normalized amounts are returned from another side
            uint256 withheldAmount = mapChainIdWithheldAmounts[chainId];
            if (withheldAmount > 0) {
                // If withheld amount is enough to cover all the staking incentives, the transfer of OLAS is not needed
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
            _distributeStakingIncentives(chainId, stakingTarget, stakingIncentive, bridgePayload, transferAmount);
        }

        emit StakingIncentivesClaimed(msg.sender, stakingIncentive, transferAmount, returnAmount);

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
        uint256 localMaxNumClaimingEpochs = maxNumClaimingEpochs;
        if (numClaimedEpochs > localMaxNumClaimingEpochs) {
            revert Overflow(numClaimedEpochs, localMaxNumClaimingEpochs);
        }

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused ||
            ITreasury(treasury).paused() == 2) {
            revert Paused();
        }

        // Total staking incentives
        // 0: Staking incentive across all the targets to send as a deposit
        // 1: Actual OLAS transfer amount across all the targets
        // 2: Staking incentive to return back to staking inflation
        uint256[] memory totalAmounts;
        // Arrays of staking and transfer amounts
        uint256[][] memory stakingIncentives;
        uint256[] memory transferAmounts;

        (totalAmounts, stakingIncentives, transferAmounts) = _calculateStakingIncentivesBatch(numClaimedEpochs, chainIds,
            stakingTargets);

        // Refund returned amount back to tokenomics inflation
        if (totalAmounts[2] > 0) {
            ITokenomics(tokenomics).refundFromStaking(totalAmounts[2]);
        }

        // Check if staking incentive is deposited
        if (totalAmounts[0] > 0) {
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

            // Dispense all the service staking targets, if the total staking incentive is not equal to zero
            _distributeStakingIncentivesBatch(chainIds, stakingTargets, stakingIncentives, bridgePayloads, transferAmounts,
                valueAmounts);
        }

        emit StakingIncentivesClaimed(msg.sender, totalAmounts[0], totalAmounts[1], totalAmounts[2]);

        _locked = 1;
    }

    /// @dev Retains staking incentives according to the retainer address to return it back to the staking inflation.
    function retain() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Go over epochs and retain funds to return back to the tokenomics
        bytes32 localRetainer = retainer;

        // Construct the nominee struct
        IVoteWeighting.Nominee memory nominee = IVoteWeighting.Nominee(localRetainer, block.chainid);
        // Get the nominee hash
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        // Get first and last claimed epochs
        (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) =
            _checkpointNomineeAndGetClaimedEpochCounters(nomineeHash, maxNumClaimingEpochs);

        // Write last claimed epoch counter to start retaining from the next time
        mapLastClaimedStakingEpochs[nomineeHash] = lastClaimedEpoch;

        uint256 totalReturnAmount;

        // Traverse all the claimed epochs
        for (uint256 j = firstClaimedEpoch; j < lastClaimedEpoch; ++j) {
            // Get service staking info
            ITokenomics.StakingPoint memory stakingPoint = ITokenomics(tokenomics).mapEpochStakingPoints(j);

            // Get epoch end time
            uint256 endTime = ITokenomics(tokenomics).getEpochEndTime(j);

            // Get the staking weight for each epoch
            (uint256 stakingWeight, ) = IVoteWeighting(voteWeighting).nomineeRelativeWeight(localRetainer,
                block.chainid, endTime);

            totalReturnAmount += stakingPoint.stakingIncentive * stakingWeight;
        }
        totalReturnAmount /= 1e18;

        if (totalReturnAmount > 0) {
            ITokenomics(tokenomics).refundFromStaking(totalReturnAmount);
        }

        emit Retained(msg.sender, totalReturnAmount);

        _locked = 1;
    }

    /// @dev Syncs the withheld amount according to the data received from L2.
    /// @notice Only a corresponding chain Id deposit processor is able to communicate the withheld amount data.
    /// @param chainId L2 chain Id the withheld amount data is communicated from.
    /// @param amount Withheld OLAS token amount.
    function syncWithheldAmount(uint256 chainId, uint256 amount) external {
        address depositProcessor = mapChainIdDepositProcessors[chainId];

        // Check L1 deposit processor address
        if (msg.sender != depositProcessor) {
            revert DepositProcessorOnly(msg.sender, depositProcessor);
        }

        // The overall amount is bound by the OLAS projected maximum amount for years to come
        uint256 withheldAmount = mapChainIdWithheldAmounts[chainId] + amount;
        if (withheldAmount > type(uint96).max) {
            revert Overflow(withheldAmount, type(uint96).max);
        }

        // Update the withheld amount
        mapChainIdWithheldAmounts[chainId] = withheldAmount;

        emit WithheldAmountSynced(chainId, amount, withheldAmount);
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

        // Check zero value chain Id and amount
        if (chainId == 0 || amount == 0) {
            revert ZeroValue();
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
            // Downsize staking incentive to a specified number of bridging decimals
            amount = normalizedAmount;
        }

        // The overall amount is bound by the OLAS projected maximum amount for years to come
        uint256 withheldAmount = mapChainIdWithheldAmounts[chainId] + amount;
        if (withheldAmount > type(uint96).max) {
            revert Overflow(withheldAmount, type(uint96).max);
        }

        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] = withheldAmount;

        emit WithheldAmountSynced(chainId, amount, withheldAmount);
    }

    /// @dev Sets the pause state.
    /// @param pauseState Pause state.
    function setPauseState(Pause pauseState) external {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = pauseState;

        emit PauseDispenser(pauseState);
    }
}
