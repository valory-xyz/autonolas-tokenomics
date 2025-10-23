// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BuyBackBurner} from "./BuyBackBurner.sol";

// Balancer interface
interface IBalancer {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

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
        external payable returns (uint256);
}

// ERC20 interface
interface IERC20 {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title BuyBackBurnerBalancer - BuyBackBurner implementation contract for interaction with Balancer
contract BuyBackBurnerBalancer is BuyBackBurner {
    // Balancer vault address
    address public balancerVault;
    // Balancer pool Id
    bytes32 public balancerPoolId;


    /// @dev BuyBackBurnerBalancer constructor.
    /// @param _liquidityManager LiquidityManager address.
    /// @param _bridge2Burner Bridge2Burner address.
    constructor(address _liquidityManager, address _bridge2Burner) BuyBackBurner(_liquidityManager, _bridge2Burner) {}

    /// @dev Performs swap for OLAS on DEX.
    /// @param nativeTokenAmount Native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(uint256 nativeTokenAmount) internal virtual override returns (uint256 olasAmount) {
        // Approve nativeToken for the Balancer Vault
        IERC20(nativeToken).approve(balancerVault, nativeTokenAmount);

        // Prepare Balancer data for the nativeToken-OLAS pool
        IBalancer.SingleSwap memory singleSwap = IBalancer.SingleSwap(balancerPoolId, IBalancer.SwapKind.GIVEN_IN,
            nativeToken, olas, nativeTokenAmount, "0x");
        IBalancer.FundManagement memory fundManagement = IBalancer.FundManagement(address(this), false,
            payable(address(this)), false);

        // Perform swap
        olasAmount = IBalancer(balancerVault).swap(singleSwap, fundManagement, 0, block.timestamp);
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal override virtual {
        address[] memory accounts;
        (accounts, balancerPoolId, maxSlippage) = abi.decode(payload, (address[], bytes32, uint256));

        olas = accounts[0];
        nativeToken = accounts[1];
        oracle = accounts[2];
        balancerVault = accounts[3];
    }
}