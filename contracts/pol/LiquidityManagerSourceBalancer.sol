// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerSourceBase, WrongTokenAddresses} from "./LiquidityManagerSourceBase.sol";
import {LiquidityManagerCore, ZeroValue, ZeroAddress} from "./LiquidityManagerCore.sol";
import {IToken} from "../interfaces/IToken.sol";

interface IBalancerV2 {
    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /// @dev Exits a Pool, transferring tokens from the Pool's balance to `recipient`; the Vault enforces the
    ///      per-token `minAmountsOut`. `assets` must match the order returned by `getPoolTokens`.
    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request)
        external;

    /// @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when any of
    ///      the tokens' balances changed.
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    /// @dev Returns a Pool's contract address and specialization setting.
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);
}

/// @title Liquidity Manager Source Balancer - Balancer V2 POL withdrawal mixin
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Withdraws protocol-owned liquidity from a Balancer V2 (50/50 weighted) pool via `vault.exitPool`. The
///      exit passes zero per-token floors; source-pool manipulation is gated in `convertToV3` by the
///      removed-ratio cross-check against the V3 slot0 price (see `LiquidityManagerCore`).
abstract contract LiquidityManagerSourceBalancer is LiquidityManagerSourceBase {
    // Balancer vault address
    address public immutable balancerVault;

    /// @dev LiquidityManagerSourceBalancer constructor.
    /// @param _balancerVault Balancer vault address.
    constructor(address _balancerVault) {
        // Check for zero address
        if (_balancerVault == address(0)) {
            revert ZeroAddress();
        }

        balancerVault = _balancerVault;
    }

    /// @inheritdoc LiquidityManagerCore
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool)
        internal
        virtual
        override
        returns (uint256[] memory amounts)
    {
        // Get pool address
        (address poolToken,) = IBalancerV2(balancerVault).getPool(v2Pool);
        // Get this contract liquidity
        uint256 liquidity = IToken(poolToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        address[] memory tokensInPool = new address[](2);
        // Get V2 pool tokens and amounts
        (tokensInPool, amounts,) = IBalancerV2(balancerVault).getPoolTokens(v2Pool);

        // Check tokens
        if (tokensInPool[0] != tokens[0] || tokensInPool[1] != tokens[1]) {
            revert WrongTokenAddresses(tokens, tokensInPool);
        }

        // Check for zero balances
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Zero per-token floors. EXACT_BPT_IN_FOR_TOKENS_OUT is proportional, so the exit returns the pool's
        // current token ratio; a manipulated pool is caught by the removed-ratio vs V3-slot0 cross-check in
        // convertToV3, which runs before the tokens are committed to the V3 mint (all in the same transaction).
        uint256[] memory minAmountsOut = new uint256[](2);

        IBalancerV2.ExitPoolRequest memory request = IBalancerV2.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(IBalancerV2.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, liquidity),
            toInternalBalance: false
        });

        // Remove liquidity
        IBalancerV2(balancerVault).exitPool(v2Pool, address(this), payable(address(this)), request);
    }
}
