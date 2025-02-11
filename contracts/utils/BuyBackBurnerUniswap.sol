// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BuyBackBurner} from "./BuyBackBurner.sol";

// ERC20 interface
interface IERC20 {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

// UniswapV2 interface
interface IUniswap {
    /// @dev Swaps an exact amount of input tokens along the route determined by the path.
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to,
        uint256 deadline) external returns (uint256[] memory amounts);
}

/// @title BuyBackBurnerUniswap - BuyBackBurner implementation contract for interaction with UniswapV2
contract BuyBackBurnerUniswap is BuyBackBurner {
    // Router address
    address public router;

    /// @dev Performs swap for OLAS on DEX.
    /// @param nativeTokenAmount Native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(uint256 nativeTokenAmount) internal virtual override returns (uint256 olasAmount) {
        // Approve nativeToken for the router
        IERC20(nativeToken).approve(router, nativeTokenAmount);

        address[] memory path = new address[](2);
        path[0] = nativeToken;
        path[1] = olas;

        // Swap nativeToken for OLAS
        uint256[] memory amounts = IUniswap(router).swapExactTokensForTokens(
            nativeTokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Record OLAS amount
        olasAmount = amounts[1];
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal override virtual {
        address[] memory accounts;
        (accounts, maxSlippage) = abi.decode(payload, (address[], uint256));

        olas = accounts[0];
        nativeToken = accounts[1];
        oracle = accounts[2];
        router = accounts[3];
    }
}