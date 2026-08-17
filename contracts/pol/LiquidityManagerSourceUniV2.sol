// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore, ZeroValue, ZeroAddress, WrongTokenAddresses} from "./LiquidityManagerCore.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";

interface IUniswapV2Router02 {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

/// @title Liquidity Manager Source UniV2 - Uniswap V2 POL withdrawal mixin
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Withdraws protocol-owned liquidity from a Uniswap V2 pair via `router.removeLiquidity`. The withdrawal
///      passes zero per-token floors; source-pool manipulation is gated in `convertToV3` by the removed-ratio
///      cross-check against the V3 slot0 price (see `LiquidityManagerCore`).
abstract contract LiquidityManagerSourceUniV2 is LiquidityManagerCore {
    // Uniswap V2 Router address
    address public immutable routerV2;

    /// @dev LiquidityManagerSourceUniV2 constructor.
    /// @param _routerV2 Uniswap V2 Router address.
    constructor(address _routerV2) {
        // Check for zero address
        if (_routerV2 == address(0)) {
            revert ZeroAddress();
        }

        routerV2 = _routerV2;
    }

    /// @inheritdoc LiquidityManagerCore
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pair)
        internal
        virtual
        override
        returns (uint256[] memory amounts)
    {
        // Convert into pool address
        address lpToken = address(uint160(uint256(v2Pair)));

        // Get this contract liquidity
        uint256 liquidity = IToken(lpToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get V2 pair tokens - assume they are in lexicographical order as per Uniswap convention
        address[] memory tokensInPair = new address[](2);
        tokensInPair[0] = IUniswapV2Pair(lpToken).token0();
        tokensInPair[1] = IUniswapV2Pair(lpToken).token1();

        // Check tokens
        if (tokensInPair[0] != tokens[0] || tokensInPair[1] != tokens[1]) {
            revert WrongTokenAddresses(tokens, tokensInPair);
        }

        // Approve V2 liquidity
        IToken(lpToken).approve(routerV2, liquidity);

        // Remove liquidity with zero per-token floors. removeLiquidity is proportional, so this returns the pair's
        // current token ratio; a manipulated pair is caught by the removed-ratio vs V3-slot0 cross-check in
        // convertToV3, which runs before the tokens are committed to the V3 mint (all in the same transaction).
        amounts = new uint256[](2);
        (amounts[0], amounts[1]) = IUniswapV2Router02(routerV2)
            .removeLiquidity(tokens[0], tokens[1], liquidity, 0, 0, address(this), block.timestamp);
    }
}
