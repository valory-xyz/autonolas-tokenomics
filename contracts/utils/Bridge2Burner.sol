// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Provided zero address.
error ZeroAddress();

/// @title Bridge2Burner - Smart contract for collecting OLAS and relaying them back to L1 OLAS Burner contract.
abstract contract Bridge2Burner {
    // Version number
    string public constant VERSION = "0.1.0";
    // L1 OLAS Burner address
    address public constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;

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

    /// @dev Relays OLAS to L1 Burner contract.
    /// @param bridgePayload Bridge payload.
    function relayToL1Burner(bytes memory bridgePayload) external payable virtual;
}
