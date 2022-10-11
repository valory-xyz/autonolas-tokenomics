// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@partylikeits1983/statistics_solidity/contracts/dependencies/prb-math/PRBMathSD59x18.sol";
import "./GenericTokenomics.sol";
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
// The size of the struct is 512 * 2 + 64 + 32 + 96 * 6 + 32 * 2 = 256 * 4 + 128 (5 full slots)
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
    // Block number.
    // With the current number of seconds per block and the current block number, 2^32 - 1 is enough for the next 1600+ years
    uint32 blockNumber;
}

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is GenericTokenomics {
    using PRBMathSD59x18 for *;

    event EpochLengthUpdated(uint32 epochLength);
    event TokenomicsParametersUpdates(uint16 ucfcWeight, uint16 ucfaWeight, uint16 componentWeight, uint16 agentWeight,
        uint32 devsPerCapital, uint64 epsilonRate, uint96 maxBond, uint32 epochLen, uint8 blockTimeETH, bool bondAutoControl);
    event RewardFractionsUpdated(uint8 stakerFraction, uint8 componentFraction, uint8 agentFraction,
        uint8 topUpOwnerFraction, uint8 topUpStakerFraction);
    event ComponentRegistryUpdated(address indexed componentRegistry);
    event AgentRegistryUpdated(address indexed agentRegistry);
    event ServiceRegistryUpdated(address indexed serviceRegistry);

    // Voting Escrow address
    address public immutable ve;

    // TODO Review max bond per epoch depending on the number of epochs per year, and the updated inflation schedule
    // ~150k of OLAS tokens per epoch (less than the max cap of 22 million during 1st year, the bonding fraction is 40%)
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 public maxBond = 150_000 * 1e18;
    // Default epsilon rate that contributes to the interest rate: 10% or 0.1
    // We assume that for the IDF calculation epsilonRate must be lower than 17 (with 18 decimals)
    // (2^64 - 1) / 10^18 > 18, however IDF = 1 + epsilonRate, thus we limit epsilonRate by 17 with 18 decimals at most
    uint64 public epsilonRate = 1e17;
    // Epoch length in block numbers
    // With the current number of seconds per block, 2^32 - 1 is enough for the length of epoch to be 1600+ years
    uint32 public epochLen;
    // Global epoch counter
    // This number cannot be practically bigger than the number of blocks
    uint32 public epochCounter = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    // This number cannot be practically bigger than the total number of supported units
    uint32 public devsPerCapital = 1;

    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    // Total service revenue per epoch: sum(r(s))
    uint96 public epochServiceRevenueETH;
    // Donation balance
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public donationBalanceETH;
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
    // Bond per epoch
    // This number cannot be practically bigger than the inflation remainder of OLAS
    uint96 public bondPerEpoch;

    // Agent Registry
    address public agentRegistry;
    // MaxBond(e) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    // This number cannot be practically bigger than the maxBond
    uint96 public effectiveBond = maxBond;

    // Service Registry
    address public serviceRegistry;
    // ETH average block time in seconds
    // We assume that the block time will not be bigger than 255 seconds
    uint8 public blockTimeETH = 12;
    // Staking parameters (in percentage)
    // treasuryFraction (implicitly set to zero by default) + componentFraction + agentFraction + stakerFraction = 100%
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 public stakerFraction = 50;
    uint8 public componentFraction = 33;
    uint8 public agentFraction = 17;
    // Top-up of OLAS and bonding parameters (in percentage)
    // Each of these numbers cannot be practically bigger than 100 as they sum up to 100%
    uint8 public topUpOwnerFraction = 40;
    uint8 public topUpStakerFraction = 20;
    // Manual or auto control of max bond
    bool public bondAutoControl;

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
    // Map of protocol-owned service Ids
    mapping(uint256 => bool) public mapProtocolServices;
    // Inflation caps for the first ten years
    uint96[] public inflationCaps;
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
    GenericTokenomics(_olas, address(this), _treasury, _depository, _dispenser, TokenomicsRole.Tokenomics)
    {
        ve = _ve;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;

        // Initial allocation is 526_500_000_0e17
        inflationCaps = new uint96[](10);
        inflationCaps[0] = 548_613_000_0e17;
        inflationCaps[1] = 628_161_885_0e17;
        inflationCaps[2] = 701_028_663_7e17;
        inflationCaps[3] = 766_084_123_6e17;
        inflationCaps[4] = 822_958_209_0e17;
        inflationCaps[5] = 871_835_342_9e17;
        inflationCaps[6] = 913_259_378_7e17;
        inflationCaps[7] = 947_973_171_3e17;
        inflationCaps[8] = 976_799_806_9e17;
        inflationCaps[9] = 1_000_000_000e18;
    }

    /// @dev Changes tokenomics parameters.
    /// @param _ucfcWeight UCFc weighs for the UCF contribution.
    /// @param _ucfaWeight UCFa weight for the UCF contribution.
    /// @param _componentWeight Component weight for new valuable code.
    /// @param _agentWeight Agent weight for new valuable code.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    /// @param _epsilonRate Epsilon rate that contributes to the interest rate value.
    /// @param _maxBond MaxBond OLAS, 18 decimals.
    /// @param _epochLen New epoch length.
    /// @param _blockTimeETH Time between blocks for ETH.
    /// @param _bondAutoControl True to enable auto-tuning of max bonding value depending on the OLAS remainder
    function changeTokenomicsParameters(
        uint16 _ucfcWeight,
        uint16 _ucfaWeight,
        uint16 _componentWeight,
        uint16 _agentWeight,
        uint32 _devsPerCapital,
        uint64 _epsilonRate,
        uint96 _maxBond,
        uint32 _epochLen,
        uint8 _blockTimeETH,
        bool _bondAutoControl
    ) external {
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
        // take into account the change during the epoch
        _adjustMaxBond(_maxBond);
        epochLen = _epochLen;
        blockTimeETH = _blockTimeETH;
        bondAutoControl = _bondAutoControl;

        emit TokenomicsParametersUpdates(_ucfcWeight, _ucfaWeight, _componentWeight, _agentWeight, _devsPerCapital,
            _epsilonRate, _maxBond, _epochLen, _blockTimeETH, _bondAutoControl);
    }

    /// @dev Sets staking parameters in fractions of distributed rewards.
    /// @param _stakerFraction Fraction for stakers.
    /// @param _componentFraction Fraction for component owners.
    /// @param _agentFraction Fraction for agent owners.
    /// @param _topUpOwnerFraction Fraction for OLAS top-up for component / agent owners.
    /// @param _topUpStakerFraction Fraction for OLAS top-up for stakers.
    function changeRewardFraction(
        uint8 _stakerFraction,
        uint8 _componentFraction,
        uint8 _agentFraction,
        uint8 _topUpOwnerFraction,
        uint8 _topUpStakerFraction
    ) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that the sum of fractions is 100%
        if (_stakerFraction + _componentFraction + _agentFraction > 100) {
            revert WrongAmount(_stakerFraction + _componentFraction + _agentFraction, 100);
        }

        // Same check for OLAS-related fractions
        if (_topUpOwnerFraction + _topUpStakerFraction > 100) {
            revert WrongAmount(_topUpOwnerFraction + _topUpStakerFraction, 100);
        }

        stakerFraction = _stakerFraction;
        componentFraction = _componentFraction;
        agentFraction = _agentFraction;

        topUpOwnerFraction = _topUpOwnerFraction;
        topUpStakerFraction = _topUpStakerFraction;

        emit RewardFractionsUpdated(_stakerFraction, _componentFraction, _agentFraction, _topUpOwnerFraction, _topUpStakerFraction);
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

    /// @dev (De-)whitelists protocol-owned services.
    /// @param serviceIds Set of service Ids.
    /// @param permissions Set of corresponding permissions for each account address.
    function changeProtocolServicesWhiteList(uint256[] memory serviceIds, bool[] memory permissions) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint256 numServices = serviceIds.length;
        // Check the array size
        if (permissions.length != numServices) {
            revert WrongArrayLength(numServices, permissions.length);
        }
        for (uint256 i = 0; i < numServices; ++i) {
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            mapProtocolServices[serviceIds[i]] = permissions[i];
        }
    }

    /// @dev Checks for the OLAS minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLAS tokens to mint.
    /// @return allowed True if the mint is allowed.
    function isAllowedMint(uint256 amount) external returns (bool allowed) {
        uint256 remainder = _getInflationRemainderForYear();
        // For the first 10 years we check the inflation cap that is pre-defined
        if (amount < (remainder + 1)) {
            allowed = true;
        }
    }

    /// @dev Gets remainder of possible OLAS allocation for the current year.
    /// @return remainder OLAS amount possible to mint.
    function _getInflationRemainderForYear() internal returns (uint256 remainder) {
        // OLAS token time launch
        uint256 timeLaunch = IOLAS(olas).timeLaunch();
        // One year of time
        uint256 oneYear = 1 days * 365;
        // Current year
        uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
        // For the first 10 years we check the inflation cap that is pre-defined
        if (numYears < 10) {
            // OLAS token supply to-date
            uint256 supply = IToken(olas).totalSupply();
            remainder = inflationCaps[numYears] - supply;
        } else {
            remainder = IOLAS(olas).inflationRemainder();
        }
    }

    /// @dev Checks if the the effective bond value per current epoch is enough to allocate the specific amount.
    /// @notice Programs exceeding the limit in the epoch are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return success True if effective bond threshold is not reached.
    function allowedNewBond(uint96 amount) external returns (bool success)  {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        uint256 remainder = _getInflationRemainderForYear();
        if (effectiveBond >= amount && amount < (remainder + 1)) {
            effectiveBond -= amount;
            success = true;
        }
    }

    /// @dev Increases the epoch bond with the OLAS payout for a Depository program
    /// @param payout Payout amount for the LP pair.
    function updateEpochBond(uint96 payout) external {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        bondPerEpoch += payout;
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    function trackServicesETHRevenue(uint32[] memory serviceIds, uint96[] memory amounts) external
        returns (uint96 revenueETH, uint96 donationETH)
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
            // Check for the whitelisted services
            if (mapProtocolServices[serviceIds[i]]) {
                // If this is a protocol-owned service, accept funds as revenue
                // Add a new service Id to the set of Ids if one was not currently in it
                if (mapServiceAmounts[serviceIds[i]] == 0) {
                    protocolServiceIds.push(serviceIds[i]);
                }
                mapServiceAmounts[serviceIds[i]] += amounts[i];
                revenueETH += amounts[i];
            } else {
                // If the service is not a protocol-owned one, accept funds as donation
                donationETH += amounts[i];
            }
        }
        // Increase the total service revenue per epoch and donation balance
        epochServiceRevenueETH += revenueETH;
        donationBalanceETH += donationETH;
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
            if (registry == agentRegistry) {
                delete mapServiceAmounts[serviceId];
            }
            for (uint256 j = 0; j < numServiceUnits[i]; ++j) {
                // Sum the amounts for the corresponding components / agents
                ucfuRevs[serviceUnitIds[i][j]] += amount;
                sumProfits += amount;
            }
        }

        // Calculate all complete UCFu-s divided by the cardinality of agent Ids in each service
        for (uint256 i = 0; i < numServices; ++i) {
            for (uint256 j = 0; j < numServiceUnits[i]; ++j) {
                // Sum(UCFa[i]) / |As(epoch)|
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

    /// @dev Adjusts max bond every epoch if max bond is contract-controlled.
    function _adjustMaxBond(uint96 _maxBond) internal {
        // take into account the change during the epoch
        uint96 delta;
        if(_maxBond > maxBond) {
            delta = _maxBond - maxBond;
            effectiveBond += delta;
        }
        if(_maxBond < maxBond) {
            delta = maxBond - _maxBond;
            if(delta < effectiveBond) {
                effectiveBond -= delta;
            } else {
                effectiveBond = 0;
            }
        }
        maxBond = _maxBond;
    }

    /// @dev Gets top-up value for epoch.
    /// @return topUp Top-up value.
    function getTopUpPerEpoch() external view returns (uint256 topUp) {
        topUp = (IOLAS(olas).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
    }

    // TODO Make sure it is impossible to call it without reward allocation, since it would break the synchronization of rewards
    /// @dev Record global data to new checkpoint
    /// @return True if the function execution is successful.
    function checkpoint() external returns (bool) {
        // New point can be calculated only if we passed the number of blocks equal to the epoch length
        uint256 diffNumBlocks = block.number - mapEpochEconomics[epochCounter - 1].blockNumber;
        if (diffNumBlocks < epochLen) {
            return false;
        }

        // Get total amount of OLAS as profits for rewards, and all the rewards categories
        // 0: total rewards, 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // 5: topUpOwnerFraction, 6: topUpStakerFraction, 7: bondFraction
        uint256[] memory rewards = new uint256[](8);
        rewards[0] = epochServiceRevenueETH;
        rewards[2] = (rewards[0] * stakerFraction) / 100;
        rewards[3] = (rewards[0] * componentFraction) / 100;
        rewards[4] = (rewards[0] * agentFraction) / 100;
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];

        // Top-ups and bonding possibility in OLAS are recalculated based on the inflation schedule per epoch
        uint256 totalTopUps = (IOLAS(olas).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
        // TODO must be based on bondPerEpoch or ibased on inflation, if the flag is set
        rewards[5] = (totalTopUps * topUpOwnerFraction) / 100;
        rewards[6] = (totalTopUps * topUpStakerFraction) / 100;
        rewards[7] = totalTopUps - rewards[5] - rewards[6];

        // Effective bond accumulates leftovers from previous epochs (with last max bond value set)
        if (maxBond > bondPerEpoch) {
            effectiveBond += maxBond - bondPerEpoch;
        }
        // Bond per epoch starts from zero every epoch
        bondPerEpoch = 0;
        // Adjust max bond and effective bond if contract-controlled max bond is enabled
        if (bondAutoControl) {
            _adjustMaxBond(uint96(rewards[7]));
        }

        // idf = 1/(1 + iterest_rate) by documentation, reverse_df = 1/df >= 1.0.
        uint64 idf;
        // Calculate UCFc, UCFa, rewards allocated from them and IDF
        PointUnits memory ucfc;
        PointUnits memory ucfa;
        uint256 numServices = protocolServiceIds.length;
        if (rewards[0] > 0) {
            // Calculate total UCFc
            ucfc = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Component, rewards[3], rewards[5], numServices);
            ucfc.ucfWeight = uint8(ucfcWeight);
            ucfc.unitWeight = uint8(componentWeight);

            // Calculate total UCFa
            ucfa = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Agent, rewards[4], rewards[5], numServices);
            ucfa.ucfWeight = uint8(ucfaWeight);
            ucfa.unitWeight = uint8(agentWeight);

            // Calculate IDF from epsilon rate and f(K,D)
            uint256 codeUnits = componentWeight * ucfc.numNewUnits + agentWeight * ucfa.numNewUnits;
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

        // Record a new point epoch
        PointEcomonics memory newPoint = PointEcomonics(ucfc, ucfa, idf, uint32(numServices), uint96(rewards[1]),
            uint96(rewards[2]), donationBalanceETH, uint96(rewards[5]), uint96(rewards[6]), devsPerCapital,
            uint32(block.number));
        mapEpochEconomics[epochCounter] = newPoint;
        epochCounter++;

        // Clears necessary data structures for the next epoch.
        delete protocolServiceIds;
        epochServiceRevenueETH = 0;

        // Allocate rewards via Treasury
        uint96 accountRewards = uint96(rewards[2]) + ucfc.unitRewards + ucfa.unitRewards;
        uint96 accountTopUps = uint96(rewards[5] + rewards[6]);
        return ITreasury(treasury).allocateRewards(uint96(rewards[1]), accountRewards, accountTopUps);
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
            PointEcomonics memory pe = mapEpochEconomics[endEpochNumber];
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
                    reward += (balance * pe.stakerRewards) / supply;
                    topUp += (balance * pe.stakerTopUps) / supply;
                }
            }
        }
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
        PointEcomonics memory pe = mapEpochEconomics[epoch];
        if (pe.idf > 0) {
            idf = pe.idf;
        } else {
            idf = 1e18 + epsilonRate;
        }
    }

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf)
    {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        if (pe.idf > 0) {
            idf = pe.idf;
        } else {
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
