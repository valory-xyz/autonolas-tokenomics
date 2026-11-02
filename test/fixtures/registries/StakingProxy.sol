// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/*
* This is a Service Staking proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special service staking implementation address slot is produced by hashing the "SERVICE_STAKING_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title StakingProxy - Smart contract for service staking proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingProxy {
    // Code position in storage is keccak256("SERVICE_STAKING_PROXY") = "0x9e5e169c1098011e4e5940a3ec1797686b2a8294a9b77a4c676b121bdc0ebb5e"
    bytes32 public constant SERVICE_STAKING_PROXY = 0x9e5e169c1098011e4e5940a3ec1797686b2a8294a9b77a4c676b121bdc0ebb5e;

    /// @dev StakingProxy constructor.
    /// @param implementation Service staking implementation address.
    constructor(address implementation) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Store the service staking implementation address
        assembly {
            sstore(SERVICE_STAKING_PROXY, implementation)
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        assembly {
            let implementation := sload(SERVICE_STAKING_PROXY)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }

    /// @dev Gets the implementation address.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(SERVICE_STAKING_PROXY)
        }
    }
}