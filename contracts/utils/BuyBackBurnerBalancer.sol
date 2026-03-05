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
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    constructor(address _bridge2Burner, address _treasury) BuyBackBurner(_bridge2Burner, _treasury) {}

    /// @dev Performs swap for OLAS on Balancer DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param poolOracle Pool oracle address.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, address poolOracle)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        // Get balancer vault address
        address balVault = IOracleBalancer(poolOracle).balancerVault();

        // Get balancer pool Id
        bytes32 balPoolId = IOracleBalancer(poolOracle).balancerPoolId();

        // Approve secondToken for the Balancer Vault
        IERC20(secondToken).approve(balVault, secondTokenAmount);

        // Prepare Balancer data for the secondToken-OLAS pool
        IBalancer.SingleSwap memory singleSwap =
            IBalancer.SingleSwap(balPoolId, IBalancer.SwapKind.GIVEN_IN, secondToken, olas, secondTokenAmount, "0x");
        IBalancer.FundManagement memory fundManagement =
            IBalancer.FundManagement(address(this), false, payable(address(this)), false);

        // Perform swap
        olasAmount = IBalancer(balVault).swap(singleSwap, fundManagement, 0, block.timestamp);
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
}
