// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero Value.
error ZeroValue();

/*
* This is a proxy contract for dispenser.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special dispenser implementation address slot is produced by hashing the "PROXY_DISPENSER" string
* in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title DispenserProxy - Smart contract for dispenser proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract DispenserProxy {
    // Code position in storage is keccak256("PROXY_DISPENSER") = "0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83"
    bytes32 public constant PROXY_DISPENSER = 0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83;

    /// @dev DispenserProxy constructor.
    /// @param dispenser Dispenser implementation address.
    /// @param dispenserData Dispenser initialization data.
    constructor(address dispenser, bytes memory dispenserData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (dispenser == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (dispenserData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_DISPENSER, dispenser)
        }
        // Initialize proxy dispenser storage
        (bool success, ) = dispenser.delegatecall(dispenserData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        assembly {
            let dispenser := sload(PROXY_DISPENSER)
            // Otherwise continue with the delegatecall to the dispenser implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), dispenser, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
