// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IErrorsTokenomics} from "./interfaces/IErrorsTokenomics.sol";
import {IToken} from "./interfaces/IToken.sol";
import {ITokenomics} from "./interfaces/ITokenomics.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

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

// Tokenomics interface that was not recorded in ITokenomics
interface ITokenomicsInfo {
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

    /// @dev Gets tokenomics epoch counter.
    /// @return Epoch counter.
    function epochCounter() external view returns (uint32);

    /// @dev Gets tokenomics epoch point.
    /// @param eCounter Epoch number.
    /// @return Epoch point.
    function mapEpochTokenomics(uint256 eCounter) external view returns (EpochPoint memory);

    /// @dev Gets tokenomics epoch service staking point.
    /// @param eCounter Epoch number.
    /// @return Staking point.
    function mapEpochStakingPoints(uint256 eCounter) external view returns (StakingPoint memory);

    /// @dev Records the amount returned back to the inflation from staking.
    /// @param amount OLAS amount returned from staking.
    function refundFromStaking(uint256 amount) external;
}

interface IDepositProcessor {
    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingAmount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(address target, uint256 stakingAmount, bytes memory bridgePayload,
        uint256 transferAmount) external payable;

    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
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

/// @dev Only the deposit processor is able to call the function.
/// @param sender Actual sender address.
/// @param depositProcessor Required deposit processor.
error DepositProcessorOnly(address sender, address depositProcessor);

// TODO Names and titles in all the deployed contracts
/// @title Dispenser - Smart contract for distributing incentives
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract Dispenser is IErrorsTokenomics {
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
    mapping(bytes32 => uint256) public mapLastClaimedStakingServiceEpochs;
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
    constructor(address _tokenomics, address _treasury, address _voteWeighting)
    {
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

    function _checkpointNomineeAndGetClaimedEpochCounters(
        bytes32 target,
        uint256 chainId,
        uint256 numClaimedEpochs
    ) internal returns (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch)
    {
        // Checkpoint the vote weighting for the retainer on L1
        IVoteWeighting(voteWeighting).checkpointNominee(target, chainId);

        uint256 eCounter = ITokenomicsInfo(tokenomics).epochCounter();

        // Construct the nominee struct
        IVoteWeighting.Nominee memory nominee = IVoteWeighting.Nominee(target, chainId);
        // Check that the nominee exists
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        firstClaimedEpoch = mapLastClaimedStakingServiceEpochs[nomineeHash];
        // This must never happen as the nominee gets enabled when added to voteWeighting
        if (firstClaimedEpoch == 0) {
            revert();
        }

        // Shall not claim in the same epoch
        if (eCounter == firstClaimedEpoch) {
            revert();
        }

        // We still need to claim for the epoch number following the one when the nominee was removed
        uint256 epochAfterRemoved = mapRemovedNomineeEpochs[nomineeHash] + 1;
        if (firstClaimedEpoch >= epochAfterRemoved) {
            revert();
        }

        // Get a number of epochs to claim for based on the maximum number of epochs claimed
        lastClaimedEpoch = firstClaimedEpoch + numClaimedEpochs;

        // Limit last claimed epoch by the number following the nominee removal epoch
        if (lastClaimedEpoch > epochAfterRemoved) {
            lastClaimedEpoch = epochAfterRemoved;
        }

        // Also limit by the current counter, if the nominee was removed in the current epoch
        if (lastClaimedEpoch > eCounter) {
            lastClaimedEpoch = eCounter;
        }

        // Write last claimed epoch counter to start retaining from the next time
        mapLastClaimedStakingServiceEpochs[nomineeHash] = lastClaimedEpoch;
    }

    function _distribute(
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

    function _distributeBatch(
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        uint256[][] memory stakingAmounts,
        bytes[] memory bridgePayloads,
        uint256[] memory transferAmounts
    ) internal {
        // Traverse all staking targets
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Unpack chain Id and target addresses
            uint256 chainId = chainIds[i];
            // Get the deposit processor contract address
            address depositProcessor = mapChainIdDepositProcessors[chainId];
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

            // Allocate updated arrays
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
            if (chainId <= MAX_EVM_CHAIN_ID) {
                // Convert to EVM addresses
                address[] memory stakingTargetsEVM = new address[](updatedStakingTargets.length);
                for (uint256 j = 0; j < updatedStakingTargets.length; ++j) {
                    stakingTargetsEVM[j] = address(uint160(uint256(updatedStakingTargets[j])));
                }

                // Send to EVM chains
                IDepositProcessor(depositProcessor).sendMessageBatch{value:msg.value}(stakingTargetsEVM,
                    updatedStakingAmounts, bridgePayloads[i], transferAmounts[i]);
            } else {
                // Send to non-EVM chains
                IDepositProcessor(depositProcessor).sendMessageBatchNonEVM{value:msg.value}(updatedStakingTargets,
                    updatedStakingAmounts, bridgePayloads[i], transferAmounts[i]);
            }
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

    /// @notice Prerequisites: remove retainer from the nominees set, call retain()
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
            revert();
        }

        // Get the current retainer nominee hash
        bytes32 localRetainer = retainer;
        // Check the current retainer if it is not a zero address
        if (localRetainer != 0) {
            nominee = IVoteWeighting.Nominee(retainer, block.chainid);
            nomineeHash = keccak256(abi.encode(nominee));

            // The current retainer must be removed from nominees before switching to a new one
            uint256 eCounter = mapRemovedNomineeEpochs[nomineeHash];
            // Check that the retainer is removed
            if (eCounter == 0) {
                revert ZeroValue();
            }

            // Check that all the funds have been retained for previous epochs
            // The retainer must be removed in one of previous epochs
            if (eCounter > mapLastClaimedStakingServiceEpochs[nomineeHash]) {
                revert();
            }
        }

        retainer = newRetainer;
    }

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

        // TODO This must never happen, discuss
        if (mapLastClaimedStakingServiceEpochs[nomineeHash] > 0) {
            revert();
        }
        mapLastClaimedStakingServiceEpochs[nomineeHash] = ITokenomicsInfo(tokenomics).epochCounter();
    }

    /// @dev Records nominee removal epoch number.
    /// @param nomineeHash Nominee hash.
    function removeNominee(bytes32 nomineeHash) external {
        // Check for the contract ownership
        if (msg.sender != voteWeighting) {
            revert ManagerOnly(msg.sender, voteWeighting);
        }

        mapRemovedNomineeEpochs[nomineeHash] = ITokenomicsInfo(tokenomics).epochCounter();
    }

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
            ITokenomicsInfo.StakingPoint memory stakingPoint =
                ITokenomicsInfo(tokenomics).mapEpochStakingPoints(j);

            ITokenomicsInfo.EpochPoint memory ep = ITokenomicsInfo(tokenomics).mapEpochTokenomics(j);
            uint256 endTime = ep.endTime;

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

    function calculateStakingIncentives(
        uint256 numClaimedEpochs,
        uint256 chainId,
        bytes32 target,
        uint256 bridgingDecimals
    ) public returns (uint256 totalStakingAmount, uint256 totalReturnAmount) {
        // Check for the correct chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }

        // Check for the zero address
        if (target == 0) {
            revert ZeroAddress();
        }

        (uint256 firstClaimedEpoch, uint256 lastClaimedEpoch) =
            _checkpointNomineeAndGetClaimedEpochCounters(target, chainId, numClaimedEpochs);

        // Traverse all the claimed epochs
        for (uint256 j = firstClaimedEpoch; j < lastClaimedEpoch; ++j) {
            // TODO: optimize not to read several times in a row same epoch info
            // Get service staking info
            ITokenomicsInfo.StakingPoint memory stakingPoint =
                ITokenomicsInfo(tokenomics).mapEpochStakingPoints(j);

            ITokenomicsInfo.EpochPoint memory ep = ITokenomicsInfo(tokenomics).mapEpochTokenomics(j);
            uint256 endTime = ep.endTime;

            // Get the staking weight for each epoch and the total weight
            // Epoch endTime is used to get the weights info, since otherwise there is a risk of having votes
            // accounted for from the next epoch
            // totalWeightSum is the overall veOLAS power (bias) across all the voting nominees
            (uint256 stakingWeight, uint256 totalWeightSum) =
                IVoteWeighting(voteWeighting).nomineeRelativeWeight(target, chainId, endTime);

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

    function claimStakingIncentives(
        uint256 numClaimedEpochs,
        uint256 chainId,
        bytes32 target,
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
            revert();
        }

        address depositProcessor = mapChainIdDepositProcessors[chainId];
        uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

        // Staking amount to send as a deposit with, and the amount to return back to effective staking
        (uint256 stakingAmount, uint256 returnAmount) = calculateStakingIncentives(numClaimedEpochs, chainId, target,
            bridgingDecimals);

        // Refund returned amount back to tokenomics inflation
        if (returnAmount > 0) {
            ITokenomicsInfo(tokenomics).refundFromStaking(returnAmount);
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
                    revert();
                }
            }

            // Dispense to a service staking target
            _distribute(chainId, target, stakingAmount, bridgePayload, transferAmount);
        }

        emit StakingIncentivesClaimed(msg.sender, stakingAmount, transferAmount, returnAmount);

        _locked = 1;
    }

