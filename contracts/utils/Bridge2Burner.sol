// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ERC20 token interface
interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Underflow of values.
/// @param provided Provided value.
/// @param min Min required value.
error Underflow(uint256 provided, uint256 min);

/// @title Bridge2Burner - Smart contract for collecting OLAS and relaying them back to L1 OLAS Burner contract.
abstract contract Bridge2Burner {
    // Version number
    string public constant VERSION = "0.1.0";
    // L1 OLAS Burner address
    address public constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    // Min OLAS balance to transfer
    uint256 public constant MIN_OLAS_BALANCE = 10 ether;

    // L2 OLAS address
    address public immutable olas;
    // L2 Token relayer address that sends tokens to the L1 source network
    address public immutable l2TokenRelayer;

    // Reentrancy lock
    uint256 internal _locked;

    /// @dev Bridge2Burner constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address.
    constructor(address _olas, address _l2TokenRelayer) {
        // Check for zero addresses
        if (_olas == address(0) || _l2TokenRelayer == address(0)) {
            revert ZeroAddress();
        }

        // Immutable parameters assignment
        olas = _olas;
        l2TokenRelayer = _l2TokenRelayer;

        _locked = 1;
    }

    /// @dev Gets OLAS balance.
    /// @param olasBalance OLAS balance.
    function _getBalance() internal virtual returns (uint256 olasBalance) {
        // Get OLAS balance
        olasBalance = IToken(olas).balanceOf(address(this));

        // Check for underflow value
        if (olasBalance < MIN_OLAS_BALANCE) {
            revert Underflow(olasBalance, MIN_OLAS_BALANCE);
        }
    }

    /// @dev Relays OLAS to L1 Burner contract.
    /// @param bridgePayload Bridge payload.
    function relayToL1Burner(bytes memory bridgePayload) external virtual;

    /// @dev Relays OLAS to L1 Burner contract where msg.value is required.
    /// @param bridgePayload Bridge payload.
    function relayToL1BurnerPayable(bytes memory bridgePayload) external virtual payable;
}
