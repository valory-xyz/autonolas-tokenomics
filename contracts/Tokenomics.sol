// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@partylikeits1983/statistics_solidity/contracts/dependencies/prb-math/PRBMathSD59x18.sol";
import "./GenericTokenomics.sol";
import "./TokenomicsConstants.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/IServiceTokenomics.sol";
import "./interfaces/IToken.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IVotingEscrow.sol";

/*
* In this contract we consider both ETH and OLAS tokens.
* For ETH tokens, there are currently about 121 million tokens.
* Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply.
* Lately the inflation rate was lower and could actually be deflationary.
*
* For OLAS tokens, the initial numbers will be as follows:
*  - For the first 10 years there will be the cap of 1 billion (1e27) tokens;
*  - After 10 years, the inflation rate is capped at 2% per year.
* Starting from a year 11, the maximum number of tokens that can be reached per the year x is 1e27 * (1.02)^x.
* To make sure that a unit(n) does not overflow the total supply during the year x, we have to check that
* 2^n - 1 >= 1e27 * (1.02)^x. We limit n by 96, thus it would take 220+ years to reach that total supply.
*
* We then limit each time variable to last until the value of 2^32 - 1 in seconds.
* 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970.
* Thus, this counter is safe until the year 2106.
*
* The number of blocks cannot be practically bigger than the number of seconds, since there is more than one second
* in a block. Thus, it is safe to assume that uint32 for the number of blocks is also sufficient.
*
* We also limit the number of registry units by the value of 2^32 - 1.
* We assume that the system is expected to support no more than 2^32-1 units.
*
* Lastly, we assume that the coefficients from tokenomics factors calculation are bound by 2^16 - 1.
*
* In conclusion, this contract is only safe to use until 2106.
*/

// Structure for component / agent point with tokenomics-related statistics
// The size of the struct is 96 * 4 + 32 + 8 = 424 bits (2 full slot)
struct UnitPoint {
    // Summation of all the relative ETH donations accumulated by each component / agent in a service
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 sumUnitDonationsETH;
    // Summation of all the relative OLAS top-ups accumulated by each component / agent in a service
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 sumUnitTopUpsOLAS;
    // Number of new units
    // This number cannot be practically bigger than the total number of supported units
    uint32 numNewUnits;
    // Unit weight for code unit calculations
    // This number is related to the component / agent reward fraction
    // We assume this number will not be practically bigger than 255
    uint8 unitWeight;
    // Component / agent rewards
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 unitRewards;
    // Component / agent top-ups
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 unitTopUps;
}

// Structure for epoch point with tokenomics-related statistics during each epoch
// The size of the struct is 96 * 4 + 64 + 32 * 4 = 576 (3 full slots)
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
    // Staker rewards in ETH
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 stakerRewards;
    // Staker top-ups in OLAS
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 stakerTopUps;
    // Number of valuable devs can be paid per units of capital per epoch
    // This number cannot be practically bigger than the total number of supported units
    uint32 devsPerCapital;
    // Number of new owners
    // Each unit has at most one owner, so this number cannot be practically bigger than numNewUnits
    uint32 numNewOwners;
    // Epoch end block number
    // With the current number of seconds per block and the current block number, 2^32 - 1 is enough for the next 1600+ years
    uint32 endBlockNumber;
    // Epoch end timestamp
    // 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970, which is safe until the year of 2106
    uint32 endTime;
}

// Structure for tokenomics point
// The size of the struct is 256 * 4 + 256 * 3 = 256 * 7 (7 full slots)
struct TokenomicsPoint {
    // Two unit points in a representation of mapping and not on array to save on gas
    // One unit point is for component (key = 0) and one is for agent (key = 1)
    mapping(uint256 => UnitPoint) unitPoints;
    // Epoch point
    EpochPoint epochPoint;
}

