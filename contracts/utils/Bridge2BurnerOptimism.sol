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
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/L2/L2StandardBridge.sol#L121
    /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
    ///         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
    ///         be locked in the L1StandardBridge. ETH may be recoverable if the call can be
    ///         successfully replayed by increasing the amount of gas supplied to the call. If the
    ///         call will fail for any amount of gas, then the ETH will be locked permanently.
    ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
    ///         `bridgeERC20To` function to bridge native L2 tokens to L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function withdrawTo(address _l2Token, address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData)
        external;
}

/// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title Bridge2BurnerOptimism - Smart contract for collecting OLAS on OP chain and relaying them back to L1 OLAS Burner contract.
contract Bridge2BurnerOptimism is Bridge2Burner {
    // Token transfer gas limit for L1
    // This is safe as the value is practically bigger than observed ones on numerous chains
    uint32 public constant TOKEN_GAS_LIMIT = 300_000;

    /// @dev Bridge2BurnerOptimism constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address.
    constructor(address _olas, address _l2TokenRelayer) Bridge2Burner(_olas, _l2TokenRelayer) {}

    /// @dev Relays OLAS to L1 Burner contract.
    function relayToL1Burner() external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS amount to bridge
        uint256 olasAmount = _getBalance();

        // Approve OLAS for token relayer contract
        IToken(olas).approve(l2TokenRelayer, olasAmount);

        // Relay OLAS to L1 Burner contract
        IBridge(l2TokenRelayer).withdrawTo(olas, OLAS_BURNER, olasAmount, TOKEN_GAS_LIMIT, "0x");

        _locked = 1;
    }
}