    // Ascending order of chain Ids
    /// @notice Mind the gas spending depending on the max number of numChains * numTargetsPerChain * numEpochs to claim.
    function claimStakingIncentivesBatch(
        uint256 numClaimedEpochs,
        uint256[] memory chainIds,
        bytes32[][] memory stakingTargets,
        bytes[] memory bridgePayloads
    ) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check array sizes
        if (chainIds.length != stakingTargets.length || chainIds.length != bridgePayloads.length) {
            revert WrongArrayLength(chainIds.length, stakingTargets.length);
        }

        // Check the number of claimed epochs
        if (numClaimedEpochs > maxNumClaimingEpochs) {
            revert Overflow(numClaimedEpochs, maxNumClaimingEpochs);
        }

        Pause currentPause = paused;
        if (currentPause == Pause.StakingIncentivesPaused || currentPause == Pause.AllPaused) {
            revert();
        }

        // Staking amount across all the targets to send as a deposit
        uint256 totalStakingAmount;
        // Actual OLAS transfer amount across all the targets
        uint256 totalTransferAmount;
        // Staking amount to return back to effective staking
        uint256 totalReturnAmount;

        // Allocate the array of staking and transfer amounts
        uint256[][] memory stakingAmounts = new uint256[][](chainIds.length);
        uint256[] memory transferAmounts = new uint256[](chainIds.length);

