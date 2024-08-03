// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {mulDiv} from "@prb/math/src/Common.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import "./interfaces/IUniswapV2Pair.sol";

interface ITokenomics {
    /// @dev Gets number of new units that were donated in the last epoch.
    /// @return Number of new units.
    function getLastEpochNumNewUnits() external view returns (uint256);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

// Struct for discount factor params
// The size of the struct is 96 + 64 + 64 = 224 (1 slot)
struct DiscountParams {
    // DAO set voting power limit for the bonding account
    // This value is bound by the veOLAS total voting power
    uint96 targetVotingPower;
    // DAO set number of new units per epoch limit
    // This number is bound by the total number of possible components and agents
    uint64 targetNewUnits;
    // DAO set weight factors
    // The sum of factors cannot exceed the value of 10_000 (100% with a 0.01% step)
    uint16[4] weightFactors;
}

// The size of the struct is 160 + 32 + 160 + 96 = 256 + 192 (2 slots)
struct Product {
    // priceLP (reserve0 / totalSupply or reserve1 / totalSupply) with 18 additional decimals
    // priceLP = 2 * r0/L * 10^18 = 2*r0*10^18/sqrt(r0*r1) ~= 61 + 96 - sqrt(96 * 112) ~= 53 bits (if LP is balanced)
    // or 2* r0/sqrt(r0) * 10^18 => 87 bits + 60 bits = 147 bits (if LP is unbalanced)
    uint160 priceLP;
    // Supply of remaining OLAS tokens
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 supply;
    // Token to accept as a payment
    address token;
    // Current OLAS payout
    // This value is bound by the initial total supply
    uint96 payout;
    // Max bond vesting time
    // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
    uint32 vesting;
}

/// @title BondCalculator - Smart contract for bond calculation payout in exchange for OLAS tokens based on dynamic IDF.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract BondCalculator {
    event OwnerUpdated(address indexed owner);
    event DiscountParamsUpdated(DiscountParams newDiscountParams);

    // Maximum sum of discount factor weights
    uint256 public constant MAX_SUM_WEIGHTS = 10_000;
    // OLAS contract address
    address public immutable olas;
    // Tokenomics contract address
    address public immutable tokenomics;
    // veOLAS contract address
    address public immutable ve;

    // Contract owner
    address public owner;
    // Discount params
    DiscountParams public discountParams;


    /// @dev Bond Calculator constructor.
    /// @param _olas OLAS contract address.
    /// @param _tokenomics Tokenomics contract address.
    /// @param _ve veOLAS contract address.
    /// @param _discountParams Discount factor parameters.
    constructor(address _olas, address _tokenomics, address _ve, DiscountParams memory _discountParams) {
        // Check for at least one zero contract address
        if (_olas == address(0) || _tokenomics == address(0) || _ve == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        tokenomics = _tokenomics;
        ve = _ve;
        owner = msg.sender;

        // Check for zero values
        if (_discountParams.targetNewUnits == 0 || _discountParams.targetVotingPower == 0) {
            revert ZeroValue();
        }
        // Check the sum of factors that cannot exceed the value of 10_000 (100% with a 0.01% step)
        uint256 sumWeights;
        for (uint256 i = 0; i < _discountParams.weightFactors.length; ++i) {
            sumWeights += _discountParams.weightFactors[i];
        }
        if (sumWeights > MAX_SUM_WEIGHTS) {
            revert Overflow(sumWeights, MAX_SUM_WEIGHTS);
        }
        discountParams = _discountParams;
    }

    /// @dev Changes contract owner address.
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

    /// @dev Changed inverse discount factor parameters.
    /// @param newDiscountParams Struct of new discount parameters.
    function changeDiscountParams(DiscountParams memory newDiscountParams) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero values
        if (newDiscountParams.targetNewUnits == 0 || newDiscountParams.targetVotingPower == 0) {
            revert ZeroValue();
        }
        // Check the sum of factors that cannot exceed the value of 10_000 (100% with a 0.01% step)
        uint256 sumWeights;
        for (uint256 i = 0; i < newDiscountParams.weightFactors.length; ++i) {
            sumWeights += newDiscountParams.weightFactors[i];
        }
        if (sumWeights > MAX_SUM_WEIGHTS) {
            revert Overflow(sumWeights, MAX_SUM_WEIGHTS);
        }

        discountParams = newDiscountParams;

        emit DiscountParamsUpdated(newDiscountParams);
    }

