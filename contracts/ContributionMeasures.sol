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

    // TODO: elaborate on this side these values must be - tokenomics or contribution measures.
    // TODO: Also, should they be written into the PointUnits struct? getUCF() requires them, check the formula
    // Component / agent weights for new valuable code
    uint256 public componentWeight = 1;
    uint256 public agentWeight = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    uint256 public devsPerCapital = 1;
    // 10^(OLAS decimals) that represent a whole unit in OLAS token
    uint256 public constant decimalsUnit = 18;

    /// @dev Changes contribution parameters.
    /// @param _componentWeight Component weight for new valuable code.
    /// @param _agentWeight Agent weight for new valuable code.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    function changeContributionParameters(
        uint256 _componentWeight,
        uint256 _agentWeight,
        uint256 _devsPerCapital
    ) external onlyOwner {
        componentWeight = _componentWeight;
        agentWeight = _agentWeight;
        devsPerCapital = _devsPerCapital;
    }

    /// @dev Calculates valuable tokenomics contributions based on component and agent contribution factors.
    /// @param ucfc Unit Contribution Factor (components).
    /// @param ucfa Unit Contribution Factor (agents).
    /// @param treasuryRewards Treasury rewards.
    function calculateValuableContributions(
        PointUnits memory ucfc,
        PointUnits memory ucfa,
        uint256 treasuryRewards
    ) external view returns (uint256 fKD)
    {
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
        uint224 sum = fp1._x + fp2._x;
        FixedPoint.uq112x112 memory fp = FixedPoint.uq112x112(uint224(sum));
        // 1/100 rational number
        FixedPoint.uq112x112 memory fp3 = FixedPoint.fraction(1, 100);
        // fp = fp/100 - calculate the final value in fixed point
        fp = fp.muluq(fp3);
        // fKD in the state that is comparable with epsilon rate
        fKD = fp._x / MAGIC_DENOMINATOR;
    }

    /// @dev Calculates UCF of by specified epoch point parameters.
    /// @param pe Epoch point.
    /// @return ucf UCF value.
    function getUCF(PointEcomonics memory pe) external pure returns (uint256 ucf) {
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
                    uint224 sum = weightedUCFc._x + weightedUCFa._x;
                    FixedPoint.uq112x112 memory ucfFP = FixedPoint.uq112x112(uint224(sum));
                    FixedPoint.uq112x112 memory fraction = FixedPoint.fraction(1, denominator);
                    ucfFP = ucfFP.muluq(fraction);
                    ucf = ucfFP._x / MAGIC_DENOMINATOR;
                }
            }
        }
    }
}    