        uint256 lastChainId;
        bytes32 lastTarget;
        // Traverse all chains
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

            // Check for the maximum number of staking targets
            if (stakingTargets[i].length > maxNumStakingTargets) {
                revert Overflow(stakingTargets[i].length, maxNumStakingTargets);
            }

            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

            stakingAmounts[i] = new uint256[](stakingTargets[i].length);
            // Traverse all staking targets
            for (uint256 j = 0; j < stakingTargets[i].length; ++j) {
                // Enforce ascending non-repeatable order of targets
                if (uint256(lastTarget) >= uint256(stakingTargets[i][j])) {
                    revert();
                }
                lastTarget = stakingTargets[i][j];

                // Staking amount to send as a deposit with, and the amount to return back to effective staking
                (uint256 stakingAmount, uint256 returnAmount) = calculateStakingIncentives(numClaimedEpochs, chainIds[i],
                    stakingTargets[i][j], bridgingDecimals);

                stakingAmounts[i][j] = stakingAmount;
                transferAmounts[i] += stakingAmount;
                totalStakingAmount += stakingAmount;
                totalReturnAmount += returnAmount;
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
            totalTransferAmount += transferAmounts[i];
        }

        // Refund returned amount back to tokenomics inflation
        if (totalReturnAmount > 0) {
            ITokenomicsInfo(tokenomics).refundFromStaking(totalReturnAmount);
        }

        // Check if minting is needed as the actual OLAS transfer is required
        if (totalTransferAmount > 0) {
            uint256 balanceBefore = IToken(olas).balanceOf(address(this));

            // Mint tokens to self in order to distribute to staking deposit processors
            ITreasury(treasury).withdrawToAccount(address(this), 0, totalTransferAmount);

            // Check the balance after the mint
            if (IToken(olas).balanceOf(address(this)) - balanceBefore != totalTransferAmount) {
                revert();
            }
        }

        // Dispense all the service staking targets
        _distributeBatch(chainIds, stakingTargets, stakingAmounts, bridgePayloads, transferAmounts);

        emit StakingIncentivesClaimed(msg.sender, totalStakingAmount, totalTransferAmount, totalReturnAmount);

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

        // The sync must never happen for the L1 chain Id itself
        if (chainId == 1) {
            revert();
        }

        // Get bridging decimals for a specified chain Id
        address depositProcessor = mapChainIdDepositProcessors[chainId];
        uint256 bridgingDecimals = IDepositProcessor(depositProcessor).getBridgingDecimals();

        // Normalize the synced withheld amount via maintenance is correct
        if (bridgingDecimals < 18) {
            uint256 normalizedAmount = amount / (10**(18 - bridgingDecimals));
            normalizedAmount *= 10**(18 - bridgingDecimals);
            // Downsize staking amount to a specified number of bridging decimals
            amount = normalizedAmount;
        }

        // Add to the withheld amount
        mapChainIdWithheldAmounts[chainId] += amount;

        emit WithheldAmountSynced(chainId, amount);
    }

    function setPause(Pause pauseState) external {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = pauseState;
    }
}
