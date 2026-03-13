// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Bridge2Burner} from "./Bridge2Burner.sol";

// ERC20 token interface
interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

// Bridge interface
interface IBridge {
    // Source: https://github.com/OffchainLabs/token-bridge-contracts/blob/main/contracts/tokenbridge/libraries/gateway/GatewayRouter.sol
    // Doc: https://docs.arbitrum.io/build-decentralized-apps/token-bridging/bridge-tokens-programmatically/how-to-bridge-tokens-standard
    /// @notice Initiates a token withdrawal from L2 to L1.
    /// @param _l1Token L1 address of token.
    /// @param _to Destination address on L1.
    /// @param _amount Amount of tokens to withdraw.
    /// @param _maxGas Max gas for L2 execution (unused for L2 to L1, pass 0).
    /// @param _gasPriceBid Gas price for L2 execution (unused for L2 to L1, pass 0).
    /// @param _data Additional data for the withdrawal.
    /// @return Encoded unique identifier for the withdrawal.
    function outboundTransfer(address _l1Token, address _to, uint256 _amount, uint256 _maxGas,
        uint256 _gasPriceBid, bytes calldata _data) external payable returns (bytes memory);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title Bridge2BurnerArbitrum - Smart contract for collecting OLAS on Arbitrum chain and relaying them back to L1 OLAS Burner contract.
contract Bridge2BurnerArbitrum is Bridge2Burner {
    // L1 OLAS token address
    address public immutable l1Olas;

    /// @dev Bridge2BurnerArbitrum constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address (L2GatewayRouter).
    /// @param _l1Olas L1 OLAS token address.
    constructor(address _olas, address _l2TokenRelayer, address _l1Olas) Bridge2Burner(_olas, _l2TokenRelayer) {
        if (_l1Olas == address(0)) {
            revert ZeroAddress();
        }

        l1Olas = _l1Olas;
    }

    /// @dev Relays OLAS to L1 Burner contract.
    function relayToL1Burner() external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS amount to bridge
        uint256 olasAmount = _getBalance();

        // Approve OLAS for L2 gateway router
        IToken(olas).approve(l2TokenRelayer, olasAmount);

        // Relay OLAS to L1 Burner contract via Arbitrum L2 Gateway Router
        IBridge(l2TokenRelayer).outboundTransfer(l1Olas, OLAS_BURNER, olasAmount, 0, 0, "");

        _locked = 1;
    }
}
