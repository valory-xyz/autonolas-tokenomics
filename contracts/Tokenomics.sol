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

// Structure for component / agent tokenomics-related statistics
// The size of the struct is 96 * 2 + 32 + 8 * 2 = 240 bits (1 full slot)
struct UnitPoint {
    // Summation of all the ETH donations accounting for each component / agent in a service
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 sumUnitDonationsETH;
    // Summation of all the OLAS top-ups accounting for each component in a service
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 sumUnitTopUpsOLAS;
    // Number of new units
    // This number cannot be practically bigger than the total number of supported units
    uint32 numNewUnits;
    // Reward component / agent fraction
    // This number cannot be practically bigger than 100 as the summation with other fractions gives at most 100 (%)
    uint8 rewardUnitFraction;
    // Top-up component / agent fraction
    // This number cannot be practically bigger than 100 as the summation with other fractions gives at most 100 (%)
    uint8 topUpUnitFraction;
}

// Structure for tokenomics
// The size of the struct is 256 * 2 + 96 * 2 + 64 + 32 * 4 + 8 * 2 = 256 * 3 + 128 + 16 (4 full slots)
struct TokenomicsPoint {
    // Component point
    UnitPoint componentPoint;
    // Agent point
    UnitPoint agentPoint;
    // Donation in ETH
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 totalDonationsETH;
    // Top-ups in OLAS
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 totalTopUpsOLAS;
    // Inverse of the discount factor
    // IDF is bound by a factor of 18, since (2^64 - 1) / 10^18 > 18
    // The IDF depends on the epsilonRate value, idf = 1 + epsilonRate, and epsilonRate is bound by 17 with 18 decimals
    uint64 idf;
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
    // Staking parameters (in percentage)
    // treasuryFraction (implicitly set to zero by default) + rewardComponentFraction + rewardAgentFraction + rewardStakerFraction = 100%
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 rewardStakerFraction;
    // maxBond and top-ups of OLAS parameters (in percentage)
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 maxBondFraction;
    // TODO Decide whether to add topUpstakerFraction as well or have it subtracted from 100 in-place
}

// Struct for component / agent owner incentive balances
struct IncentiveBalances {
    // Reward in ETH
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 reward;
    // Pending reward in ETH
    uint96 pendingReward;
    // Top-up in OLAS
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 topUp;
    // Pending top-up
    uint96 pendingTopUp;
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
    event TokenomicsParametersUpdates(uint256 devsPerCapital, uint256 epsilonRate, uint256 epochLen, uint256 veOLASThreshold);
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
    // TODO Change to seconds
    // Epoch length in seconds
    // By design, the epoch length cannot be practically bigger than one year, or 31_536_000 seconds
    uint32 public epochLen;
    // Global epoch counter
    // This number cannot be practically bigger than the number of blocks
    uint32 public epochCounter;
    // Number of valuable devs can be paid per units of capital per epoch
    // This number cannot be practically bigger than the total number of supported units
    uint32 public devsPerCapital = 1;

    // Inflation amount per second
    uint96 public inflationPerSecond;
    // TODO: Get the final veOLAS amount requirement
    // veOLAS threshold for top-ups
    // This number cannot be practically bigger than the number of OLAS tokens
    uint96 public veOLASThreshold = 5_000e18;
    // TODO Check if componentPoint(a)Weight and componentWeight / agentWeight are the same
    // TODO component weight is 2 by default, agent weight is 1
    // UCFc / UCFa weights for the UCF contribution
    // We assume the coefficients are bound by 2^16 - 1
    uint16 public ucfcWeight = 1;
    uint16 public ucfaWeight = 1;
    // Component / agent weights for new valuable code
    uint16 public componentWeight = 1;
    uint16 public agentWeight = 1;

    // Component Registry
    address public componentRegistry;
    // effectiveBond = sum(MaxBond(e)) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    // Effective bond is updated before the start of the next epoch such that the bonding limits are accounted for
    // This number cannot be practically bigger than the inflation remainder of OLAS
    uint96 public effectiveBond;

    // Agent Registry
    address public agentRegistry;
    // Current year number
    // This number is enough for the next 255 years
    uint8 public currentYear;
    // maxBond-related parameter change locker
    uint8 public lockMaxBond = 1;

