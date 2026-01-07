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

// UniswapV3 router interface
interface IRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// UniswapV3 factory interface
interface IFactory {
    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @dev Value underflow.
/// @param provided Underflow value.
/// @param min Minimum possible value.
error Underflow(int256 provided, int256 min);

/// @title BuyBackBurnerUniswap - BuyBackBurner implementation contract for interaction with UniswapV2 and UniswapV3
contract BuyBackBurnerUniswap is BuyBackBurner {
    // Uniswap V2 router address
    address public router;

    /// @dev BuyBackBurnerUniswap constructor.
    /// @param _liquidityManager LiquidityManager address.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    /// @param _swapRouter Concentrated liquidity swap router.
    constructor(address _liquidityManager, address _bridge2Burner, address _treasury, address _swapRouter)
        BuyBackBurner(_liquidityManager, _bridge2Burner, _treasury, _swapRouter)
    {}

    /// @dev Performs swap for OLAS on DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, address) internal virtual override returns (uint256 olasAmount) {
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

    /// @dev Performs swap for OLAS on V3 DEX.
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @param feeTier Fee tier.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address token, uint256 tokenAmount, int24 feeTier)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        IERC20(token).approve(swapRouter, tokenAmount);

        IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: olas,
            fee: uint24(feeTier),
            recipient: address(this),
            amountIn: tokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        olasAmount = IRouterV3(swapRouter).exactInputSingle(params);
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

    /// @dev Gets Uniswap V3 pool based on factory, token addresses and fee tier.
    /// @param factory Factory address.
    /// @param tokens Token addresses.
    /// @param feeTier Fee tier.
    /// @return Uniswap V3 pool address.
    function getV3Pool(address factory, address[] memory tokens, int24 feeTier)
        public
        view
        virtual
        override
        returns (address)
    {
        // Check for value underflow
        if (feeTier < 0) {
            revert Underflow(feeTier, 0);
        }

        return IFactory(factory).getPool(tokens[0], tokens[1], uint24(feeTier));
    }
}
