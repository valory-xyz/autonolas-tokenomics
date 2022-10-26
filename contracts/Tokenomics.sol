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
// The size of the struct is 32 * 2 + 96 * 2 + 32 * 2 + 16 * 2 = 256 + 96 bits (2 full slots)
struct PointUnits {
    // Total absolute number of components / agents
    // We assume that the system is expected to support no more than 2^32-1 units
    // This assumption is compatible with Autonolas registries that have same bounds for units
    uint32 numUnits;
    // Number of components / agents that were part of profitable services
    // Profitable units are a subset of the units, so this number cannot be bigger than the absolute number of units
    uint32 numProfitableUnits;
    // Allocated rewards for components / agents
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 unitRewards;
    // Cumulative UCFc-s / UCFa-s: sum of all UCFc-s or all UCFa-s
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 ucfuSum;
    // Number of new units
    // This number cannot be practically bigger than the total number of supported units
    uint32 numNewUnits;
    // Number of new owners
    // Each unit has at most one owner, so this number cannot be practically bigger than numNewUnits
    uint32 numNewOwners;
    // We assume the coefficients are bound by numbers of 2^16 - 1
    // Coefficient weight of units for the final UCF formula, set by the governance
    uint16 ucfWeight;
    // Component / agent weight for new valuable code
    uint16 unitWeight;
}

