// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/IServiceTokenomics.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IVotingEscrow.sol";

// TODO: Optimize structs together with its variable sizes
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

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is IErrorsTokenomics, Ownable {
    using FixedPoint for *;

    event TreasuryUpdated(address treasury);
    event DepositoryUpdated(address depository);
    event DispenserUpdated(address dispenser);
    event VotingEscrowUpdated(address ve);
    event EpochLengthUpdated(uint256 epochLength);

    // OLAS token address
    address public immutable olas;
    // Treasury contract address
    address public treasury;
    // Depository contract address
    address public depository;
    // Dispenser contract address
    address public dispenser;
    // Voting Escrow address
    address public ve;

    // Epoch length in block numbers
    uint256 public epochLen;
    // Global epoch counter
    uint256 public epochCounter = 1;
    // ETH average block time
    uint256 public blockTimeETH = 14;
    // source: https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27 
    // 2^(112 - log2(1e18))
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816;
    // ~120k of OLAS tokens per epoch (the max cap is 20 million during 1st year, and the bonding fraction is 40%)
    uint256 public maxBond = 120_000 * 1e18;
    // TODO Decide which rate has to be put by default
    // Default epsilon rate that contributes to the interest rate: 50% or 0.5
    uint256 public epsilonRate = 5 * 1e17;

    // UCFc / UCFa weights for the UCF contribution
    uint256 public ucfcWeight = 1;
    uint256 public ucfaWeight = 1;
    // Component / agent weights for new valuable code
    uint256 public componentWeight = 1;
    uint256 public agentWeight = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    uint256 public devsPerCapital = 1;
    // 10^(OLAS decimals) that represent a whole unit in OLAS token
    uint256 public immutable decimalsUnit;

    // Total service revenue per epoch: sum(r(s))
    uint256 public epochServiceRevenueETH;
    // Donation balance
    uint256 public donationBalanceETH;

    // Staking parameters with multiplying by 100
    // treasuryFraction (implicit, zero by default) + componentFraction + agentFraction + stakerFraction = 100%
    uint256 public stakerFraction = 50;
    uint256 public componentFraction = 33;
    uint256 public agentFraction = 17;
    // Top-up of OLAS and bonding parameters with multiplying by 100
    uint256 public topUpOwnerFraction = 40;
    uint256 public topUpStakerFraction = 20;

    // Bond per epoch
    uint256 public bondPerEpoch;
    // MaxBond(e) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    uint256 public effectiveBond = maxBond;
    // Manual or auto control of max bond
    bool public bondAutoControl;

    // Component Registry
    address public immutable componentRegistry;
    // Agent Registry
    address public immutable agentRegistry;
    // Service Registry
    address payable public immutable serviceRegistry;

    // Inflation caps for the first ten years
    uint256[] public inflationCaps;
    // Set of protocol-owned services in current epoch
    uint256[] public protocolServiceIds;
    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;
    // Map of component Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapComponents;
    // Map of agent Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapAgents;
    // Mapping of owner of component / agent addresses that create them
    mapping(address => bool) public mapOwners;
    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) public mapServiceAmounts;
    // Mapping of owner of component / agent address => reward amount (in ETH)
    mapping(address => uint256) public mapOwnerRewards;
    // Mapping of owner of component / agent address => top-up amount (in OLAS)
    mapping(address => uint256) public mapOwnerTopUps;
    // Map of whitelisted service owners for protocol-owned services
    mapping(address => bool) private _mapServiceOwners;

    // TODO sync address constants with other contracts
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Tokenomics constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _ve Voting Escrow address.
    /// @param _epochLen Epoch length.
    /// @param _componentRegistry Component registry address.
    /// @param _agentRegistry Agent registry address.
    /// @param _serviceRegistry Service registry address.
    constructor(address _olas, address _treasury, address _depository, address _dispenser, address _ve, uint256 _epochLen,
        address _componentRegistry, address _agentRegistry, address payable _serviceRegistry)
    {
        olas = _olas;
        treasury = _treasury;
        depository = _depository;
        dispenser = _dispenser;
        ve = _ve;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;
        decimalsUnit = 10 ** IOLAS(_olas).decimals();

        inflationCaps = new uint[](10);
        inflationCaps[0] = 520_000_000e18;
        inflationCaps[1] = 590_000_000e18;
        inflationCaps[2] = 660_000_000e18;
        inflationCaps[3] = 730_000_000e18;
        inflationCaps[4] = 790_000_000e18;
        inflationCaps[5] = 840_000_000e18;
        inflationCaps[6] = 890_000_000e18;
        inflationCaps[7] = 930_000_000e18;
        inflationCaps[8] = 970_000_000e18;
        inflationCaps[9] = 1_000_000_000e18;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyTreasury() {
        if (treasury != msg.sender) {
            revert ManagerOnly(msg.sender, treasury);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyDispenser() {
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }
        _;
    }

    /// @dev Changes various managing contract addresses.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _ve Voting Escrow address.
    function changeManagers(address _treasury, address _depository, address _dispenser, address _ve) external onlyOwner {
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
        if (_depository != address(0)) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        if (_dispenser != address(0)) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
        if (_ve != address(0)) {
            ve = _ve;
            emit VotingEscrowUpdated(_ve);
        }
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
        uint256 _ucfcWeight,
        uint256 _ucfaWeight,
        uint256 _componentWeight,
        uint256 _agentWeight,
        uint256 _devsPerCapital,
        uint256 _epsilonRate,
        uint256 _maxBond,
        uint256 _epochLen,
        uint256 _blockTimeETH,
        bool _bondAutoControl
    ) external onlyOwner {
        ucfcWeight = _ucfcWeight;
        ucfaWeight = _ucfaWeight;
        componentWeight = _componentWeight;
        agentWeight = _agentWeight;
        devsPerCapital = _devsPerCapital;
        epsilonRate = _epsilonRate;
        // take into account the change during the epoch
        _adjustMaxBond(_maxBond);
        epochLen = _epochLen;
        blockTimeETH = _blockTimeETH;
        bondAutoControl = _bondAutoControl;
    }

    /// @dev Sets staking parameters in fractions of distributed rewards.
    /// @param _stakerFraction Fraction for stakers.
    /// @param _componentFraction Fraction for component owners.
    /// @param _agentFraction Fraction for agent owners.
    /// @param _topUpOwnerFraction Fraction for OLAS top-up for component / agent owners.
    /// @param _topUpStakerFraction Fraction for OLAS top-up for stakers.
    function changeRewardFraction(
        uint256 _stakerFraction,
        uint256 _componentFraction,
        uint256 _agentFraction,
        uint256 _topUpOwnerFraction,
        uint256 _topUpStakerFraction
    ) external onlyOwner {
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
    }

    /// @dev (De-)whitelists service owners for protocol-owned services.
    /// @param accounts Set of account addresses.
    /// @param permissions Set of corresponding permissions for each account address.
    function changeServiceOwnerWhiteList(address[] memory accounts, bool[] memory permissions) external onlyOwner {
        uint256 numAccounts = accounts.length;
        // Check the array size
        if (permissions.length != numAccounts) {
            revert WrongArrayLength(numAccounts, permissions.length);
        }
        for (uint256 i = 0; i < numAccounts; ++i) {
            _mapServiceOwners[accounts[i]] = permissions[i];
        }
    }

    /// @dev Checks for the OLAS minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLAS tokens to mint.
    /// @return True if the mint is allowed.
    function isAllowedMint(uint256 amount) public returns (bool) {
        uint256 remainder = _getInflationRemainderForYear();
        // For the first 10 years we check the inflation cap that is pre-defined
        if (amount > remainder) {
            return false;
        }
        return true;
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
    /// @return True if effective bond threshold is not reached.
    function allowedNewBond(uint256 amount) external onlyDepository returns (bool)  {
        if(effectiveBond >= amount && isAllowedMint(amount)) {
            effectiveBond -= amount;
            return true;
        }
        return false;
    }

    /// @dev Increases the bond per epoch with the OLAS payout for a Depository program
    /// @param payout Payout amount for the LP pair.
    function usedBond(uint256 payout) external onlyDepository {
        bondPerEpoch += payout;
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external onlyTreasury
        returns (uint256 revenueETH, uint256 donationETH)
    {
        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existence
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            // Check for the whitelisted service owner
            address owner = IToken(serviceRegistry).ownerOf(serviceIds[i]);
            // If not, accept it as donation
            if (!_mapServiceOwners[owner]) {
                donationETH += amounts[i];
            } else {
                // Add a new service Id to the set of Ids if one was not currently in it
                if (mapServiceAmounts[serviceIds[i]] == 0) {
                    protocolServiceIds.push(serviceIds[i]);
                }
                mapServiceAmounts[serviceIds[i]] += amounts[i];
                revenueETH += amounts[i];
            }
        }
        // Increase the total service revenue per epoch and donation balance
        epochServiceRevenueETH += revenueETH;
        donationBalanceETH += donationETH;
    }

    /// @dev Calculates tokenomics for components / agents of protocol-owned services.
    /// @param unitType Unit type as component or agent.
    /// @param unitRewards Component / agent allocated rewards.
    /// @param unitTopUps Component / agent allocated top-ups.
    /// @return ucfu Calculated UCFc / UCFa.
    function _calculateUnitTokenomics(IServiceTokenomics.UnitType unitType, uint256 unitRewards, uint256 unitTopUps) private
        returns (PointUnits memory ucfu)
    {
        uint256 numServices = protocolServiceIds.length;

        // TODO Possible optimization is to store a set of componets / agents and the map of those used in protocol-owned services
        address registry = unitType == IServiceTokenomics.UnitType.Component ? componentRegistry: agentRegistry;
        ucfu.numUnits = IToken(registry).totalSupply();
        // Set of agent revenues UCFu-s. Agent / component Ids start from "1", so the index can be equal to the set size
        uint256[] memory ucfuRevs = new uint256[](ucfu.numUnits + 1);
        // Set of agent revenues UCFu-s divided by the cardinality of agent Ids in each service
        uint256[] memory ucfus = new uint256[](numServices);
        // Overall profits of UCFu-s
        uint256 sumProfits = 0;

        // Loop over profitable service Ids to calculate initial UCFu-s
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = protocolServiceIds[i];
            uint256 numServiceUnits;
            uint32[] memory unitIds;
            (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getUnitIdsOfService(unitType, serviceId);
            // Add to UCFa part for each agent Id
            uint256 amount = mapServiceAmounts[serviceId];
            for (uint256 j = 0; j < numServiceUnits; ++j) {
                // Sum the amounts for the corresponding components / agents
                ucfuRevs[unitIds[j]] += amount;
                sumProfits += amount;
            }
        }

        // Calculate all complete UCFu-s divided by the cardinality of agent Ids in each service
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = protocolServiceIds[i];
            uint256 numServiceUnits;
            uint32[] memory unitIds;
            (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getUnitIdsOfService(unitType, serviceId);
            for (uint256 j = 0; j < numServiceUnits; ++j) {
                // Sum(UCFa[i]) / |As(epoch)|
                ucfus[i] += ucfuRevs[unitIds[j]];
            }
            ucfus[i] /= numServiceUnits;
        }

        // Calculate component / agent related values
        for (uint256 i = 0; i < ucfu.numUnits; ++i) {
            // Get the agent Id from the index list
            // For our architecture it's the identity function (see tokenByIndex() in autonolas-registries)
            uint256 unitId = i + 1;
            if (ucfuRevs[unitId] > 0) {
                // Add address of a profitable component owner
                address owner = IToken(registry).ownerOf(unitId);
                // Increase a profitable agent number
                ++ucfu.numProfitableUnits;
                // Calculate agent rewards in ETH
                mapOwnerRewards[owner] += (unitRewards * ucfuRevs[unitId]) / sumProfits;
                // Calculate OLAS top-ups
                uint256 amountOLAS = (unitTopUps * ucfuRevs[unitId]) / sumProfits;
                if (unitType == IServiceTokenomics.UnitType.Component) {
                    amountOLAS = (amountOLAS * componentWeight) / (componentWeight + agentWeight);
                } else {
                    amountOLAS = (amountOLAS * agentWeight)  / (componentWeight + agentWeight);
                }
                mapOwnerTopUps[owner] += amountOLAS;

                // Check if the component / agent is used for the first time
                if (unitType == IServiceTokenomics.UnitType.Component && !mapComponents[unitId]) {
                    ucfu.numNewUnits++;
                    mapComponents[unitId] = true;
                } else if (unitType == IServiceTokenomics.UnitType.Agent && !mapAgents[unitId]){
                    ucfu.numNewUnits++;
                    mapAgents[unitId] = true;
                }
                // Check if the owner has introduced component / agent for the first time 
                if (!mapOwners[owner]) {
                    mapOwners[owner] = true;
                    ucfu.numNewOwners++;
                }
            }
        }

        // Calculate total UCFu
        for (uint256 i = 0; i < numServices; ++i) {
            ucfu.ucfuSum += ucfus[i];
        }
        // Record unit rewards
        ucfu.unitRewards = unitRewards;
    }

    /// @dev Clears necessary data structures for the next epoch.
    function _clearEpochData() internal {
        uint256 numServices = protocolServiceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            delete mapServiceAmounts[protocolServiceIds[i]];
        }
        delete protocolServiceIds;
        epochServiceRevenueETH = 0;
    }

    /// @dev Record global data to the checkpoint
    function checkpoint() external onlyTreasury {
        PointEcomonics memory lastPoint = mapEpochEconomics[epochCounter - 1];
        // New point can be calculated only if we passed number of blocks equal to the epoch length
        if (block.number > lastPoint.blockNumber) {
            uint256 diffNumBlocks = block.number - lastPoint.blockNumber;
            if (diffNumBlocks >= epochLen) {
                _checkpoint();
            }
        }
    }

    /// @dev Adjusts max bond every epoch if max bond is contract-controlled.
    function _adjustMaxBond(uint256 _maxBond) internal {
        // take into account the change during the epoch
        if(_maxBond > maxBond) {
            uint256 delta = _maxBond - maxBond;
            effectiveBond += delta;
        }
        if(_maxBond < maxBond) {
            uint256 delta = maxBond - _maxBond;
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

    /// @dev Record global data to new checkpoint
    function _checkpoint() internal {
        // Get total amount of OLAS as profits for rewards, and all the rewards categories
        // 0: total rewards, 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // 5: topUpOwnerFraction, 6: topUpStakerFraction, 7: bondFraction
        uint256[] memory rewards = new uint256[](8);
        rewards[0] = epochServiceRevenueETH;
        rewards[2] = rewards[0] * stakerFraction / 100;
        rewards[3] = rewards[0] * componentFraction / 100;
        rewards[4] = rewards[0] * agentFraction / 100;
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];

        // Top-ups and bonding possibility in OLAS are recalculated based on the inflation schedule per epoch
        uint256 totalTopUps = (IOLAS(olas).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
        rewards[5] = totalTopUps * topUpOwnerFraction / 100;
        rewards[6] = totalTopUps * topUpStakerFraction / 100;
        rewards[7] = totalTopUps - rewards[5] - rewards[6];

        // Effective bond accumulates leftovers from previous epochs (with last max bond value set)
        if (maxBond > bondPerEpoch) {
            effectiveBond += maxBond - bondPerEpoch;
        }
        // Bond per epoch starts from zero every epoch
        bondPerEpoch = 0;
        // Adjust max bond and effective bond if contract-controlled max bond is enabled
        if (bondAutoControl) {
            _adjustMaxBond(rewards[7]);
        }

        // df = 1/(1 + iterest_rate) by documantation, reverse_df = 1/df >= 1.0.
        uint256 df;
        // Calculate UCFc, UCFa, rewards allocated from them and DF
        PointUnits memory ucfc;
        PointUnits memory ucfa;
        if (rewards[0] > 0) {
            // Calculate total UCFc
            ucfc = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Component, rewards[3], rewards[5]);
            ucfc.ucfWeight = ucfcWeight;
            ucfc.unitWeight = componentWeight;

            // Calculate total UCFa
            ucfa = _calculateUnitTokenomics(IServiceTokenomics.UnitType.Agent, rewards[4], rewards[5]);
            ucfa.ucfWeight = ucfaWeight;
            ucfa.unitWeight = agentWeight;

            // Calculate DF from epsilon rate and f(K,D)
            uint256 codeUnits = componentWeight * ucfc.numNewUnits + agentWeight * ucfa.numNewUnits;
            uint256 newOwners = ucfc.numNewOwners + ucfa.numNewOwners;
            //  f(K(e), D(e)) = d * k * K(e) + d * D(e)
            // fKD = codeUnits * devsPerCapital * rewards[1] + codeUnits * newOwners;
            //  Convert amount of tokens with OLAS decimals (18 by default) to fixed point x.x
            FixedPoint.uq112x112 memory fp1 = FixedPoint.fraction(rewards[1], decimalsUnit);
            // For consistency multiplication with fp1
            FixedPoint.uq112x112 memory fp2 = FixedPoint.fraction(codeUnits * devsPerCapital, 1);
            // fp1 == codeUnits * devsPerCapital * rewards[1]
            fp1 = fp1.muluq(fp2);
            // fp2 = codeUnits * newOwners
            fp2 = FixedPoint.fraction(codeUnits * newOwners, 1);
            // fp = codeUnits * devsPerCapital * rewards[1] + codeUnits * newOwners;
            FixedPoint.uq112x112 memory fp = _add(fp1, fp2);
            // 1/100 rational number
            FixedPoint.uq112x112 memory fp3 = FixedPoint.fraction(1, 100);
            // fp = fp/100 - calculate the final value in fixed point
            fp = fp.muluq(fp3);
            // fKD in the state that is comparable with epsilon rate
            uint256 fKD = fp._x / MAGIC_DENOMINATOR;

            // Compare with epsilon rate and choose the smallest one
            if (fKD > epsilonRate) {
                fKD = epsilonRate;
            }
            // 1 + fKD in the system where 1e18 is equal to a whole unit (18 decimals)
            df = 1e18 + fKD;
        }

        uint256 numServices = protocolServiceIds.length;
        PointEcomonics memory newPoint = PointEcomonics(ucfc, ucfa, df, numServices, rewards[1], rewards[2],
            donationBalanceETH, rewards[5], rewards[6], devsPerCapital, block.timestamp, block.number);
        mapEpochEconomics[epochCounter] = newPoint;
        epochCounter++;

        _clearEpochData();
    }

    // TODO: Specify the doc mentioned below
    /// @dev Calculates the amount of OLAS tokens based on LP (see the doc for explanation of price computation).
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutFromLP(address token, uint256 tokenAmount) external view returns (uint256 amountOLAS)
    {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        if(pe.df > 0) {
            amountOLAS = _calculatePayoutFromLP(token, tokenAmount, pe.df);
        } else {
            // if df is undefined
            amountOLAS = _calculatePayoutFromLP(token, tokenAmount, 1e18 + epsilonRate);
        }
    }

    /// @dev Calculates the amount of OLAS tokens based on LP (see the doc for explanation of price computation).
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param df Discount
    /// @return resAmount Resulting amount of OLAS tokens.
    function _calculatePayoutFromLP(address token, uint256 amount, uint256 df) internal view
        returns (uint256 resAmount)
    {
        // Calculation of removeLiquidity
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 balance0 = IToken(token0).balanceOf(address(pair));
        uint256 balance1 = IToken(token1).balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();

        // Using balances ensures pro-rate distribution
        uint256 amount0 = (amount * balance0) / totalSupply;
        uint256 amount1 = (amount * balance1) / totalSupply;

        require(balance0 > amount0, "UniswapV2: INSUFFICIENT_LIQUIDITY token0");
        require(balance1 > amount1, "UniswapV2: INSUFFICIENT_LIQUIDITY token1");

        // Get the initial OLAS token amounts
        uint256 amountOLAS = (token0 == olas) ? amount0 : amount1;
        uint256 amountPairForOLAS = (token0 == olas) ? amount1 : amount0;

        // Calculate swap tokens from the LP back to the OLAS token
        balance0 -= amount0;
        balance1 -= amount1;
        uint256 reserveIn = (token0 == olas) ? balance1 : balance0;
        uint256 reserveOut = (token0 == olas) ? balance0 : balance1;
        
        amountOLAS = amountOLAS + getAmountOut(amountPairForOLAS, reserveIn, reserveOut);

        // Get the resulting amount in OLAS tokens
        resAmount = (amountOLAS * df) / 1e18; // df with decimals 18

        // The discounted amount cannot be smaller than the actual one
        if (resAmount < amountOLAS) {
            revert AmountLowerThan(resAmount, amountOLAS);
        }
    }

    // UniswapV2 https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // No license in file
    // forked for Solidity 8.x
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset

    /// @dev Gets the additional OLAS amount from the LP pair token by swapping.
    /// @param amountIn Initial OLAS token amount.
    /// @param reserveIn Token amount that is not OLAS.
    /// @param reserveOut Token amount in OLAS wit fees.
    /// @return amountOut Resulting OLAS amount.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee / reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
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
                    reward += balance * pe.stakerRewards / supply;
                    topUp += balance * pe.stakerTopUps / supply;
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

    /// @dev Gets rewards data of the last epoch.
    /// @return treasuryRewards Treasury rewards.
    /// @return accountRewards Cumulative staker, component and agent rewards.
    /// @return accountTopUps Cumulative staker, component and agent top-ups.
    function getRewardsData() external returns (uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps) {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        treasuryRewards = pe.treasuryRewards;
        accountRewards = pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;
        accountTopUps = pe.ownerTopUps + pe.stakerTopUps;
    }

    /// @dev Gets discount factor.
    /// @param epoch Epoch number.
    /// @return df Discount factor.
    function getDF(uint256 epoch) external view returns (uint256 df)
    {
        PointEcomonics memory pe = mapEpochEconomics[epoch];
        if (pe.df > 0) {
            df = pe.df;
        } else {
            df = 1e18 + epsilonRate;
        }
    }

    /// @dev Sums two fixed points.
    /// @param x Point x.
    /// @param y Point y.
    /// @return r Result of x + y.
    function _add(FixedPoint.uq112x112 memory x, FixedPoint.uq112x112 memory y) private pure
        returns (FixedPoint.uq112x112 memory r)
    {
        uint224 z = x._x + y._x;
        if (x._x > 0 && y._x > 0) assert (z > x._x && z > y._x);
        r = FixedPoint.uq112x112(uint224(z));
    }

    /// @dev Calculated UCF of a specified epoch.
    /// @param epoch Epoch number.
    /// @return ucf UCF value.
    function getUCF(uint256 epoch) external view returns (FixedPoint.uq112x112 memory ucf) {
        PointEcomonics memory pe = mapEpochEconomics[epoch];

        // Total rewards per epoch
        uint256 totalRewards = pe.treasuryRewards + pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;

        // Calculate UCFc
        uint256 denominator = totalRewards * pe.numServices * pe.ucfc.numUnits;
        FixedPoint.uq112x112 memory ucfc;
        // Number of components can be equal to zero for all the services, so the UCFc is just zero by default
        if (denominator > 0) {
            ucfc = FixedPoint.fraction(pe.ucfc.numProfitableUnits * pe.ucfc.ucfuSum, denominator);
        }

        // Calculate UCFa
        denominator = totalRewards * pe.numServices * pe.ucfa.numUnits;
        // Number of agents must always be greater than zero, since at least one agent is used by a service
        if (denominator == 0) {
            revert ZeroValue();
        }
        FixedPoint.uq112x112 memory ucfa = FixedPoint.fraction(pe.ucfa.numProfitableUnits * pe.ucfa.ucfuSum, denominator);

        // Calculate UCF
        denominator = pe.ucfc.ucfWeight + pe.ucfa.ucfWeight;
        if (denominator == 0) {
            revert ZeroValue();
        }
        FixedPoint.uq112x112 memory weightedUCFc = FixedPoint.fraction(pe.ucfc.ucfWeight, 1);
        FixedPoint.uq112x112 memory weightedUCFa = FixedPoint.fraction(pe.ucfa.ucfWeight, 1);
        weightedUCFc = ucfc.muluq(weightedUCFc);
        weightedUCFa = ucfa.muluq(weightedUCFa);
        ucf = _add(weightedUCFc, weightedUCFa);
        FixedPoint.uq112x112 memory fraction = FixedPoint.fraction(1, denominator);
        ucf = ucf.muluq(fraction);
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
    function accountOwnerRewards(address account) external onlyDispenser returns (uint256 reward, uint256 topUp) {
        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
        mapOwnerRewards[account] = 0;
        mapOwnerTopUps[account] = 0;
    }
}    