    /// @dev Calculated inverse discount factor based on bonding and account parameters.
    /// @param account Account address.
    /// @param bondVestingTime Bond vesting time.
    /// @param productMaxVestingTime Product max vesting time.
    /// @param productSupply Current product supply.
    /// @param productPayout Current product payout.
    /// @return idf Inverse discount factor in 18 decimals format.
    function calculateIDF(address account, uint256 bondVestingTime, uint256 productMaxVestingTime, uint256 productSupply,
        uint256 productPayout) public view returns (uint256 idf) {

        // Get the copy of the discount params
        DiscountParams memory localParams = discountParams;
        uint256 discountBooster;

        // First discount booster: booster = k1 * NumNewUnits(previous epoch) / TargetNewUnits(previous epoch)
        // Check the number of new units coming from tokenomics vs the target number of new units
        if (localParams.weightFactors[0] > 0) {
            uint256 numNewUnits = ITokenomics(tokenomics).getLastEpochNumNewUnits();

            // If the number of new units exceeds the target, bound by the target number
            if (numNewUnits >= localParams.targetNewUnits) {
                discountBooster = uint256(localParams.weightFactors[0]) * 1e18;
            } else {
                discountBooster = (uint256(localParams.weightFactors[0]) * numNewUnits * 1e18) /
                    uint256(localParams.targetNewUnits);
            }
        }

        // Second discount booster: booster += k2 * bondVestingTime / productMaxVestingTime
        // Add vesting time discount booster
        if (localParams.weightFactors[1] > 0) {
            if (bondVestingTime == productMaxVestingTime) {
                discountBooster += uint256(localParams.weightFactors[1]) * 1e18;
            } else {
                discountBooster += (uint256(localParams.weightFactors[1]) * bondVestingTime * 1e18) / productMaxVestingTime;
            }
        }

        // Third discount booster: booster += k3 * (1 - productPayout(at bonding time) / productSupply)
        // Add product supply discount booster
        if (localParams.weightFactors[2] > 0) {
            if (productPayout == 0) {
                discountBooster += uint256(localParams.weightFactors[2]) * 1e18;
            } else {
                // Get the total product supply
                productSupply = productSupply + productPayout;
                discountBooster += uint256(localParams.weightFactors[2]) * (1e18 - ((productPayout * 1e18) / productSupply));
            }
        }

        // Fourth discount booster: booster += k4 * getVotes(bonding account) / targetVotingPower
        // Check the veOLAS balance of a bonding account
        if (localParams.weightFactors[3] > 0) {
            uint256 vPower = IVotingEscrow(ve).getVotes(account);

            // If the number of new units exceeds the target, bound by the target number
            if (vPower >= localParams.targetVotingPower) {
                discountBooster += uint256(localParams.weightFactors[3]) * 1e18;
            } else {
                discountBooster += (uint256(localParams.weightFactors[3]) * vPower * 1e18) /
                    uint256(localParams.targetVotingPower);
            }
        }

        // Normalize discount booster by the max sum of weights
        discountBooster /= MAX_SUM_WEIGHTS;

        // IDF = 1 + normalized booster
        idf = 1e18 + discountBooster;
    }

    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism accounting for dynamic IDF.
    /// @param account Account address.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @param bondVestingTime Bond vesting time.
    /// @param productMaxVestingTime Product max vesting time.
    /// @param productSupply Current product supply.
    /// @param productPayout Current product payout.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(
        address account,
        uint256 tokenAmount,
        uint256 priceLP,
        uint256 bondVestingTime,
        uint256 productMaxVestingTime,
        uint256 productSupply,
        uint256 productPayout
    ) external view returns (uint256 amountOLAS) {
        // The result is divided by additional 1e18, since it was multiplied by in the current LP price calculation
        // The resulting amountDF can not overflow by the following calculations: idf = 64 bits;
        // priceLP = 2 * r0/L * 10^18 = 2*r0*10^18/sqrt(r0*r1) ~= 61 + 96 - sqrt(96 * 112) ~= 53 bits (if LP is balanced)
        // or 2* r0/sqrt(r0) * 10^18 => 87 bits + 60 bits = 147 bits (if LP is unbalanced);
        // tokenAmount is of the order of sqrt(r0*r1) ~ 104 bits (if balanced) or sqrt(96) ~ 10 bits (if max unbalanced);
        // overall: 64 + 53 + 104 = 221 < 256 - regular case if LP is balanced, and 64 + 147 + 10 = 221 < 256 if unbalanced
        // mulDiv will correctly fit the total amount up to the value of max uint256, i.e., max of priceLP and max of tokenAmount,
        // however their multiplication can not be bigger than the max of uint192
        uint256 totalTokenValue = mulDiv(priceLP, tokenAmount, 1);
        // Check for the cumulative LP tokens value limit
        if (totalTokenValue > type(uint192).max) {
            revert Overflow(totalTokenValue, type(uint192).max);
        }

        // Calculate the dynamic inverse discount factor
        uint256 idf = calculateIDF(account, bondVestingTime, productMaxVestingTime, productSupply, productPayout);

        // Amount with the discount factor is IDF * priceLP * tokenAmount / 1e36
        // At this point of time IDF is bound by the max of uint64, and totalTokenValue is no bigger than the max of uint192
        amountOLAS = (idf * totalTokenValue) / 1e36;
    }

    /// @dev Gets current reserves of OLAS / totalSupply of Uniswap V2-like LP tokens.
    /// @notice The price LP calculation is based on the UniswapV2Pair contract.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP) {
        IUniswapV2Pair pair = IUniswapV2Pair(token);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply > 0) {
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint256 reserve0;
            uint256 reserve1;
            // requires low gas
            (reserve0, reserve1, ) = pair.getReserves();
            // token0 != olas && token1 != olas, this should never happen
            if (token0 == olas || token1 == olas) {
                // If OLAS is in token0, assign its reserve to reserve1, otherwise the reserve1 is already correct
                if (token0 == olas) {
                    reserve1 = reserve0;
                }
                // Calculate the LP price based on reserves and totalSupply ratio multiplied by 1e18
                // Inspired by: https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy#L262
                priceLP = (reserve1 * 1e18) / totalSupply;
            }
        }
    }

    function getDiscountParams() external view returns (DiscountParams memory) {
        return discountParams;
    }
}    
