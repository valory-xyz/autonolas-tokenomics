// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {mulDiv} from "@prb/math/src/Common.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "@prb/math/src/UD60x18.sol";


/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Provided zero address.
error ZeroAddress();


/// @title GenericBondSwap - Smart contract for generic bond calculation mechanisms in exchange for OLAS tokens.
/// @dev The bond calculation mechanism is based on the UniswapV2Pair contract.
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GenericBondCalculator {
    // OLAS contract address
    address public immutable olas;
    // Tokenomics contract address
    address public immutable tokenomics;

    /// @dev Generic Bond Calcolator constructor
    /// @param _olas OLAS contract address.
    /// @param _tokenomics Tokenomics contract address.
    constructor(address _olas, address _tokenomics) {
        // Check for at least one zero contract address
        if (_olas == address(0) || _tokenomics == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        tokenomics = _tokenomics;
    }

    /// @dev to init TWAP
    /// ToDo + spec
    function priceCumulativeLast(address token) external view returns (uint256 price0Cumulative, uint32 blockTimestampLast) {
        uint256 totalSupply = IUniswapV2Pair(token).totalSupply();
        if (totalSupply > 0) {
            address token0 = IUniswapV2Pair(token).token0();
            address token1 = IUniswapV2Pair(token).token1();
            if (token0 == olas || token1 == olas) {
                (,, blockTimestampLast) = IUniswapV2Pair(token).getReserves();
                price0Cumulative = IUniswapV2Pair(token).price0CumulativeLast();
                uint256 price1Cumulative = IUniswapV2Pair(token).price1CumulativeLast();
                if (token1 == olas) {
                    price0Cumulative = price1Cumulative;
                }
            }
        }
    }

    /// @dev currentCumulativePrices  per token at time t in deposit
    /// @dev ToDO: natspec
    function currentCumulativePrices(address token) external view returns (uint256 price0Cumulative) {
        uint256 totalSupply = IUniswapV2Pair(token).totalSupply();
        if (totalSupply > 0) {
            address token0 = IUniswapV2Pair(token).token0();
            address token1 = IUniswapV2Pair(token).token1();
            if (token0 == olas || token1 == olas) {
                price0Cumulative = IUniswapV2Pair(token).price0CumulativeLast();
                uint256 price1Cumulative = IUniswapV2Pair(token).price1CumulativeLast();
                // adjust priceXCumulative
                (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(token).getReserves();
                uint32 timeElapsed = uint32(block.timestamp - blockTimestampLast);
                if(timeElapsed > 0) {
                    // Adjusted ??? price0Cumulative, ToDo: re-thinking later, triple check pls!!
                    // re-check blockTimestampLast under flash loan attack
                    // price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
                    // price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
                    // optimized calculation later. 
                    UD60x18 numerator = convert(reserve1);
                    UD60x18 denominator = convert(reserve0);
                    price0Cumulative += UD60x18.unwrap(numerator.div(denominator)) * timeElapsed;
                    price1Cumulative += UD60x18.unwrap(denominator.div(numerator)) * timeElapsed;
                }
                if (token1 == olas) {
                    price0Cumulative = price1Cumulative;
                }
            }    
        }
    }

    /// @dev ToDO: natspec
    function calcPrice0Average(uint256 price0Cumulative, uint256 price0CumulativeLast, uint32 timeElapsed) external pure returns (uint256 price0Average){
        // ToDO: re-write by @prb/math/src/UD60x18 - done
        //price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        UD60x18 numerator = convert(price0Cumulative - price0CumulativeLast);
        UD60x18 denominator = convert(timeElapsed);
        price0Average = UD60x18.unwrap(numerator.div(denominator));
    }

    /// @dev ToDO: natspec
    function priceInBlock(address token) external view returns(uint256 price0) {
        address token0 = IUniswapV2Pair(token).token0();
        address token1 = IUniswapV2Pair(token).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(token).getReserves();
        if (token0 == olas || token1 == olas) {
            UD60x18 numerator = convert(reserve1);
            UD60x18 denominator = convert(reserve0);             
            price0 = UD60x18.unwrap(numerator.div(denominator));
            uint256 price1 = UD60x18.unwrap(denominator.div(numerator));
            if (token1 == olas) {
                price0 = price1;
            }
        }
    }
    
    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @notice Currently there is only one implementation of a bond calculation mechanism based on the UniswapV2 LP.
    /// @notice IDF has a 10^18 multiplier and priceLP has the same as well, so the result must be divided by 10^36.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    /// #if_succeeds {:msg "LP price limit"} priceLP * tokenAmount <= type(uint192).max;
    function calculatePayoutOLAS(uint256 tokenAmount, uint256 priceLP) external view
        returns (uint256 amountOLAS)
    {
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
        // Amount with the discount factor is IDF * priceLP * tokenAmount / 1e36
        // At this point of time IDF is bound by the max of uint64, and totalTokenValue is no bigger than the max of uint192
        amountOLAS = ITokenomics(tokenomics).getLastIDF() * totalTokenValue / 1e36;
    }

    /// @dev Gets current reserves of OLAS / totalSupply of LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP)
    {
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
                // Calculate the LP price based on reserves and totalSupply ratio multipliend by (2*9975/10000) multiplied by 1e18 
                // Inspired by: https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy#L262
                // first element in Tylor series
                // maybe just 2?!
                priceLP = (reserve1 * 1e18 * 2 * 9975) / (10000 * totalSupply);
            }
        }
    }
}    
