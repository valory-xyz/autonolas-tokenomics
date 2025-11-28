// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero Value.
error ZeroValue();

/*
* This is a proxy contract for liquidity manager.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special liquidity manager implementation address slot is produced by hashing the "PROXY_LIQUIDITY_MANAGER" string
* in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title LiquidityManagerProxy - Smart contract for liquidity manager proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerProxy {
    // Code position in storage is keccak256("PROXY_LIQUIDITY_MANAGER") = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
    bytes32 public constant PROXY_LIQUIDITY_MANAGER = 0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd;

    /// @dev LiquidityManagerProxy constructor.
    /// @param liquidityManager Liquidity Manager implementation address.
    /// @param liquidityManagerData Liquidity Manager initialization data.
    constructor(address liquidityManager, bytes memory liquidityManagerData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (liquidityManager == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (liquidityManagerData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_LIQUIDITY_MANAGER, liquidityManager)
        }
        // Initialize proxy liquidity manager storage
        (bool success, ) = liquidityManager.delegatecall(liquidityManagerData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        assembly {
            let liquidityManager := sload(PROXY_LIQUIDITY_MANAGER)
            // Otherwise continue with the delegatecall to the liquidity manager implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), liquidityManager, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