// Structure for tokenomics
// The size of the struct is 512 * 2 + 64 + 32 + 96 * 6 + 32 * 3 = 256 * 4 + 128 + 32 (5 full slots)
struct PointEcomonics {
    // UCFc
    PointUnits ucfc;
    // UCFa
    PointUnits ucfa;
    // Inverse of the discount factor
    // IDF is bound by a factor of 18, since (2^64 - 1) / 10^18 > 18
    // The IDF depends on the epsilonRate value, idf = 1 + epsilonRate, and epsilonRate is bound by 17 with 18 decimals
    uint64 idf;
    // Profitable number of services
    // We assume that the system is expected to support no more than 2^32-1 services
    uint32 numServices;
    // Treasury rewards
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 treasuryRewards;
    // Staking rewards
    uint96 stakerRewards;
    // Donation in ETH
    uint96 totalDonationETH;
    // Top-ups for component / agent owners
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 ownerTopUps;
    // Top-ups for stakers
    uint96 stakerTopUps;
    // Number of valuable devs can be paid per units of capital per epoch
    // This number cannot be practically bigger than the total number of supported units
    uint32 devsPerCapital;
    // Block number
    // With the current number of seconds per block and the current block number, 2^32 - 1 is enough for the next 1600+ years
    uint32 blockNumber;
    // Timestamp
    // 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970, which is safe until the year of 2106
    uint32 epochTime;
}

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is TokenomicsConstants, GenericTokenomics {
    // TODO Just substitute with 10**18?
    using PRBMathSD59x18 for *;

    event EpochLengthUpdated(uint256 epochLength);
    event TokenomicsParametersUpdates(uint256 ucfcWeight, uint256 ucfaWeight, uint256 componentWeight,
        uint256 agentWeight, uint256 devsPerCapital, uint256 epsilonRate, uint256 epochLen);
    event IncentiveFractionsUpdated(uint256 stakerFraction, uint256 componentFraction, uint256 agentFraction,
        uint256 maxBondFraction, uint256 topUpOwnerFraction);
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
    uint32 public epochCounter = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    // This number cannot be practically bigger than the total number of supported units
    uint32 public devsPerCapital = 1;

    // Inflation amount per second
    uint96 public inflationPerSecond;
    // Total service donation per epoch: sum(r(s))
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public epochServiceDonationETH;
    // TODO Check if ucfc(a)Weight and componentWeight / agentWeight are the same
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
    // Staking parameters (in percentage)
    // treasuryFraction (implicitly set to zero by default) + componentFraction + agentFraction + stakerFraction = 100%
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 public stakerFraction = 50;
    uint8 public componentFraction = 33;
    uint8 public agentFraction = 17;
    // maxBond and top-ups of OLAS parameters (in percentage)
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 public maxBondFraction = 40;
    uint8 public topUpOwnerFraction = 40;
    // Current year number
    // This number is enough for the next 255 years
    uint8 currentYear;

    // Service Registry
    address public serviceRegistry;

    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) public mapServiceAmounts;
    // Mapping of owner of component / agent address => reward amount (in ETH)
    mapping(address => uint256) public mapOwnerRewards;
    // Mapping of owner of component / agent address => top-up amount (in OLAS)
    mapping(address => uint256) public mapOwnerTopUps;
    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;
    // Map of component Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapComponents;
    // Map of agent Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapAgents;
    // Mapping of owner of component / agent addresses that create them
    mapping(address => bool) public mapOwners;
    // Set of protocol-owned services in current epoch
    uint32[] public protocolServiceIds;

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

        // Calculating initial inflation per second derived from the zero year inflation amount
        uint256 _inflationPerSecond = 22_113_000_0e17 / zeroYearSecondsLeft;
        inflationPerSecond = uint96(_inflationPerSecond);

        // Calculate initial effectiveBond based on the maxBond during the first epoch
        uint256 _maxBond = _inflationPerSecond * _epochLen * maxBondFraction;
        maxBond = uint96(_maxBond);
        effectiveBond = uint96(_maxBond);
    }

    /// @dev Checks if the maxBond update is within allowed limits for effectiveBond, adjusts maxBond and effectiveBond.
    /// @param nextMaxBond Proposed next epoch maxBond.
    function adjustMaxBond(uint256 nextMaxBond) internal {
        uint256 curMaxBond = maxBond;
        uint256 curEffectiveBond = effectiveBond;
        // The new epochLen is shorter than the current one
        if (curMaxBond > nextMaxBond) {
            // Get the difference of the maxBond
            curMaxBond -= nextMaxBond;
            // Update the value for the effectiveBond if there is room for it
            if (curEffectiveBond > curMaxBond) {
                curEffectiveBond -= curMaxBond;
            } else {
                // Otherwise effectiveBond cannot be reduced further, and the current epochLen cannot be shortened
                revert AmountLowerThan(curEffectiveBond, curMaxBond);
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
    /// @param _ucfcWeight UCFc weighs for the UCF contribution.
    /// @param _ucfaWeight UCFa weight for the UCF contribution.
    /// @param _componentWeight Component weight for new valuable code.
    /// @param _agentWeight Agent weight for new valuable code.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    /// @param _epsilonRate Epsilon rate that contributes to the interest rate value.
    /// @param _epochLen New epoch length.
    function changeTokenomicsParameters(
        uint16 _ucfcWeight,
        uint16 _ucfaWeight,
        uint16 _componentWeight,
        uint16 _agentWeight,
        uint32 _devsPerCapital,
        uint64 _epsilonRate,
        uint32 _epochLen
    ) external
    {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        ucfcWeight = _ucfcWeight;
        ucfaWeight = _ucfaWeight;
        componentWeight = _componentWeight;
        agentWeight = _agentWeight;
        devsPerCapital = _devsPerCapital;

        // Check the epsilonRate value for idf to fit in its size
        // 2^64 - 1 < 18.5e18, idf is equal at most 1 + epsilonRate < 18e18, which fits in the variable size
        if (_epsilonRate < 17e18) {
            epsilonRate = _epsilonRate;
        }

        // Check for the epochLen value to change
        uint256 oldEpochLen = epochLen;
        if (oldEpochLen != _epochLen) {
            // Actual current year
            uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
            uint256 curYear = currentYear;
            // Check if the year changes in the current epoch and revert if it is the case
            if (numYears > curYear) {
                revert Overflow(numYears, curYear);
            }

            // Actual year plus two proposed epochLens
            numYears = (block.timestamp + 2 * _epochLen - timeLaunch) / oneYear;
            // Check if the year is going to change in two epochs and revert if it is the case
            if (numYears > currentYear) {
                revert Overflow(numYears, curYear);
            }

            // Calculate next maxBond based on the proposed epochLen
            uint256 nextMaxBond = inflationPerSecond * maxBondFraction * _epochLen;
            // Adjust maxBond and effectiveBond, if they are within the allowed limits
            adjustMaxBond(nextMaxBond);

            // Update the epochLen
            epochLen = _epochLen;
        }

        emit TokenomicsParametersUpdates(_ucfcWeight, _ucfaWeight, _componentWeight, _agentWeight, _devsPerCapital,
            _epsilonRate, _epochLen);
    }

    /// @dev Sets incentive parameter fractions.
    /// @param _stakerFraction Fraction for stakers.
    /// @param _componentFraction Fraction for component owners.
    /// @param _agentFraction Fraction for agent owners.
    /// @param _topUpOwnerFraction Fraction for OLAS top-up for component / agent owners.
    /// @param _maxBondFraction Fraction for the maxBond.
    function changeIncentiveFractions(
        uint8 _stakerFraction,
        uint8 _componentFraction,
        uint8 _agentFraction,
        uint8 _maxBondFraction,
        uint8 _topUpOwnerFraction,
        uint8 _topUpStakerFraction
    ) external
    {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that the sum of fractions is 100%
        if (_stakerFraction + _componentFraction + _agentFraction > 100) {
            revert WrongAmount(_stakerFraction + _componentFraction + _agentFraction, 100);
        }

        // Same check for OLAS-related fractions
        if (_maxBondFraction + _topUpOwnerFraction > 100) {
            revert WrongAmount(_topUpOwnerFraction + _topUpStakerFraction, 100);
        }

        stakerFraction = _stakerFraction;
        componentFraction = _componentFraction;
        agentFraction = _agentFraction;

        // Check if the maxBondFraction changes
        uint256 oldMaxBondFraction = maxBondFraction;
        if (oldMaxBondFraction != _maxBondFraction) {
            // Actual current year
            uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
            uint256 curYear = currentYear;
            // Check if the year changes in the current epoch and revert if it is the case
            // This is done to prevent the change of the maxBond that was calculated from two parts accounting for the year change
            if (numYears > curYear) {
                revert Overflow(numYears, curYear);
            }

            // Calculate next maxBond based on the proposed maxBondFraction
            uint256 nextMaxBond = inflationPerSecond * _maxBondFraction * epochLen;
            // Adjust maxBond and effectiveBond, if they are within the allowed limits
            adjustMaxBond(nextMaxBond);

            // Update the maxBondFraction
            maxBondFraction = _maxBondFraction;
        }
        topUpOwnerFraction = _topUpOwnerFraction;

        emit IncentiveFractionsUpdated(_stakerFraction, _componentFraction, _agentFraction, _maxBondFraction, _topUpOwnerFraction);
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

    /// @dev Refunds unused bond program amount.
    /// @param amount Amount to be refunded from the bond program.
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

        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existence
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            // TODO whitelist service Ids whose owners stake veOLAS (with a minimum threshold)
            // Add a new service Id to the set of Ids if one was not currently in it
            if (mapServiceAmounts[serviceIds[i]] == 0) {
                protocolServiceIds.push(serviceIds[i]);
            }
            mapServiceAmounts[serviceIds[i]] += amounts[i];
            donationETH += amounts[i];
        }
        // Increase the total service donation balance per epoch
        epochServiceDonationETH += donationETH;
    }

    /// @dev Calculates tokenomics for components / agents based on service donations.
    /// @param unitType Unit type as component or agent.
    /// @param unitRewards Component / agent allocated rewards.
    /// @param unitTopUps Component / agent allocated top-ups.
    /// @param numServices Number of services with provided donations.
    /// @return ucfu Calculated UCFc / UCFa.
    function _calculateUnitTokenomics(IServiceTokenomics.UnitType unitType, uint256 unitRewards, uint256 unitTopUps, uint256 numServices)
        internal returns (PointUnits memory ucfu)
    {
        // Array of numbers of units per each service Id
        uint256[] memory numServiceUnits = new uint256[](numServices);
        // 2D array of all the sets of units per each service Id
        uint32[][] memory serviceUnitIds = new uint32[][](numServices);

        // TODO Possible optimization is to store a set of componets / agents and the map of those used in protocol-owned services
        address registry = unitType == IServiceTokenomics.UnitType.Component ? componentRegistry: agentRegistry;
        ucfu.numUnits = uint32(IToken(registry).totalSupply());
        // Set of agent revenues UCFu-s. Agent / component Ids start from "1", so the index can be equal to the set size
        uint256[] memory ucfuRevs = new uint256[](ucfu.numUnits + 1);
        // Set of agent revenues UCFu-s divided by the cardinality of agent Ids in each service
        uint256[] memory ucfus = new uint256[](numServices);
        // Overall profits of UCFu-s
        uint256 sumProfits = 0;

        // Loop over profitable service Ids to calculate initial UCFu-s
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = protocolServiceIds[i];
            (numServiceUnits[i], serviceUnitIds[i]) = IServiceTokenomics(serviceRegistry).getUnitIdsOfService(unitType, serviceId);
            // Add to UCFa part for each agent Id
            uint256 amount = mapServiceAmounts[serviceId];
            // Release gas allocated for the service amount when passing through agents for the calculation of UCFa
            // Since UCFa is calculated after UCFc, this is safe to do. If they were to change, deletion must be done
            // during the UCFc calculation
            if (unitType == IServiceTokenomics.UnitType.Agent) {
                delete mapServiceAmounts[serviceId];
            }
            for (uint256 j = 0; j < numServiceUnits[i]; ++j) {
                // Sum the amounts for the corresponding components / agents
                ucfuRevs[serviceUnitIds[i][j]] += amount;
                sumProfits += amount;
            }
        }

        // Calculate all complete UCFu-s divided by the cardinality of unit Ids in each service
        for (uint256 i = 0; i < numServices; ++i) {
            for (uint256 j = 0; j < numServiceUnits[i]; ++j) {
                // Sum(UCFu[i]) / |Us(epoch)|
                ucfus[i] += ucfuRevs[serviceUnitIds[i][j]];
            }
            ucfus[i] /= numServiceUnits[i];
        }

        // Calculate component / agent related values
        for (uint256 i = 0; i < ucfu.numUnits; ++i) {
            // Get the agent Id from the index list
            // For our architecture it's the identity function (see tokenByIndex() in autonolas-registries)
            uint256 unitId = i + 1;
            if (ucfuRevs[unitId] > 0) {
                // Add address of a profitable component owner
                address unitOwner = IToken(registry).ownerOf(unitId);
                // Increase a profitable agent number
                ++ucfu.numProfitableUnits;
                // Calculate agent rewards in ETH
                mapOwnerRewards[unitOwner] += (unitRewards * ucfuRevs[unitId]) / sumProfits;
                // Calculate OLAS top-ups
                uint256 amountOLAS = (unitTopUps * ucfuRevs[unitId]) / sumProfits;
                if (unitType == IServiceTokenomics.UnitType.Component) {
                    amountOLAS = (amountOLAS * componentWeight) / (componentWeight + agentWeight);
                } else {
                    amountOLAS = (amountOLAS * agentWeight)  / (componentWeight + agentWeight);
                }
                mapOwnerTopUps[unitOwner] += amountOLAS;

                // Check if the component / agent is used for the first time
                if (unitType == IServiceTokenomics.UnitType.Component && !mapComponents[unitId]) {
                    ucfu.numNewUnits++;
                    mapComponents[unitId] = true;
                } else {
                    ucfu.numNewUnits++;
                    mapAgents[unitId] = true;
                }
                // Check if the owner has introduced component / agent for the first time 
                if (!mapOwners[unitOwner]) {
                    mapOwners[unitOwner] = true;
                    ucfu.numNewOwners++;
                }
            }
        }

        // Calculate total UCFu
        sumProfits = 0;
        for (uint256 i = 0; i < numServices; ++i) {
            sumProfits += ucfus[i];
        }
        ucfu.ucfuSum = uint96(sumProfits);
        // Record unit rewards and number of units
        ucfu.unitRewards = uint96(unitRewards);
    }

    // TODO Double check we are always in sync with correct rewards allocation, i.e., such that we calculate rewards and don't allocate them
    // TODO Figure out how to call checkpoint automatically, i.e. with a keeper
    /// @dev Record global data to new checkpoint
    /// @return True if the function execution is successful.
    function checkpoint() external returns (bool) {
        // New point can be calculated only if we passed the number of blocks equal to the epoch length
        uint256 prevEpochTime = mapEpochEconomics[epochCounter - 1].epochTime;
        uint256 diffNumSeconds = block.timestamp - prevEpochTime;
        uint256 curEpochLen = epochLen;
        if (diffNumSeconds < curEpochLen) {
            return false;
        }

        // 0: total rewards funded with donations in ETH, that are split between:
        // 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        uint256[] memory rewards = new uint256[](8);
        rewards[0] = epochServiceDonationETH;
        rewards[2] = (rewards[0] * stakerFraction) / 100;
        rewards[3] = (rewards[0] * componentFraction) / 100;
        rewards[4] = (rewards[0] * agentFraction) / 100;
        // Treasury reward calculation
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];

        uint256 inflationPerEpoch;
        // Get the maxBond that was credited to effectiveBond during this settled epoch
        // If the year changes, the maxBond for the next epoch is updated in the condition below and will be used
        // later when the effectiveBond is updated for the next epoch
        uint256 curMaxBond = maxBond;
        // Current year
        uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
        // Account for the year change to adjust inflation numbers
        if (numYears > currentYear) {
            // Calculate remainder of inflation for the passing year
            uint256 curInflationPerSecond = inflationPerSecond;
            // End of the year timestamp
            uint256 yearEndTime = timeLaunch + numYears * oneYear;
            // Initial inflation per epoch during the end of the year minus previous epoch timestamp
            inflationPerEpoch = (yearEndTime - prevEpochTime) * curInflationPerSecond;
            // Recalculate inflation per second based on a new year inflation
            curInflationPerSecond = getInflationForYear(numYears) / oneYear;
            // Add the remainder of inflation amount for this epoch based on a new inflation per nex year ratio
            inflationPerEpoch += (block.timestamp - yearEndTime) * curInflationPerSecond;
            // Update the maxBond value for the next epoch after the year changes
            maxBond = uint96(curInflationPerSecond * curEpochLen);
            // Updating state variables
            inflationPerSecond = uint96(curInflationPerSecond);
            currentYear = uint8(numYears);
        } else {
            inflationPerEpoch = inflationPerSecond * diffNumSeconds;
        }

        // Bonding and top-ups in OLAS are recalculated based on the inflation schedule per epoch
        // OLAS inflation is split between:
        // 5: maxBond, 6: ownerTopUps, 7: stakerTopUps
        rewards[5] = (inflationPerEpoch * maxBondFraction) / 100;
        rewards[6] = (inflationPerEpoch * topUpOwnerFraction) / 100;
        // Calculation of OLAS top-ups for stakers
        rewards[7] = inflationPerEpoch - rewards[5] - rewards[6];

        // Effective bond accumulates bonding leftovers from previous epochs (with the last max bond value set)
        // It is given the value of the maxBond for the next epoch as a credit
        // The difference between recalculated max bond per epoch and maxBond value must be reflected in effectiveBond,
        // since the epoch checkpoint delay was not accounted for initially
        // TODO optimize for gas usage below
        // TODO Prove that the adjusted maxBond (rewards[5]) will never be lower than the epoch maxBond
        rewards[5] = effectiveBond + rewards[5] - curMaxBond;
        effectiveBond = uint96(rewards[5]);

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
            curMaxBond = (yearEndTime - block.timestamp) * curInflationPerSecond * maxBondFraction;
            // Recalculate inflation per second based on a new year inflation
            curInflationPerSecond = getInflationForYear(numYears) / oneYear;
            // Add the remainder of max bond amount for the next epoch based on a new inflation per the next year ratio
            curMaxBond += (block.timestamp + curEpochLen - yearEndTime) * curInflationPerSecond * maxBondFraction;
            maxBond = uint96(curMaxBond);
        } else {
            // This assignment is done again to account for the maxBond value that could change if we are currently
            // in the epoch with a changing year
            curMaxBond = maxBond;
        }
        // Update effectiveBond with the current or updated maxBond value
        effectiveBond += uint96(curMaxBond);

        // idf = 1 / (1 + iterest_rate), reverse_df = 1/df >= 1.0.
        uint64 idf;
        // Calculate UCFc, UCFa, rewards allocated from them and IDF
        PointUnits memory ucfc;
        PointUnits memory ucfa;
        uint256 numServices = protocolServiceIds.length;
        if (rewards[0] > 0) {
            // Calculate total UCFc
            ucfc = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Component, rewards[3], rewards[6], numServices);
            ucfc.ucfWeight = uint8(ucfcWeight);
            ucfc.unitWeight = uint8(componentWeight);

            // Calculate total UCFa
            ucfa = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Agent, rewards[4], rewards[6], numServices);
            ucfa.ucfWeight = uint8(ucfaWeight);
            ucfa.unitWeight = uint8(agentWeight);

            // Calculate IDF from epsilon rate and f(K,D)
            uint256 codeUnits = ucfc.unitWeight * ucfc.numNewUnits + ucfa.unitWeight * ucfa.numNewUnits;
            uint256 newOwners = ucfc.numNewOwners + ucfa.numNewOwners;
            // f(K(e), D(e)) = d * k * K(e) + d * D(e)
            // fKD = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
            // Convert all the necessary values to fixed-point numbers considering OLAS decimals (18 by default)
            // Convert treasuryRewards and convert to ETH
            int256 fp1 = PRBMathSD59x18.fromInt(int256(rewards[1])) / 1e18;
            // Convert (codeUnits * devsPerCapital)
            int256 fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * devsPerCapital));
            // fp1 == codeUnits * devsPerCapital * treasuryRewards
            fp1 = fp1.mul(fp2);
            // fp2 = codeUnits * newOwners
            fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * newOwners));
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

        // Record settled epoch point
        PointEcomonics memory newPoint = PointEcomonics(ucfc, ucfa, idf, uint32(numServices), uint96(rewards[1]),
            uint96(rewards[2]), epochServiceDonationETH, uint96(rewards[6]), uint96(rewards[7]), devsPerCapital,
            uint32(block.number), uint32(block.timestamp));
        uint32 eCounter = epochCounter;
        mapEpochEconomics[eCounter] = newPoint;

        // Clears necessary data structures for the next epoch.
        delete protocolServiceIds;
        epochServiceDonationETH = 0;

        // Allocate rewards via Treasury and start new epoch
        uint96 accountRewards = uint96(rewards[2]) + ucfc.unitRewards + ucfa.unitRewards;
        uint96 accountTopUps = uint96(rewards[6] + rewards[7]);

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
            uint96 stakerRewards = mapEpochEconomics[endEpochNumber].stakerRewards;
            uint96 stakerTopUps = mapEpochEconomics[endEpochNumber].stakerTopUps;
            // Last block number of a previous epoch
            uint256 iBlock = mapEpochEconomics[endEpochNumber - 1].blockNumber - 1;
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
    /// @return pe raw point
    function getPoint(uint256 epoch) external view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epoch];
    }

    /// @dev Gets last epoch Point.
    function getLastPoint() external view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epochCounter - 1];
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18.
    /// @param epoch Epoch number.
    /// @return idf Discount factor with the multiple of 1e18.
    function getIDF(uint256 epoch) external view returns (uint256 idf)
    {
        // TODO if IDF si undefined somewhere, we must return 1 but not the maximum possible
        idf = mapEpochEconomics[epoch].idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf)
    {
        idf = mapEpochEconomics[epochCounter - 1].idf;
        if (idf == 0) {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Calculated UCF of a specified epoch.
    /// @param epoch Epoch number.
    /// @return ucf UCF value with the multiple of 1e18.
    function getUCF(uint256 epoch) external view returns (uint256 ucf) {
        PointEcomonics memory pe = mapEpochEconomics[epoch];

        // Total rewards per epoch
        uint256 totalRewards = pe.treasuryRewards + pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;

        // Calculate UCFc
        uint256 denominator = totalRewards * pe.numServices * pe.ucfc.numUnits;
        int256 ucfc;
        // Number of components can be equal to zero for all the services, so the UCFc is just zero by default
        if (denominator > 0) {
            // UCFC = (numProfitableUnits * Sum(UCFc)) / (totalRewards * numServices * numUnits(c))
            ucfc = PRBMathSD59x18.div(PRBMathSD59x18.fromInt(int256(uint256(pe.ucfc.numProfitableUnits * pe.ucfc.ucfuSum))),
                PRBMathSD59x18.fromInt(int256(denominator)));

            // Calculate UCFa
            denominator = totalRewards * pe.numServices * pe.ucfa.numUnits;
            // Number of agents must always be greater than zero, since at least one agent is used by a service
            if (denominator > 0) {
                // UCFA = (numProfitableUnits * Sum(UCFa)) / (totalRewards * numServices * numUnits(a))
                int256 ucfa = PRBMathSD59x18.div(PRBMathSD59x18.fromInt(int256(uint256(pe.ucfa.numProfitableUnits * pe.ucfa.ucfuSum))),
                    PRBMathSD59x18.fromInt(int256(denominator)));

                // Calculate UCF
                denominator = pe.ucfc.ucfWeight + pe.ucfa.ucfWeight;
                if (denominator > 0) {
                    // UCF = (ucfc * ucfWeight(c) + ucfa * ucfWeight(a)) / (ucfWeight(c) + ucfWeight(a))
                    int256 weightedUCFc = ucfc.mul(PRBMathSD59x18.fromInt(int256(uint256(pe.ucfc.ucfWeight))));
                    int256 weightedUCFa = ucfa.mul(PRBMathSD59x18.fromInt(int256(uint256(pe.ucfa.ucfWeight))));
                    int256 ucfFP = weightedUCFc + weightedUCFa;
                    ucfFP = ucfFP.div(PRBMathSD59x18.fromInt(int256(denominator)));
                    ucf = uint256(ucfFP);
                }
            }
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

    /// @dev Gets the component / agent owner reward and zeros the record of it being written off.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerRewards(address account) external returns (uint256 reward, uint256 topUp) {
        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
        mapOwnerRewards[account] = 0;
        mapOwnerTopUps[account] = 0;
    }
}    