// Struct for component / agent incentive balances
struct IncentiveBalances {
    // Reward in ETH
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 reward;
    // Pending relative reward in ETH
    uint96 pendingRelativeReward;
    // Top-up in OLAS
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 topUp;
    // Pending relative top-up
    uint96 pendingRelativeTopUp;
    // Last epoch number the information was updated
    // This number cannot be practically bigger than the number of blocks
    uint32 lastEpoch;
}

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is TokenomicsConstants, GenericTokenomics {
    using PRBMathSD59x18 for *;

    event EpochLengthUpdated(uint256 epochLength);
    event TokenomicsParametersUpdated(uint256 devsPerCapital, uint256 epsilonRate, uint256 epochLen, uint256 veOLASThreshold);
    event IncentiveFractionsUpdated(uint256 rewardStakerFraction, uint256 rewardComponentFraction, uint256 rewardAgentFraction,
        uint256 maxBondFraction, uint256 topUpComponentFraction, uint256 topUpAgentFraction);
    event ComponentRegistryUpdated(address indexed componentRegistry);
    event AgentRegistryUpdated(address indexed agentRegistry);
    event ServiceRegistryUpdated(address indexed serviceRegistry);
    event EpochSettled(uint256 epochCounter, uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps);

    // Voting Escrow address
    address public immutable ve;

    // Max bond per epoch: calculated as a fraction from the OLAS inflation parameter
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 public maxBond;
    // Default epsilon rate that contributes to the interest rate: 10% or 0.1
    // We assume that for the IDF calculation epsilonRate must be lower than 17 (with 18 decimals)
    // (2^64 - 1) / 10^18 > 18, however IDF = 1 + epsilonRate, thus we limit epsilonRate by 17 with 18 decimals at most
    uint64 public epsilonRate = 1e17;
    // Epoch length in seconds
    // By design, the epoch length cannot be practically bigger than one year, or 31_536_000 seconds
    uint32 public epochLen;
    // Global epoch counter
    // This number cannot be practically bigger than the number of blocks
    uint32 public epochCounter;

    // Inflation amount per second
    uint96 public inflationPerSecond;
    // veOLAS threshold for top-ups
    // This number cannot be practically bigger than the number of OLAS tokens
    uint96 public veOLASThreshold = 5_000e18;

    // Component Registry
    address public componentRegistry;
    // effectiveBond = sum(MaxBond(e)) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    // Effective bond is updated before the start of the next epoch such that the bonding limits are accounted for
    // This number cannot be practically bigger than the inflation remainder of OLAS
    uint96 public effectiveBond;

    // Agent Registry
    address public agentRegistry;
    // Component / agent reward fractions
    uint8 rewardAgentFraction;
    uint8 rewardComponentFraction;
    // Component / agent top-up fractions
    // This number cannot be practically bigger than 100 as the summation with other fractions gives at most 100 (%)
    uint8 topUpComponentFraction;
    uint8 topUpAgentFraction;
    uint8 rewardTreasuryFraction;
    // Staking parameters for rewards (in percentage)
    // treasuryFraction (implicitly set to zero by default) + rewardComponentFraction + rewardAgentFraction + rewardStakerFraction = 100%
    // Staker reward fraction
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 rewardStakerFraction;
    // Staking parameters for top-ups (in percentage)
    // maxBondFraction + topUpComponentFraction + topUpAgentFraction + topUpStakerFraction = 100%
    // Amount of OLAS (in percentage of inflation) intended to fund bonding incentives during the epoch
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 maxBondFraction;
    // Amount of OLAS (in percentage of inflation) intended to fund veOLAS locker to-ups during the epoch
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 topUpStakerFraction;

    // Service Registry
    address public serviceRegistry;
    // Current year number
    // This number is enough for the next 255 years
    uint8 public currentYear;
    // maxBond-related parameter change locker
    uint8 public lockMaxBond = 1;

    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) public mapServiceAmounts;
    // Mapping of owner of component / agent address => reward amount (in ETH)
    mapping(address => uint256) public mapOwnerRewards;
    // Mapping of owner of component / agent address => top-up amount (in OLAS)
    mapping(address => uint256) public mapOwnerTopUps;
    // Mapping of epoch => point
    mapping(uint256 => TokenomicsPoint) public mapEpochTokenomics;
    // Map of new component / agent Ids that contribute to protocol owned services
    mapping(uint256 => mapping(uint256 => bool)) public mapNewUnits;
    // Mapping of new owner of component / agent addresses that create them
    mapping(address => bool) public mapNewOwners;
    // Mapping of component / agent Id => incentive balances
    mapping(uint256 => mapping(uint256 => IncentiveBalances)) public mapUnitIncentives;

    /// @dev Tokenomics constructor.
    /// @notice To avoid circular dependency, the contract with its role sets its own address to address(this)
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _ve Voting Escrow address.
    /// @param _epochLen Epoch length.
    /// @param _componentRegistry Component registry address.
    /// @param _agentRegistry Agent registry address.
    /// @param _serviceRegistry Service registry address.
    constructor(address _olas, address _treasury, address _depository, address _dispenser, address _ve, uint32 _epochLen,
        address _componentRegistry, address _agentRegistry, address _serviceRegistry)
        TokenomicsConstants()
        GenericTokenomics(_olas, address(this), _treasury, _depository, _dispenser, TokenomicsRole.Tokenomics)
    {
        ve = _ve;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;

        // Calculating initial inflation per second: (mintable OLAS from inflationAmounts[0]) / (seconds left in a year)
        uint256 _inflationPerSecond = 22_113_000_0e17 / zeroYearSecondsLeft;
        inflationPerSecond = uint96(_inflationPerSecond);

        // The initial epoch start time is the end time of the zero epoch
        mapEpochTokenomics[0].epochPoint.endTime = uint32(block.timestamp);

        // The epoch counter starts from 1
        epochCounter = 1;
        TokenomicsPoint storage tp = mapEpochTokenomics[1];

        // Setting initial parameters and ratios
        tp.epochPoint.devsPerCapital = 1;
        tp.epochPoint.idf = 1e18 + epsilonRate;

        rewardStakerFraction = 49;
        // The initial target is to distribute around 2/3 of incentives reserved to fund owners of the code
        // for components royalties and 1/3 for agents royalties
        rewardComponentFraction = 34;
        rewardAgentFraction = 17;

        // We want to measure a unit of code as n agents or m components.
        // Initially we consider 1 unit of code as either 2 agents or 1 component.
        // E.g. if we have 2 profitable components and 2 profitable agents, this means there are (2x2 + 2x1) / 3 = 2
        // units of code. Note that usually these weights are related to unit fractions.
        // 0 stands for components and 1 for agents
        tp.unitPoints[0].unitWeight = 1;
        tp.unitPoints[1].unitWeight = 2;

        // Accumulate numbers into topUpFractions
        uint256 _maxBondFraction = 49;
        maxBondFraction = uint8(_maxBondFraction);
        topUpComponentFraction = 34;
        topUpAgentFraction = 17;
        // topUpStakerFraction is essentially equal to zero

        // Calculate initial effectiveBond based on the maxBond during the first epoch
        uint256 _maxBond = _inflationPerSecond * _epochLen * _maxBondFraction / 100;
        maxBond = uint96(_maxBond);
        effectiveBond = uint96(_maxBond);
    }

    /// @dev Checks if the maxBond update is within allowed limits of the effectiveBond, and adjusts maxBond and effectiveBond.
    /// @param nextMaxBond Proposed next epoch maxBond.
    function _adjustMaxBond(uint256 nextMaxBond) internal {
        uint256 curMaxBond = maxBond;
        uint256 curEffectiveBond = effectiveBond;
        // If the new epochLen is shorter than the current one, the current maxBond is bigger than the proposed nextMaxBond
        if (curMaxBond > nextMaxBond) {
            // Get the difference of the maxBond
            uint256 delta = curMaxBond - nextMaxBond;
            // Update the value for the effectiveBond if there is room for it
            if (curEffectiveBond > delta) {
                curEffectiveBond -= delta;
            } else {
                // Otherwise effectiveBond cannot be reduced further, and the current epochLen cannot be shortened
                revert RejectMaxBondAdjustment(curEffectiveBond, delta);
            }
        } else {
            // The new epochLen is longer than the current one, and thus we must add the difference to the effectiveBond
            curEffectiveBond += nextMaxBond - curMaxBond;
        }
        // Update maxBond and effectiveBond based on their calculations
        maxBond = uint96(nextMaxBond);
        effectiveBond = uint96(curEffectiveBond);
    }

    /// @dev Changes tokenomics parameters.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    /// @param _epsilonRate Epsilon rate that contributes to the interest rate value.
    /// @param _epochLen New epoch length.
    function changeTokenomicsParameters(
        uint32 _devsPerCapital,
        uint64 _epsilonRate,
        uint32 _epochLen,
        uint96 _veOLASThreshold
    ) external
    {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (_devsPerCapital > 0) {
            mapEpochTokenomics[epochCounter].epochPoint.devsPerCapital = _devsPerCapital;
        } else {
            // This is done in order not to pass incorrect parameters into the event
            _devsPerCapital = mapEpochTokenomics[epochCounter].epochPoint.devsPerCapital;
        }

        // Check the epsilonRate value for idf to fit in its size
        // 2^64 - 1 < 18.5e18, idf is equal at most 1 + epsilonRate < 18e18, which fits in the variable size
        if (_epsilonRate > 0 && _epsilonRate < 17e18) {
            epsilonRate = _epsilonRate;
        } else {
            _epsilonRate = epsilonRate;
        }

        // Check for the epochLen value to change
        uint256 oldEpochLen = epochLen;
        if (_epochLen > 0 && oldEpochLen != _epochLen) {
            // Check if the year change is ongoing in the current epoch, and thus maxBond cannot be changed
            if (lockMaxBond == 2) {
                revert MaxBondUpdateLocked();
            }

            // Check if the bigger proposed length of the epoch end time results in a scenario when the year changes
            if (_epochLen > oldEpochLen) {
                // End time of the last epoch
                uint256 lastEpochEndTime = mapEpochTokenomics[epochCounter - 1].epochPoint.endTime;
                // Actual year of the time when the epoch is going to finish with the proposed epoch length
                uint256 numYears = (lastEpochEndTime + _epochLen - timeLaunch) / oneYear;
                // Check if the year is going to change
                if (numYears > currentYear) {
                    revert MaxBondUpdateLocked();
                }
            }

            // Calculate next maxBond based on the proposed epochLen
            uint256 nextMaxBond = inflationPerSecond * maxBondFraction * _epochLen / 100;
            // Adjust maxBond and effectiveBond, if they are within the allowed limits
            _adjustMaxBond(nextMaxBond);

            // Update the epochLen
            epochLen = _epochLen;
        } else {
            _epochLen = epochLen;
        }

        if (_veOLASThreshold > 0) {
            veOLASThreshold = _veOLASThreshold;
        } else {
            _veOLASThreshold = veOLASThreshold;
        }

        emit TokenomicsParametersUpdated(_devsPerCapital, _epsilonRate, _epochLen, _veOLASThreshold);
    }

    /// @dev Sets incentive parameter fractions.
    /// @param _rewardStakerFraction Fraction for staker rewards funded by ETH donations.
    /// @param _rewardComponentFraction Fraction for component owner rewards funded by ETH donations.
    /// @param _rewardAgentFraction Fraction for agent owner rewards funded by ETH donations.
    /// @param _maxBondFraction Fraction for the maxBond that depends on the OLAS inflation.
    /// @param _topUpComponentFraction Fraction for OLAS top-up for component owners.
    /// @param _topUpAgentFraction Fraction for OLAS top-up for agent owners.
    function changeIncentiveFractions(
        uint8 _rewardStakerFraction,
        uint8 _rewardComponentFraction,
        uint8 _rewardAgentFraction,
        uint8 _maxBondFraction,
        uint8 _topUpComponentFraction,
        uint8 _topUpAgentFraction
    ) external
    {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that the sum of fractions is 100%
        if (_rewardStakerFraction + _rewardComponentFraction + _rewardAgentFraction > 100) {
            revert WrongAmount(_rewardStakerFraction + _rewardComponentFraction + _rewardAgentFraction, 100);
        }

        // Same check for OLAS-related fractions
        if (_maxBondFraction + _topUpComponentFraction + _topUpAgentFraction > 100) {
            revert WrongAmount(_maxBondFraction + _topUpComponentFraction + _topUpAgentFraction, 100);
        }

        rewardStakerFraction = _rewardStakerFraction;
        rewardComponentFraction = _rewardComponentFraction;
        rewardAgentFraction = _rewardAgentFraction;

        // Check if the maxBondFraction changes
        uint256 oldMaxBondFraction = maxBondFraction;
        if (oldMaxBondFraction != _maxBondFraction) {
            // Epoch with the year change is ongoing, and maxBond cannot be changed
            if (lockMaxBond == 2) {
                revert MaxBondUpdateLocked();
            }

            // Calculate next maxBond based on the proposed maxBondFraction
            uint256 nextMaxBond = inflationPerSecond * _maxBondFraction * epochLen;
            // Adjust maxBond and effectiveBond, if they are within the allowed limits
            _adjustMaxBond(nextMaxBond);

            // Update the maxBondFraction
            maxBondFraction = _maxBondFraction;
        }
        topUpComponentFraction = _topUpComponentFraction;
        topUpAgentFraction = _topUpAgentFraction;
        topUpStakerFraction = 100 - _maxBondFraction - _topUpComponentFraction - _topUpAgentFraction;

        emit IncentiveFractionsUpdated(_rewardStakerFraction, _rewardComponentFraction, _rewardAgentFraction,
            _maxBondFraction, _topUpComponentFraction, _topUpAgentFraction);
    }

    /// @dev Changes registries contract addresses.
    /// @param _componentRegistry Component registry address.
    /// @param _agentRegistry Agent registry address.
    /// @param _serviceRegistry Service registry address.
    function changeRegistries(address _componentRegistry, address _agentRegistry, address _serviceRegistry) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for registries addresses
        if (_componentRegistry != address(0)) {
            componentRegistry = _componentRegistry;
            emit ComponentRegistryUpdated(_componentRegistry);
        }
        if (_agentRegistry != address(0)) {
            agentRegistry = _agentRegistry;
            emit AgentRegistryUpdated(_agentRegistry);
        }
        if (_serviceRegistry != address(0)) {
            serviceRegistry = _serviceRegistry;
            emit ServiceRegistryUpdated(_serviceRegistry);
        }
    }

    /// @dev Reserves OLAS amount from the effective bond to be minted during a bond program.
    /// @notice Programs exceeding the limit of the effective bond are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return success True if effective bond threshold is not reached.
    function reserveAmountForBondProgram(uint256 amount) external returns (bool success) {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        // Effective bond must be bigger than the requested amount
        uint256 eBond = effectiveBond;
        if ((eBond + 1) > amount) {
            // The value of effective bond is then adjusted to the amount that is now reserved for bonding
            // The unrealized part of the bonding amount will be returned when the bonding program is closed
            eBond -= amount;
            effectiveBond = uint96(eBond);
            success = true;
        }
    }

    /// @dev Refunds unused bond program amount when the program is closed.
    /// @param amount Amount to be refunded from the closed bond program.
    function refundFromBondProgram(uint256 amount) external {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        uint256 eBond = effectiveBond + amount;
        effectiveBond = uint96(eBond);
    }

    /// @dev Finalizes epoch incentives for a specified component / agent Id.
    /// @param epochNum Epoch number to finalize incentives for.
    /// @param unitType Unit type (component / agent).
    /// @param unitId Unit Id.
    function _finalizeIncentivesForUnitId(uint256 epochNum, uint256 unitType, uint256 unitId) internal {
        // Get the overall amount of component rewards for the component's last epoch
        // reward = (pendingRelativeReward * unitRewards) / sumUnitDonationsETH
        uint256 totalIncentives = mapUnitIncentives[unitType][unitId].pendingRelativeReward;
        totalIncentives *= mapEpochTokenomics[epochNum].unitPoints[unitType].unitRewards;
        uint256 sumUnitIncentives = mapEpochTokenomics[epochNum].unitPoints[unitType].sumUnitDonationsETH;
        // TODO Optimize gas usage
        // Add to the final reward for the last epoch
        mapUnitIncentives[unitType][unitId].reward += uint96(totalIncentives / sumUnitIncentives);
        // Setting pending reward to zero
        mapUnitIncentives[unitType][unitId].pendingRelativeReward = 0;
        // Add to the final top-up for the last epoch
        if (mapUnitIncentives[unitType][unitId].pendingRelativeTopUp > 0) {
            // Summation of all the unit top-ups and total amount of top-ups per epoch
            // topUp = (pendingRelativeTopUp * unitTopUps) / sumUnitTopUpsOLAS
            totalIncentives = mapUnitIncentives[unitType][unitId].pendingRelativeTopUp;
            totalIncentives *= mapEpochTokenomics[epochNum].unitPoints[unitType].unitTopUps;
            sumUnitIncentives = mapEpochTokenomics[epochNum].unitPoints[unitType].sumUnitTopUpsOLAS;
            mapUnitIncentives[unitType][unitId].topUp += uint96(totalIncentives / sumUnitIncentives);
            // Setting pending top-up to zero
            mapUnitIncentives[unitType][unitId].pendingRelativeTopUp = 0;
        }
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    /// @return donationETH Overall service donation amount in ETH.
    function trackServicesETHRevenue(uint32[] memory serviceIds, uint96[] memory amounts) external
        returns (uint96 donationETH)
    {
        // Check for the treasury access
        if (treasury != msg.sender) {
            revert ManagerOnly(msg.sender, treasury);
        }

        // Component / agent registry addresses
        address[] memory registries = new address[](2);
        (registries[0], registries[1]) = (componentRegistry, agentRegistry);

        // Get the current epoch
        uint256 curEpoch = epochCounter;
        // TODO gas optimization
        // Get the current epoch struct pointer
        TokenomicsPoint storage tp = mapEpochTokenomics[curEpoch];
        // Get the number of services
        uint256 numServices = serviceIds.length;
        // Loop over service Ids to calculate their partial UCFu-s
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existence
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }

            // TODO Account for zero fractions for components and agents here, in setting them and in incentives calculations

            // Check if the service owner stakes enough OLAS for its components / agents to get a top-up
            address serviceOwner = IToken(serviceRegistry).ownerOf(serviceIds[i]);
            bool topUpEligible = IVotingEscrow(ve).getVotes(serviceOwner) > veOLASThreshold ? true : false;

            // Loop over component and agent Ids
            for (uint256 unitType = 0; unitType < 2; ++unitType) {
                // Get the number and set of units in the service
                (uint256 numServiceUnits, uint32[] memory serviceUnitIds) = IServiceTokenomics(serviceRegistry).
                    getUnitIdsOfService(IServiceTokenomics.UnitType(unitType), serviceIds[i]);
                // Accumulate amounts for each unit Id
                for (uint256 j = 0; j < numServiceUnits; ++j) {
                    // Get the last epoch number the incentives were accumulated for
                    uint256 lastEpoch = mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch;
                    // Check if there were no donations in previous epochs and set the current epoch
                    if (lastEpoch == 0) {
                        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
                    } else if (lastEpoch < curEpoch) {
                        // Finalize component rewards and top-ups if there were pending ones from the previous epoch
                        _finalizeIncentivesForUnitId(lastEpoch, unitType, serviceUnitIds[j]);
                        // Change the last epoch number
                        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
                    }
                    // Sum the relative amounts for the corresponding components / agents
                    mapUnitIncentives[unitType][serviceUnitIds[j]].pendingRelativeReward += amounts[i];
                    mapEpochTokenomics[curEpoch].unitPoints[unitType].sumUnitDonationsETH += amounts[i];
                    // If eligible, add relative top-up weights in the form of donation amounts.
                    // These weights will represent the fraction of top-ups for each component / agent relative
                    // to the overall amount of top-ups that must be allocated
                    if (topUpEligible) {
                        mapUnitIncentives[unitType][serviceUnitIds[j]].pendingRelativeTopUp += amounts[i];
                        mapEpochTokenomics[curEpoch].unitPoints[unitType].sumUnitTopUpsOLAS += amounts[i];
                    }
    
                    // Check if the component / agent is used for the first time
                    if (!mapNewUnits[unitType][serviceUnitIds[j]]) {
                        mapNewUnits[unitType][serviceUnitIds[j]] = true;
                        tp.unitPoints[unitType].numNewUnits++;
                        // Check if the owner has introduced component / agent for the first time
                        // This is done together with the new unit check, otherwise it could be just a new unit owner
                        address unitOwner = IToken(registries[unitType]).ownerOf(serviceUnitIds[j]);
                        if (!mapNewOwners[unitOwner]) {
                            mapNewOwners[unitOwner] = true;
                            tp.epochPoint.numNewOwners++;
                        }
                    }
                }
            }

            // Sum up ETH service amounts
            donationETH += amounts[i];
        }

        // Increase the total service donation balance per epoch
        donationETH = tp.epochPoint.totalDonationsETH + donationETH;
        tp.epochPoint.totalDonationsETH = donationETH;
    }

    // TODO Figure out how to call checkpoint automatically, i.e. with a keeper
    /// @dev Record global data to new checkpoint
    /// @return True if the function execution is successful.
    function checkpoint() external returns (bool) {
        // New point can be calculated only if we passed the number of blocks equal to the epoch length
        uint256 prevEpochTime = mapEpochTokenomics[epochCounter - 1].epochPoint.endTime;
        uint256 diffNumSeconds = block.timestamp - prevEpochTime;
        uint256 curEpochLen = epochLen;
        if (diffNumSeconds < curEpochLen) {
            return false;
        }

        uint256 eCounter = epochCounter;
        TokenomicsPoint storage tp = mapEpochTokenomics[eCounter];

        // 0: total rewards funded with donations in ETH, that are split between:
        // 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // OLAS inflation is split between:
        // 5: maxBond, 6: component ownerTopUps, 7: agent ownerTopUps, 8: stakerTopUps
        uint256[] memory rewards = new uint256[](9);
        rewards[0] = tp.epochPoint.totalDonationsETH;
        // Treasury reward calculation
        rewards[1] = (rewards[0] * rewardTreasuryFraction) / 100;
        // 0 stands for components and 1 for agents
        rewards[2] = (rewards[0] * rewardStakerFraction) / 100;
        rewards[3] = (rewards[0] * rewardComponentFraction) / 100;
        rewards[4] = (rewards[0] * rewardAgentFraction) / 100;

        // The actual inflation per epoch considering that it is settled not in the exact epochLen time, but a bit later
        uint256 inflationPerEpoch;
        // Get the maxBond that was credited to effectiveBond during this settled epoch
        // If the year changes, the maxBond for the next epoch is updated in the condition below and will be used
        // later when the effectiveBond is updated for the next epoch
        uint256 curMaxBond = maxBond;
        // Current year
        uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
        // There amounts for the yearly inflation change from year to year, so if the year changes in the middle
        // of the epoch, it is necessary to adjust the epoch inflation numbers to account for the year change
        if (numYears > currentYear) {
            // Calculate remainder of inflation for the passing year
            uint256 curInflationPerSecond = inflationPerSecond;
            // End of the year timestamp
            uint256 yearEndTime = timeLaunch + numYears * oneYear;
            // Initial inflation per epoch during the end of the year minus previous epoch timestamp
            inflationPerEpoch = (yearEndTime - prevEpochTime) * curInflationPerSecond;
            // Recalculate the inflation per second based on the new inflation for the current year
            curInflationPerSecond = getInflationForYear(numYears) / oneYear;
            // Add the remainder of inflation amount for this epoch based on a new inflation per second ratio
            inflationPerEpoch += (block.timestamp - yearEndTime) * curInflationPerSecond;
            // Update the maxBond value for the next epoch after the year changes
            maxBond = uint96(curInflationPerSecond * curEpochLen * maxBondFraction) / 100;
            // Updating state variables
            inflationPerSecond = uint96(curInflationPerSecond);
            currentYear = uint8(numYears);
            // maxBond lock is released and can be changed starting from the new epoch
            lockMaxBond = 1;
        } else {
            inflationPerEpoch = inflationPerSecond * diffNumSeconds;
        }

        // Bonding and top-ups in OLAS are recalculated based on the inflation schedule per epoch
        // Actual maxBond of the epoch
        tp.epochPoint.totalTopUpsOLAS = uint96(inflationPerEpoch);
        rewards[5] = (inflationPerEpoch * maxBondFraction) / 100;

        // Effective bond accumulates bonding leftovers from previous epochs (with the last max bond value set)
        // It is given the value of the maxBond for the next epoch as a credit
        // The difference between recalculated max bond per epoch and maxBond value must be reflected in effectiveBond,
        // since the epoch checkpoint delay was not accounted for initially
        // TODO optimize for gas usage below
        // TODO Prove that the adjusted maxBond (rewards[5]) will never be lower than the epoch maxBond
        // This has to always be true, or rewards[5] == curMaxBond if the epoch is settled exactly at the epochLen time
        if (rewards[5] > curMaxBond) {
            // Adjust the effectiveBond
            //rewards[5] = effectiveBond + rewards[5] - curMaxBond;
            //effectiveBond = uint96(rewards[5]);
            effectiveBond += uint96(rewards[5] - curMaxBond);
        }

        // Adjust max bond value if the next epoch is going to be the year change epoch
        // Note that this computation happens before the epoch that is triggered in the next epoch (the code above) when
        // the actual year will change
        numYears = (block.timestamp + curEpochLen - timeLaunch) / oneYear;
        // Account for the year change to adjust the max bond
        if (numYears > currentYear) {
            // Calculate remainder of inflation for the passing year
            uint256 curInflationPerSecond = inflationPerSecond;
            // End of the year timestamp
            uint256 yearEndTime = timeLaunch + numYears * oneYear;
            // Calculate the  max bond value until the end of the year
            curMaxBond = ((yearEndTime - block.timestamp) * curInflationPerSecond * maxBondFraction) / 100;
            // Recalculate the inflation per second based on the new inflation for the current year
            curInflationPerSecond = getInflationForYear(numYears) / oneYear;
            // Add the remainder of max bond amount for the next epoch based on a new inflation per second ratio
            curMaxBond += ((block.timestamp + curEpochLen - yearEndTime) * curInflationPerSecond * maxBondFraction) / 100;
            maxBond = uint96(curMaxBond);
            // maxBond lock is set and cannot be changed until the next epoch with the year change passes
            lockMaxBond = 2;
        } else {
            // This assignment is done again to account for the maxBond value that could change if we are currently
            // in the epoch with a changing year
            curMaxBond = maxBond;
        }
        // Update effectiveBond with the current or updated maxBond value
        effectiveBond += uint96(curMaxBond);

        // Calculate the inverse discount factor based on the tokenomics parameters and values of units per epoch
        // idf = 1 / (1 + iterest_rate), reverse_df = 1/df >= 1.0.
        uint64 idf;
        if (rewards[0] > 0) {
            // 0 for components and 1 for agents
            uint256 sumWeights = tp.unitPoints[0].unitWeight * tp.unitPoints[1].unitWeight;
            // Calculate IDF from epsilon rate and f(K,D)
            // (weightAgent * numComponents + weightComponent * numAgents) / (weightComponent * weightAgent)
            uint256 codeUnits = (tp.unitPoints[1].unitWeight * tp.unitPoints[0].numNewUnits +
                tp.unitPoints[0].unitWeight * tp.unitPoints[1].numNewUnits) / sumWeights;
            // f(K(e), D(e)) = d * k * K(e) + d * D(e)
            // fKD = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
            // Convert all the necessary values to fixed-point numbers considering OLAS decimals (18 by default)
            // Convert treasuryRewards and convert to ETH
            int256 fp1 = PRBMathSD59x18.fromInt(int256(rewards[1])) / 1e18;
            // Convert (codeUnits * devsPerCapital)
            int256 fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.epochPoint.devsPerCapital));
            // fp1 == codeUnits * devsPerCapital * treasuryRewards
            fp1 = fp1.mul(fp2);
            // fp2 = codeUnits * newOwners
            fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.epochPoint.numNewOwners));
            // fp = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
            int256 fp = fp1 + fp2;
            // fp = fp/100 - calculate the final value in fixed point
            fp = fp.div(PRBMathSD59x18.fromInt(100));
            // fKD in the state that is comparable with epsilon rate
            uint256 fKD = uint256(fp);

            // Compare with epsilon rate and choose the smallest one
            if (fKD > epsilonRate) {
                fKD = epsilonRate;
            }
            // 1 + fKD in the system where 1e18 is equal to a whole unit (18 decimals)
            idf = uint64(1e18 + fKD);
        }

        // Record settled epoch point values
        tp.epochPoint.endBlockNumber = uint32(block.number);
        tp.epochPoint.endTime = uint32(block.timestamp);

        // Allocate rewards via Treasury and start new epoch
        uint96 accountRewards = uint96(rewards[2] + rewards[3] + rewards[4]);
        // Owner top-ups: epoch incentives for component owners funded with the inflation
        rewards[6] = (inflationPerEpoch * topUpComponentFraction) / 100;
        // Owner top-ups: epoch incentives for agent owners funded with the inflation
        rewards[7] = (inflationPerEpoch * topUpAgentFraction) / 100;
        // Staker top-ups: epoch incentives for veOLAS lockers funded with the inflation
        rewards[8] = (inflationPerEpoch * topUpStakerFraction) / 100;
        uint96 accountTopUps = uint96(rewards[8]);
        // Add owner top-ups only if there was at least one donating service owner that had a sufficient veOLAS balance
        // This means that it is safe to check for the sum related to OLAS top-ups in agents,
        // since a service has at least one agent, and each agent has at least one component
        if (tp.unitPoints[1].sumUnitTopUpsOLAS > 0) {
            accountTopUps += uint96(rewards[6] + rewards[7]);
        }

        // Treasury contract allocates rewards
        if (rewards[1] == 0 || ITreasury(treasury).rebalanceTreasury(rewards[1])) {
            // Emit settled epoch written to the last economics point
            emit EpochSettled(eCounter, rewards[1], accountRewards, accountTopUps);
            // Start new epoch
            eCounter++;
            epochCounter = uint32(eCounter);
        } else {
            // If rewards were not correctly allocated, the new epoch does not start
            revert TreasuryRebalanceFailed(eCounter);
        }

        // Record reward and top-up values
        // TODO Check for zero values
        tp.unitPoints[0].unitRewards = uint96(rewards[3]);
        tp.unitPoints[1].unitRewards = uint96(rewards[4]);
        tp.epochPoint.stakerRewards = uint96(rewards[1]);
        tp.unitPoints[0].unitTopUps = uint96(rewards[6]);
        tp.unitPoints[1].unitTopUps = uint96(rewards[7]);
        tp.epochPoint.stakerTopUps = uint96(rewards[8]);

        // Copy current tokenomics point into the next one such that it has necessary tokenomics parameters
        mapEpochTokenomics[eCounter].unitPoints[0].unitWeight = tp.unitPoints[0].unitWeight;
        mapEpochTokenomics[eCounter].unitPoints[1].unitWeight = tp.unitPoints[1].unitWeight;
        mapEpochTokenomics[eCounter].epochPoint.devsPerCapital = tp.epochPoint.devsPerCapital;
        mapEpochTokenomics[eCounter].epochPoint.idf = idf;

        return true;
    }

    /// @dev Gets staking incentives.
    /// @notice To be eligible for the n-th epoch incentives, have a non-zero veOLAS balance in the (n-1)-th epoch.
    /// @notice This distribution criteria is used in order to eliminate front-runners that observe incoming donations.
    /// @param account Account address.
    /// @param startEpochNumber Epoch number at which the reward starts being calculated.
    /// @return reward Reward amount up to the last possible epoch.
    /// @return topUp Top-up amount up to the last possible epoch.
    /// @return endEpochNumber Epoch number where the reward calculation will start the next time.
    function getStakingIncentives(address account, uint256 startEpochNumber) external view
        returns (uint256 reward, uint256 topUp, uint256 endEpochNumber)
    {
        // There is no reward in the first epoch yet
        if (startEpochNumber < 2) {
            startEpochNumber = 2;
        }

        uint256 eCounter = epochCounter;
        // Loop over epoch points to calculate incentives according to the staking fraction
        for (endEpochNumber = startEpochNumber; endEpochNumber < eCounter; ++endEpochNumber) {
            // Last block number of a previous epoch
            uint256 iBlock = mapEpochTokenomics[endEpochNumber - 1].epochPoint.endBlockNumber - 1;
            // Get account's balance at the end of a previous epoch
            uint256 balance = IVotingEscrow(ve).balanceOfAt(account, iBlock);

            // If there was no locking / staking, skip the reward computation
            if (balance > 0) {
                // Get the total supply at the last block of the epoch
                uint256 supply = IVotingEscrow(ve).totalSupplyAt(iBlock);

                // Add to the reward depending on the staker reward
                if (supply > 0) {
                    // reward = balance * stakerRewards / supply
                    reward += (balance * mapEpochTokenomics[endEpochNumber].epochPoint.stakerRewards) / supply;

                    // topUp = balance * stakerTopUps / supply
                    topUp += (balance * mapEpochTokenomics[endEpochNumber].epochPoint.stakerTopUps) / supply;
                }
            }
        }
    }

    /// @dev Gets inflation per last epoch.
    /// @return inflationPerEpoch Inflation value.
    function getInflationPerEpoch() external view returns (uint256 inflationPerEpoch) {
        inflationPerEpoch = inflationPerSecond * epochLen;
    }

    /// @dev Gets epoch point of a specified epoch number.
    /// @param epoch Epoch number.
    /// @return ep Epoch point.
    function getEpochPoint(uint256 epoch) external view returns (EpochPoint memory ep) {
        ep = mapEpochTokenomics[epoch].epochPoint;
    }

    /// @dev Gets component / agent point of a specified epoch number and a unit type.
    /// @param epoch Epoch number.
    /// @param unitType Component (0) or agent (1).
    /// @return up Unit point.
    function getUnitPoint(uint256 epoch, uint256 unitType) external view returns (UnitPoint memory up) {
        up = mapEpochTokenomics[epoch].unitPoints[unitType];
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18.
    /// @param epoch Epoch number.
    /// @return idf Discount factor with the multiple of 1e18.
    function getIDF(uint256 epoch) external view returns (uint256 idf)
    {
        // TODO if IDF is undefined somewhere, we must return 1 but not the maximum possible
        idf = mapEpochTokenomics[epoch].epochPoint.idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf)
    {
        idf = mapEpochTokenomics[epochCounter - 1].epochPoint.idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets component / agent owner incentives and clears the balances.
    /// @notice `account` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `account` were provided, they will be untouched and keep accumulating.
    /// @param account Account address.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerIncentives(address account, uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp)
    {
        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        // Check array lengths
        if (unitTypes.length != unitIds.length) {
            revert WrongArrayLength(unitTypes.length, unitIds.length);
        }

        // Component / agent registry addresses
        address[] memory registries = new address[](2);
        (registries[0], registries[1]) = (componentRegistry, agentRegistry);

        // Check the ownership of unitIds
        for (uint256 i = 0; i < unitIds.length; ++i) {
            // Check for the unit type to be component / agent only
            if (unitTypes[i] > 1) {
                revert Overflow(unitTypes[i], 1);
            }

            // Check the component / agent Id ownership
            address unitOwner = IToken(registries[unitTypes[i]]).ownerOf(unitIds[i]);
            if (unitOwner != account) {
                revert OwnerOnly(unitOwner, account);
            }
        }

        // Get the current epoch counter
        uint256 curEpoch = epochCounter;

        for (uint256 i = 0; i < unitIds.length; ++i) {
            // Get the last epoch number the incentives were accumulated for
            uint256 lastEpoch = mapUnitIncentives[unitTypes[i]][unitIds[i]].lastEpoch;
            // Finalize component rewards and top-ups if there were pending ones from the previous epoch
            if (lastEpoch > 0 && lastEpoch < curEpoch) {
                _finalizeIncentivesForUnitId(lastEpoch, unitTypes[i], unitIds[i]);
                // Change the last epoch number
                mapUnitIncentives[unitTypes[i]][unitIds[i]].lastEpoch = 0;
            }

            // Accumulate total rewards and clear their balances
            reward += mapUnitIncentives[unitTypes[i]][unitIds[i]].reward;
            mapUnitIncentives[unitTypes[i]][unitIds[i]].reward = 0;
            // Accumulate total top-ups and clear their balances
            topUp += mapUnitIncentives[unitTypes[i]][unitIds[i]].topUp;
            mapUnitIncentives[unitTypes[i]][unitIds[i]].topUp = 0;
        }
    }

    // TODO Make sure unitIds are unique otherwise the calculation will be wrong
    /// @dev Gets the component / agent owner incentives.
    /// @notice `account` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @param account Account address.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function getOwnerIncentives(address account, uint256[] memory unitTypes, uint256[] memory unitIds) external view
        returns (uint256 reward, uint256 topUp)
    {
        // Check array lengths
        if (unitTypes.length != unitIds.length) {
            revert WrongArrayLength(unitTypes.length, unitIds.length);
        }

        // Component / agent registry addresses
        address[] memory registries = new address[](2);
        (registries[0], registries[1]) = (componentRegistry, agentRegistry);

        // Check the ownership of unitIds
        for (uint256 i = 0; i < unitIds.length; ++i) {
            // Check for the unit type to be component / agent only
            if (unitTypes[i] > 1) {
                revert Overflow(unitTypes[i], 1);
            }

            // Check the component / agent Id ownership
            address unitOwner = IToken(registries[unitTypes[i]]).ownerOf(unitIds[i]);
            if (unitOwner != account) {
                revert OwnerOnly(unitOwner, account);
            }
        }

        // Get the current epoch counter
        uint256 curEpoch = epochCounter;

        for (uint256 i = 0; i < unitIds.length; ++i) {
            // Get the last epoch number the incentives were accumulated for
            uint256 lastEpoch = mapUnitIncentives[unitTypes[i]][unitIds[i]].lastEpoch;
            // Calculate rewards and top-ups if there were pending ones from the previous epoch
            if (lastEpoch > 0 && lastEpoch < curEpoch) {
                // Get the overall amount of component rewards for the component's last epoch
                // reward = (pendingRelativeReward * unitRewards) / sumUnitDonationsETH
                uint256 totalIncentives = mapUnitIncentives[unitTypes[i]][unitIds[i]].pendingRelativeReward;
                totalIncentives *= mapEpochTokenomics[lastEpoch].unitPoints[unitTypes[i]].unitRewards;
                uint256 sumUnitIncentives = mapEpochTokenomics[lastEpoch].unitPoints[unitTypes[i]].sumUnitDonationsETH;
                // Accumulate to the final reward for the last epoch
                reward += totalIncentives / sumUnitIncentives;
                // Add the final top-up for the last epoch
                if (mapUnitIncentives[unitTypes[i]][unitIds[i]].pendingRelativeTopUp > 0) {
                    // Summation of all the unit top-ups and total amount of top-ups per epoch
                    // topUp = (pendingRelativeTopUp * unitTopUps) / sumUnitTopUpsOLAS
                    totalIncentives = mapUnitIncentives[unitTypes[i]][unitIds[i]].pendingRelativeTopUp;
                    totalIncentives *= mapEpochTokenomics[lastEpoch].unitPoints[unitTypes[i]].unitTopUps;
                    sumUnitIncentives = mapEpochTokenomics[lastEpoch].unitPoints[unitTypes[i]].sumUnitTopUpsOLAS;
                    // Accumulate to the final top-up for the last epoch
                    topUp += totalIncentives / sumUnitIncentives;
                }
            }

            // Accumulate total rewards to finalized ones
            reward += mapUnitIncentives[unitTypes[i]][unitIds[i]].reward;
            // Accumulate total top-ups to finalized ones
            topUp += mapUnitIncentives[unitTypes[i]][unitIds[i]].topUp;
        }
    }

    /// @dev Gets incentive balances of a component / agent.
    /// @param unitType Unit type (component or agent).
    /// @param unitId Unit Id.
    /// @return Component / agent incentive balances.
    function getIncentiveBalances(uint256 unitType, uint256 unitId) external view returns (IncentiveBalances memory) {
        return mapUnitIncentives[unitType][unitId];
    }
}    
