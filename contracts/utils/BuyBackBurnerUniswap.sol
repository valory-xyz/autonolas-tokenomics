// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @title BuyBackBurnerUniswap - BuyBackBurner implementation contract for interaction with UniswapV2 and UniswapV3
contract BuyBackBurnerUniswap is BuyBackBurner {
    // Uniswap V2 router address
    address public router;

    /// @dev BuyBackBurnerUniswap constructor.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    constructor(address _bridge2Burner, address _treasury) BuyBackBurner(_bridge2Burner, _treasury) {}

    /// @dev Performs swap for OLAS on DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, address)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        // Approve secondToken for the router
        IERC20(secondToken).approve(router, secondTokenAmount);

        address[] memory path = new address[](2);
        path[0] = secondToken;
        path[1] = olas;

        // Swap secondToken for OLAS
        uint256[] memory amounts =
            IUniswap(router).swapExactTokensForTokens(secondTokenAmount, 0, path, address(this), block.timestamp);

        // Record OLAS amount
        olasAmount = amounts[1];
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual override {
        address[] memory accounts;
        (accounts, maxSlippage) = abi.decode(payload, (address[], uint256));

        olas = accounts[0];
        nativeToken = accounts[1];
        oracle = accounts[2];
        router = accounts[3];
    }
}
