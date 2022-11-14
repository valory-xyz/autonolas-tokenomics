// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/ITokenomics.sol";

/// @title GenericBondSwap - Smart contract for generic bond calculation mechanisms in exchange for OLAS tokens.
/// @dev The bond calculation mechanism is based on the UniswapV2Pair contract.
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GenericBondCalculator {
    // OLAS contract address
    address immutable olas;
    // Tokenomics contract address
    address immutable tokenomics;

    /// @dev Generic Bond Calcolator constructor
    /// @param _olas OLAS contract address.
    /// @param _tokenomics Tokenomics contract address.
    constructor(address _olas, address _tokenomics) {
        olas = _olas;
        tokenomics = _tokenomics;
    }

    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @notice Currently there is only one implementation of a bond calculation mechanism based on the UniswapV2 LP.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(uint224 tokenAmount, uint256 priceLP) external view
        returns (uint96 amountOLAS)
    {
        // The result is divided by additional 1e18, since it was multiplied by in the current LP price calculation
        uint256 amountDF = (ITokenomics(tokenomics).getLastIDF() * priceLP * tokenAmount) / 1e36;
        amountOLAS = uint96(amountDF);
    }

    /// @dev Gets current reserves of OLAS / totalSupply of LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX/totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply > 0) {
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint112 reserve0;
            uint112 reserve1;
            // requires low gas
            (reserve0, reserve1, ) = pair.getReserves();
            // token0 != olas && token1 != olas, this should never happen
            if (token0 == olas || token1 == olas) {
                // Calculate the LP price based on reserves and totalSupply ratio
                priceLP = (token0 == olas) ? reserve0 / totalSupply : reserve1 / totalSupply;
                // Precision factor
                // Inspired by: https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy#L262
                priceLP *= 1e18;
            }
        }
    }

    /// @dev Check if the token is a UniswapV2Pair.
    /// @param token Address of an LP token.
    /// @return success True if successful.
    function checkLP(address token) external returns (bool success) {
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("kLast()")));
        assembly {
            success := call(
            5000,           // 5k gas
            token,          // destination address
            0,              // no ether
            add(data, 32),  // input buffer (starts after the first 32 bytes in the `data` array)
            mload(data),    // input length (loaded from the first 32 bytes in the `data` array)
            0,              // output buffer
            0               // output length
            )
        }
    }
}    
