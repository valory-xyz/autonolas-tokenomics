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
    // Contract: Omnibridge Multi-Token Mediator Proxy
    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/components/common/TokensRelayer.sol#L54
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
    function relayTokens(address token, address receiver, uint256 amount) external;
}

/// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title Bridge2BurnerGnosis - Smart contract for collecting OLAS on Gnosis chain and relaying them back to L1 OLAS Burner contract.
contract Bridge2BurnerGnosis is Bridge2Burner {
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
        IBridge(l2TokenRelayer).relayTokens(olas, OLAS_BURNER, olasAmount);

        _locked = 1;
    }
}