    // Service Registry
    address public serviceRegistry;

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
        mapEpochTokenomics[0].endTime = uint32(block.timestamp);

        // The epoch counter starts from 1
        epochCounter = 1;
        TokenomicsPoint storage tp = mapEpochTokenomics[1];

        // Setting initial ratios
        tp.rewardStakerFraction = 50;
        tp.componentPoint.rewardUnitFraction = 33;
        tp.agentPoint.rewardUnitFraction = 17;

        tp.maxBondFraction = 50;
        tp.componentPoint.topUpUnitFraction = 33;
        tp.agentPoint.topUpUnitFraction = 17;

        // Calculate initial effectiveBond based on the maxBond during the first epoch
        uint256 _maxBond = _inflationPerSecond * _epochLen * 50 / 100;
        maxBond = uint96(_maxBond);
        effectiveBond = uint96(_maxBond);
    }

    /// @dev Checks if the maxBond update is within allowed limits of the effectiveBond, and adjusts maxBond and effectiveBond.
    /// @param nextMaxBond Proposed next epoch maxBond.
    function _adjustMaxBond(uint256 nextMaxBond) internal {
        uint256 curMaxBond = maxBond;
        uint256 curEffectiveBond = effectiveBond;
        // If the new epochLen is shorter than the current one, the current maxBond is bigger than the proposed one
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

        mapEpochTokenomics[epochCounter].devsPerCapital = _devsPerCapital;

        // Check the epsilonRate value for idf to fit in its size
        // 2^64 - 1 < 18.5e18, idf is equal at most 1 + epsilonRate < 18e18, which fits in the variable size
        if (_epsilonRate < 17e18) {
            epsilonRate = _epsilonRate;
        }

        // Check for the epochLen value to change
        uint256 oldEpochLen = epochLen;
        if (oldEpochLen != _epochLen) {
            // Check if the year change is ongoing in the current epoch, and thus maxBond cannot be changed
            if (lockMaxBond == 2) {
                revert MaxBondUpdateLocked();
            }

            // Check if the bigger proposed length of the epoch end time results in a scenario when the year changes
            if (_epochLen > oldEpochLen) {
                // End time of the last epoch
                uint256 lastEpochEndTime = mapEpochTokenomics[epochCounter - 1].endTime;
                // Actual year of the time when the epoch is going to finish with the proposed epoch length
                uint256 numYears = (lastEpochEndTime + _epochLen - timeLaunch) / oneYear;
                // Check if the year is going to change
                if (numYears > currentYear) {
                    revert MaxBondUpdateLocked();
                }
            }

            // Calculate next maxBond based on the proposed epochLen
            uint256 nextMaxBond = inflationPerSecond * mapEpochTokenomics[epochCounter].maxBondFraction * _epochLen / 100;
            // Adjust maxBond and effectiveBond, if they are within the allowed limits
            _adjustMaxBond(nextMaxBond);

            // Update the epochLen
            epochLen = _epochLen;
        }

        veOLASThreshold = _veOLASThreshold;

        emit TokenomicsParametersUpdates(_devsPerCapital, _epsilonRate, _epochLen, _veOLASThreshold);
    }

    /// @dev Sets incentive parameter fractions.
    /// @param _rewardStakerFraction Fraction for stakers.
    /// @param _rewardComponentFraction Fraction for component owners.
    /// @param _rewardAgentFraction Fraction for agent owners.
    /// @param _maxBondFraction Fraction for the maxBond.
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
        if (_maxBondFraction + _topUpComponentFraction > 100) {
            revert WrongAmount(_maxBondFraction + _topUpComponentFraction + _topUpAgentFraction, 100);
        }

        TokenomicsPoint storage tp = mapEpochTokenomics[epochCounter];
        tp.rewardStakerFraction = _rewardStakerFraction;
        tp.componentPoint.rewardUnitFraction = _rewardComponentFraction;
        tp.agentPoint.rewardUnitFraction = _rewardAgentFraction;

        // Check if the maxBondFraction changes
        uint256 oldMaxBondFraction = tp.maxBondFraction;
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
            tp.maxBondFraction = _maxBondFraction;
        }
        tp.componentPoint.topUpUnitFraction = _topUpComponentFraction;
        tp.agentPoint.topUpUnitFraction = _topUpAgentFraction;

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
    function reserveAmountForBondProgram(uint96 amount) external returns (bool success) {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        // Effective bond must be bigger than the requested amount
        if ((effectiveBond + 1) > amount) {
            // The value of effective bond is then adjusted to the amount that is now reserved for bonding
            // The unrealized part of the bonding amount will be returned when the bonding program is closed
            effectiveBond -= amount;
            success = true;
        }
    }

    /// @dev Refunds unused bond program amount when the program is closed.
    /// @param amount Amount to be refunded from the closed bond program.
    function refundFromBondProgram(uint96 amount) external {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        effectiveBond += amount;
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

            // Check if the service owner stakes enough OLAS for its components / agents to get a top-up
            address serviceOwner = IToken(serviceRegistry).ownerOf(serviceIds[i]);
            bool topUpEligible = IVotingEscrow(ve).getVotes(serviceOwner) > veOLASThreshold ? true : false;

            // Loop over component and agent Ids
            for (uint256 unitType = 0; unitType < 2; ++unitType) {
                // Get the number and set of units in the service
                (uint256 numServiceUnits, uint32[] memory serviceUnitIds) = IServiceTokenomics(serviceRegistry).
                    getUnitIdsOfService(IServiceTokenomics.UnitType(unitType), serviceIds[i]);
                // Add to UCFu part for each unit Id
                for (uint256 j = 0; j < numServiceUnits; ++j) {
                    // Get the last epoch number the incentives were accumulated for
                    uint256 lastEpoch = mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch;
                    // Check if there were no donations in previous epochs and set the current epoch
                    if (lastEpoch == 0) {
                        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
                    }
                    // Finalize component rewards and top-ups if there were pending ones from the previous epoch
                    if (lastEpoch < curEpoch) {
                        // Get the overall amount of component rewards for the component's last epoch
                        // Summation of all the unit rewards
                        uint256 sumUnitIncentives;
                        // Total amount of rewards per epoch
                        uint256 totalIncentives;
                        if (unitType == 0) {
                            sumUnitIncentives = mapEpochTokenomics[lastEpoch].componentPoint.sumUnitDonationsETH;
                            totalIncentives = mapEpochTokenomics[lastEpoch].totalDonationsETH *
                                mapEpochTokenomics[lastEpoch].componentPoint.rewardUnitFraction / 100;
                        } else {
                            sumUnitIncentives = mapEpochTokenomics[lastEpoch].agentPoint.sumUnitDonationsETH;
                            totalIncentives = mapEpochTokenomics[lastEpoch].totalDonationsETH *
                                mapEpochTokenomics[lastEpoch].agentPoint.rewardUnitFraction / 100;
                        }
                        // Add the final reward for the last epoch
                        mapUnitIncentives[unitType][serviceUnitIds[j]].reward +=
                            uint96(mapUnitIncentives[unitType][serviceUnitIds[j]].pendingReward * totalIncentives / sumUnitIncentives);
                        // Setting pending reward to zero
                        mapUnitIncentives[unitType][serviceUnitIds[j]].pendingReward = 0;
                        // Add the final top-up for the last epoch
                        if (mapUnitIncentives[unitType][serviceUnitIds[j]].pendingTopUp > 0) {
                            // Summation of all the unit top-ups and total amount of top-ups per epoch
                            if (unitType == 0) {
                                sumUnitIncentives = mapEpochTokenomics[lastEpoch].componentPoint.sumUnitTopUpsOLAS;
                                totalIncentives = mapEpochTokenomics[lastEpoch].totalTopUpsOLAS *
                                    mapEpochTokenomics[lastEpoch].componentPoint.topUpUnitFraction / 100;
                                mapUnitIncentives[unitType][serviceUnitIds[j]].topUp +=
                                    uint96(mapUnitIncentives[unitType][serviceUnitIds[j]].pendingTopUp * totalIncentives /
                                    sumUnitIncentives);
                            } else {
                                sumUnitIncentives = mapEpochTokenomics[lastEpoch].agentPoint.sumUnitTopUpsOLAS;
                                totalIncentives = mapEpochTokenomics[lastEpoch].totalTopUpsOLAS *
                                    mapEpochTokenomics[lastEpoch].agentPoint.rewardUnitFraction / 100;
                                mapUnitIncentives[unitType][serviceUnitIds[j]].topUp +=
                                    uint96(mapUnitIncentives[unitType][serviceUnitIds[j]].pendingTopUp * totalIncentives /
                                    sumUnitIncentives);
                            }
                            // Setting pending top-up to zero
                            mapUnitIncentives[unitType][serviceUnitIds[j]].pendingTopUp = 0;
                        }
                        // Change the last epoch number
                        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
                    }
                    // Sum the amounts for the corresponding components / agents
                    mapUnitIncentives[unitType][serviceUnitIds[j]].pendingReward += amounts[i];
                    if (unitType == 0) {
                        mapEpochTokenomics[curEpoch].componentPoint.sumUnitDonationsETH += amounts[i];
                    } else {
                        mapEpochTokenomics[curEpoch].agentPoint.sumUnitDonationsETH += amounts[i];
                    }
                    // Same for the tup-ups, if eligible
                    if (topUpEligible) {
                        mapUnitIncentives[unitType][serviceUnitIds[j]].pendingTopUp += amounts[i];
                        if (unitType == 0) {
                            mapEpochTokenomics[curEpoch].componentPoint.sumUnitTopUpsOLAS += amounts[i];
                        } else {
                            mapEpochTokenomics[curEpoch].agentPoint.sumUnitTopUpsOLAS += amounts[i];
                        }
                    }
    
                    // Check if the component / agent is used for the first time
                    if (!mapNewUnits[unitType][serviceUnitIds[j]]) {
                        mapNewUnits[unitType][serviceUnitIds[j]] = true;
                        if (unitType == 0) {
                            tp.componentPoint.numNewUnits++;
                        } else {
                            tp.agentPoint.numNewUnits++;
                        }
                        // Check if the owner has introduced component / agent for the first time
                        // This is done together with the new unit check, otherwise it could be just a new unit owner
                        address unitOwner = IToken(registries[unitType]).ownerOf(serviceUnitIds[j]);
                        if (!mapNewOwners[unitOwner]) {
                            mapNewOwners[unitOwner] = true;
                            tp.numNewOwners++;
                        }
                    }
                }
            }

            // Sum up ETH service amounts
            donationETH += amounts[i];
        }

        // Increase the total service donation balance per epoch
        donationETH = tp.totalDonationsETH + donationETH;
        tp.totalDonationsETH = donationETH;
    }

    // TODO Double check we are always in sync with correct rewards allocation, i.e., such that we calculate rewards and don't allocate them
    // TODO Figure out how to call checkpoint automatically, i.e. with a keeper
    /// @dev Record global data to new checkpoint
    /// @return True if the function execution is successful.
    function checkpoint() external returns (bool) {
        // New point can be calculated only if we passed the number of blocks equal to the epoch length
        uint256 prevEpochTime = mapEpochTokenomics[epochCounter - 1].endTime;
        uint256 diffNumSeconds = block.timestamp - prevEpochTime;
        uint256 curEpochLen = epochLen;
        if (diffNumSeconds < curEpochLen) {
            return false;
        }

        uint32 eCounter = epochCounter;
        TokenomicsPoint storage tp = mapEpochTokenomics[eCounter];

        // 0: total rewards funded with donations in ETH, that are split between:
        // 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // OLAS inflation is split between:
        // 5: maxBond, 6: component ownerTopUps, 7: agent ownerTopUps, 8: stakerTopUps
        uint256[] memory rewards = new uint256[](9);
        rewards[0] = tp.totalDonationsETH;

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
            maxBond = uint96(curInflationPerSecond * curEpochLen * tp.maxBondFraction) / 100;
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
        tp.totalTopUpsOLAS = uint96(inflationPerEpoch);
        rewards[5] = (inflationPerEpoch * tp.maxBondFraction) / 100;

        // Effective bond accumulates bonding leftovers from previous epochs (with the last max bond value set)
        // It is given the value of the maxBond for the next epoch as a credit
        // The difference between recalculated max bond per epoch and maxBond value must be reflected in effectiveBond,
        // since the epoch checkpoint delay was not accounted for initially
        // TODO optimize for gas usage below
        // TODO Prove that the adjusted maxBond (rewards[5]) will never be lower than the epoch maxBond
        // This has to always be true, or rewards[5] == curMaxBond if the epoch is settled exactly at the epochLen time
        if (rewards[5] > curMaxBond) {
            // Adjust the effectiveBond
            rewards[5] = effectiveBond + rewards[5] - curMaxBond;
            effectiveBond = uint96(rewards[5]);
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
            curMaxBond = (yearEndTime - block.timestamp) * curInflationPerSecond * tp.maxBondFraction / 100;
            // Recalculate the inflation per second based on the new inflation for the current year
            curInflationPerSecond = getInflationForYear(numYears) / oneYear;
            // Add the remainder of max bond amount for the next epoch based on a new inflation per second ratio
            curMaxBond += (block.timestamp + curEpochLen - yearEndTime) * curInflationPerSecond * tp.maxBondFraction / 100;
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

        // idf = 1 / (1 + iterest_rate), reverse_df = 1/df >= 1.0.
        uint64 idf;
        if (rewards[0] > 0) {
            // TODO: Recalculate component and agent weights correctly based on the corresponding fractions
            uint256 sumWeights = tp.componentPoint.topUpUnitFraction + tp.agentPoint.topUpUnitFraction;
            // Calculate IDF from epsilon rate and f(K,D)
            uint256 codeUnits = (tp.componentPoint.topUpUnitFraction * tp.componentPoint.numNewUnits +
                tp.agentPoint.topUpUnitFraction * tp.agentPoint.numNewUnits) / sumWeights;
            // f(K(e), D(e)) = d * k * K(e) + d * D(e)
            // fKD = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
            // Convert all the necessary values to fixed-point numbers considering OLAS decimals (18 by default)
            // Convert treasuryRewards and convert to ETH
            int256 fp1 = PRBMathSD59x18.fromInt(int256(rewards[1])) / 1e18;
            // Convert (codeUnits * devsPerCapital)
            int256 fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.devsPerCapital));
            // fp1 == codeUnits * devsPerCapital * treasuryRewards
            fp1 = fp1.mul(fp2);
            // fp2 = codeUnits * newOwners
            fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.numNewOwners));
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
        tp.idf = idf;
        tp.endBlockNumber = uint32(block.number);
        tp.endTime = uint32(block.timestamp);

        // Allocate rewards via Treasury and start new epoch
        rewards[2] = (rewards[0] * tp.rewardStakerFraction) / 100;
        rewards[3] = (rewards[0] * tp.componentPoint.rewardUnitFraction) / 100;
        rewards[4] = (rewards[0] * tp.agentPoint.rewardUnitFraction) / 100;
        // Treasury reward calculation
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];
        uint96 accountRewards = uint96(rewards[2] + rewards[3] + rewards[4]);
        // TODO do not mint the accumulated amount of OLAS, but mint directly to the claimer. The array values can be then deleted
        // Owner top-ups: epoch incentives for component owners funded with the inflation
        rewards[6] = (inflationPerEpoch * tp.componentPoint.topUpUnitFraction) / 100;
        // Owner top-ups: epoch incentives for agent owners funded with the inflation
        rewards[7] = (inflationPerEpoch * tp.agentPoint.topUpUnitFraction) / 100;
        // Staker top-ups: epoch incentives for veOLAS lockers funded with the inflation
        rewards[8] = inflationPerEpoch - rewards[5] - rewards[6];
        uint96 accountTopUps = uint96(rewards[6] + rewards[7] + rewards[8]);

        // Treasury contract allocates rewards
        if (ITreasury(treasury).allocateRewards(uint96(rewards[1]), accountRewards, accountTopUps)) {
            // Emit settled epoch written to the last economics point
            emit EpochSettled(eCounter, rewards[1], accountRewards, accountTopUps);
            // Start new epoch
            eCounter++;
            epochCounter = eCounter;
        } else {
            // If rewards were not correctly allocated, the new epoch does not start
            revert RewardsAllocationFailed(eCounter);
        }

        // TODO Make sure we are not copying something that is not supposed to be used in the next epoch
        // Copy current tokenomics point into the next one such that it has necessary tokenomics parameters
        mapEpochTokenomics[eCounter] = tp;

        return true;
    }

    /// @dev Calculates staking rewards.
    /// @param account Account address.
    /// @param startEpochNumber Epoch number at which the reward starts being calculated.
    /// @return reward Reward amount up to the last possible epoch.
    /// @return topUp Top-up amount up to the last possible epoch.
    /// @return endEpochNumber Epoch number where the reward calculation will start the next time.
    function calculateStakingRewards(address account, uint256 startEpochNumber) external view
        returns (uint256 reward, uint256 topUp, uint256 endEpochNumber)
    {
        // There is no reward in the first epoch yet
        if (startEpochNumber < 2) {
            startEpochNumber = 2;
        }

        for (endEpochNumber = startEpochNumber; endEpochNumber < epochCounter; ++endEpochNumber) {
            // Epoch point where the current epoch info is recorded
            // stakerRewards = rewardStakerFraction * totalDonationsETH / 100
            uint96 stakerRewards = mapEpochTokenomics[endEpochNumber].rewardStakerFraction *
                mapEpochTokenomics[endEpochNumber].totalDonationsETH / 100;
            // TODO Estimate the gas cost of storing stakerTopUpsFraction instead of calculating it via subtraction, as mentioned above
            // stakerTopUps = (100 - maxBondFraction - componentTopUpsFraction - agentTopUpsFraction) * totalTopUpsOLAS / 100
            uint96 stakerTopUps = (100 - mapEpochTokenomics[endEpochNumber].maxBondFraction - mapEpochTokenomics[endEpochNumber].componentPoint.topUpUnitFraction -
                mapEpochTokenomics[endEpochNumber].agentPoint.topUpUnitFraction) * mapEpochTokenomics[endEpochNumber].totalTopUpsOLAS / 100;
            // Last block number of a previous epoch
            uint256 iBlock = mapEpochTokenomics[endEpochNumber - 1].endBlockNumber - 1;
            // Get account's balance at the end of epoch
            uint256 balance = IVotingEscrow(ve).balanceOfAt(account, iBlock);

            // If there was no locking / staking, we skip the reward computation
            if (balance > 0) {
                // Get the total supply at the last block of the epoch
                uint256 supply = IVotingEscrow(ve).totalSupplyAt(iBlock);

                // Add to the reward depending on the staker reward
                if (supply > 0) {
                    reward += (balance * stakerRewards) / supply;
                    topUp += (balance * stakerTopUps) / supply;
                }
            }
        }
    }

    /// @dev Gets top-up value for epoch.
    /// @return topUp Top-up value.
    function getTopUpPerEpoch() external view returns (uint256 topUp) {
        topUp = inflationPerSecond * epochLen;
    }

    /// @dev get Point by epoch
    /// @param epoch number of a epoch
    /// @return tp raw point
    function getPoint(uint256 epoch) external view returns (TokenomicsPoint memory tp) {
        tp = mapEpochTokenomics[epoch];
    }

    /// @dev Gets last epoch Point.
    function getLastPoint() external view returns (TokenomicsPoint memory tp) {
        tp = mapEpochTokenomics[epochCounter - 1];
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18.
    /// @param epoch Epoch number.
    /// @return idf Discount factor with the multiple of 1e18.
    function getIDF(uint256 epoch) external view returns (uint256 idf)
    {
        // TODO if IDF si undefined somewhere, we must return 1 but not the maximum possible
        idf = mapEpochTokenomics[epoch].idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf)
    {
        idf = mapEpochTokenomics[epochCounter - 1].idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets the component / agent owner reward.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function getOwnerRewards(address account) external view returns (uint256 reward, uint256 topUp) {
        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
    }

    // TODO Revise according to the new incentives allocation algorithm
    /// @dev Gets the component / agent owner reward and zeros the record of it being written off.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerRewards(address account) external returns (uint256 reward, uint256 topUp) {
        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        // TODO if lastEpoch > 0 && lastEpoch < curEpoch, finalize incentives and delete the struct (free gas and zero lastEpoch value)
        // TODO Otherwise just zero finalized incentives

        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
        mapOwnerRewards[account] = 0;
        mapOwnerTopUps[account] = 0;
    }
}    
