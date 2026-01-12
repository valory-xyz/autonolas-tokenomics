// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BuyBackBurner} from "./BuyBackBurner.sol";

// Balancer interface
interface IBalancer {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /// @dev Swaps tokens on Balancer.
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        payable
        returns (uint256);
}

// Slipstream router interface
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// Slipstream factory interface
interface ICLFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

// ERC20 interface
interface IERC20 {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

// Oracle V2 interface
interface IOracleBalancer {
    /// @dev Gets balancer vault address.
    function balancerVault() external view returns (address);

    /// @dev Gets balancer pool Id.
    function balancerPoolId() external view returns (bytes32);
}

/// @title BuyBackBurnerBalancer - BuyBackBurner implementation contract for interaction with Balancer for V2-like
///        full range pools and Slipstream for V3-like concentrated liquidity pools
contract BuyBackBurnerBalancer is BuyBackBurner {
    // Deprecated (proxy legacy): Balancer vault address
    address public balancerVault;
    // Deprecated (proxy legacy): Balancer pool Id
    bytes32 public balancerPoolId;

    /// @dev BuyBackBurnerBalancer constructor.
    /// @param _liquidityManager LiquidityManager address.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    /// @param _swapRouter Concentrated liquidity swap router.
    constructor(address _liquidityManager, address _bridge2Burner, address _treasury, address _swapRouter)
        BuyBackBurner(_liquidityManager, _bridge2Burner, _treasury, _swapRouter)
    {}

    /// @dev Performs swap for OLAS on Balancer DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param poolOracle Pool oracle address.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, address poolOracle) internal virtual override returns (uint256 olasAmount) {
        // Get balancer vault address
        address balVault = IOracleBalancer(poolOracle).balancerVault();

        // Get balancer pool Id
        bytes32 balPoolId = IOracleBalancer(poolOracle).balancerPoolId();

        // Approve secondToken for the Balancer Vault
        IERC20(secondToken).approve(balVault, secondTokenAmount);

        // Prepare Balancer data for the secondToken-OLAS pool
        IBalancer.SingleSwap memory singleSwap = IBalancer.SingleSwap(
            balPoolId, IBalancer.SwapKind.GIVEN_IN, secondToken, olas, secondTokenAmount, "0x"
        );
        IBalancer.FundManagement memory fundManagement =
            IBalancer.FundManagement(address(this), false, payable(address(this)), false);

        // Perform swap
        olasAmount = IBalancer(balVault).swap(singleSwap, fundManagement, 0, block.timestamp);
    }

    /// @dev Performs swap for OLAS on Slipstream CL DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param tickSpacing Tick spacing.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, int24 tickSpacing)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        IERC20(secondToken).approve(swapRouter, secondTokenAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: secondToken,
            tokenOut: olas,
            tickSpacing: tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: secondTokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        olasAmount = ISwapRouter(swapRouter).exactInputSingle(params);
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual override {
        address[] memory accounts;
        (accounts, balancerPoolId, maxSlippage) = abi.decode(payload, (address[], bytes32, uint256));

        olas = accounts[0];
        nativeToken = accounts[1];
        oracle = accounts[2];
        balancerVault = accounts[3];
    }

    /// @dev Gets Slipstream CL pool based on factory, token addresses and tick spacing.
    /// @param factory Factory address.
    /// @param tokens Token addresses.
    /// @param tickSpacing Tick spacing.
    /// @return Pool address.
    function getV3Pool(address factory, address[] memory tokens, int24 tickSpacing)
        public
        view
        virtual
        override
        returns (address)
    {
        return ICLFactory(factory).getPool(tokens[0], tokens[1], tickSpacing);
    }
}
