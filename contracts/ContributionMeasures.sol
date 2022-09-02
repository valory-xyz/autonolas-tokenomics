// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/IServiceTokenomics.sol";
import "./interfaces/IToken.sol";

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
    // Timestamp
    uint256 ts;
    // Block number
    uint256 blockNumber;
}

/// @title Contribution Measures - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ContributionMeasures is Ownable {
    using FixedPoint for *;

    // source: https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27
    // 2^(112 - log2(1e18))
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816;

    // UCFc / UCFa weights for the UCF contribution
    uint256 public ucfcWeight = 1;
    uint256 public ucfaWeight = 1;
    // Component / agent weights for new valuable code
    uint256 public componentWeight = 1;
    uint256 public agentWeight = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    uint256 public devsPerCapital = 1;
    // 10^(OLAS decimals) that represent a whole unit in OLAS token
    uint256 public constant decimalsUnit = 18;

    // Component Registry
    address public immutable componentRegistry;
    // Agent Registry
    address public immutable agentRegistry;
    // Service Registry
    address public immutable serviceRegistry;

    /// @dev Contribution Measures constructor.
    /// @param _componentRegistry Component registry address.
    /// @param _agentRegistry Agent registry address.
    /// @param _serviceRegistry Service registry address.
    constructor(address _componentRegistry, address _agentRegistry, address _serviceRegistry)
    {
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Changes contribution parameters.
    /// @param _ucfcWeight UCFc weighs for the UCF contribution.
    /// @param _ucfaWeight UCFa weight for the UCF contribution.
    /// @param _componentWeight Component weight for new valuable code.
    /// @param _agentWeight Agent weight for new valuable code.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    function changeContributionParameters(
        uint256 _ucfcWeight,
        uint256 _ucfaWeight,
        uint256 _componentWeight,
        uint256 _agentWeight,
        uint256 _devsPerCapital
    ) external onlyOwner {
        ucfcWeight = _ucfcWeight;
        ucfaWeight = _ucfaWeight;
        componentWeight = _componentWeight;
        agentWeight = _agentWeight;
        devsPerCapital = _devsPerCapital;
    }

    /// @dev Calculates contributions for components / agents of protocol-owned services.
    /// @param unitType Unit type as component or agent.
    /// @param unitRewards Component / agent allocated rewards.
    /// @param unitTopUps Component / agent allocated top-ups.
    /// @param protocolServiceIds Set of protocol-owned services in current epoch.
    /// @return ucfu Calculated UCFc / UCFa.
    function _calculateUnitContributionFactor(
        IServiceTokenomics.UnitType unitType,
        uint256 unitRewards,
        uint256 unitTopUps,
        uint256[] memory protocolServiceIds
    ) private returns (PointUnits memory ucfu)
    {
        uint256 numServices = protocolServiceIds.length;
        // Array of numbers of units per each service Id
        uint256[] memory numServiceUnits = new uint256[](numServices);
        // 2D array of all the sets of units per each service Id
        uint32[][] memory serviceUnitIds = new uint32[][](numServices);

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
            (numServiceUnits[i], serviceUnitIds[i]) = IServiceTokenomics(serviceRegistry).getUnitIdsOfService(unitType, serviceId);
            // Add to UCFa part for each agent Id
            uint256 amount = mapServiceAmounts[serviceId];
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
                } else {
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

    /// @dev Gets tokenomics contributions.
    /// @param protocolServiceIds Set of protocol-owned services in current epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @param componentRewards Component rewards.
    /// @param agentRewards Agent rewards.
    function getContributions(
        uint256[] memory protocolServiceIds,
        uint256 treasuryRewards,
        uint256 componentRewards,
        uint256 agentRewards
    ) external returns (PointUnits memory ucfc, PointUnits memory ucfa, uint256 fKD)
    {
        // Calculate total UCFc
        ucfc = _calculateUnitContributionFactor(IServiceTokenomics.UnitType.Component, componentRewards,
            topUpOwnerFraction, protocolServiceIds);
        ucfc.ucfWeight = ucfcWeight;
        ucfc.unitWeight = componentWeight;

        // Calculate total UCFa
        ucfa = _calculateUnitContributionFactor(IServiceTokenomics.UnitType.Agent, agentRewards,
            topUpOwnerFraction, protocolServiceIds);
        ucfa.ucfWeight = ucfaWeight;
        ucfa.unitWeight = agentWeight;

        // Calculate DF from epsilon rate and f(K,D)
        uint256 codeUnits = componentWeight * ucfc.numNewUnits + agentWeight * ucfa.numNewUnits;
        uint256 newOwners = ucfc.numNewOwners + ucfa.numNewOwners;
        // f(K(e), D(e)) = d * k * K(e) + d * D(e)
        // fKD = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
        // Convert amount of tokens with OLAS decimals (18 by default) to fixed point x.x
        FixedPoint.uq112x112 memory fp1 = FixedPoint.fraction(treasuryRewards, decimalsUnit);
        // For consistency multiplication with fp1
        FixedPoint.uq112x112 memory fp2 = FixedPoint.fraction(codeUnits * devsPerCapital, 1);
        // fp1 == codeUnits * devsPerCapital * treasuryRewards
        fp1 = fp1.muluq(fp2);
        // fp2 = codeUnits * newOwners
        fp2 = FixedPoint.fraction(codeUnits * newOwners, 1);
        // fp = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
        FixedPoint.uq112x112 memory fp = _add(fp1, fp2);
        // 1/100 rational number
        FixedPoint.uq112x112 memory fp3 = FixedPoint.fraction(1, 100);
        // fp = fp/100 - calculate the final value in fixed point
        fp = fp.muluq(fp3);
        // fKD in the state that is comparable with epsilon rate
        fKD = fp._x / MAGIC_DENOMINATOR;
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

    /// @dev Calculates UCF of by specified epoch point parameters.
    /// @param pe Epoch point.
    /// @return ucf UCF value.
    function getUCF(PointEcomonics memory pe) external view returns (uint256  ucf) {
        // Total rewards per epoch
        uint256 totalRewards = pe.treasuryRewards + pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;

        // Calculate UCFc
        uint256 denominator = totalRewards * pe.numServices * pe.ucfc.numUnits;
        FixedPoint.uq112x112 memory ucfc;
        // Number of components can be equal to zero for all the services, so the UCFc is just zero by default
        if (denominator > 0) {
            ucfc = FixedPoint.fraction(pe.ucfc.numProfitableUnits * pe.ucfc.ucfuSum, denominator);

            // Calculate UCFa
            denominator = totalRewards * pe.numServices * pe.ucfa.numUnits;
            // Number of agents must always be greater than zero, since at least one agent is used by a service
            if (denominator > 0) {
                FixedPoint.uq112x112 memory ucfa = FixedPoint.fraction(pe.ucfa.numProfitableUnits * pe.ucfa.ucfuSum, denominator);

                // Calculate UCF
                denominator = pe.ucfc.ucfWeight + pe.ucfa.ucfWeight;
                if (denominator > 0) {
                    FixedPoint.uq112x112 memory weightedUCFc = FixedPoint.fraction(pe.ucfc.ucfWeight, 1);
                    FixedPoint.uq112x112 memory weightedUCFa = FixedPoint.fraction(pe.ucfa.ucfWeight, 1);
                    weightedUCFc = ucfc.muluq(weightedUCFc);
                    weightedUCFa = ucfa.muluq(weightedUCFa);
                    FixedPoint.uq112x112 memory ucfFP = _add(weightedUCFc, weightedUCFa);
                    FixedPoint.uq112x112 memory fraction = FixedPoint.fraction(1, denominator);
                    ucfFP = ucfFP.muluq(fraction);
                    ucf = ucfFP._x / MAGIC_DENOMINATOR;
                }
            }
        }
    }
}    
