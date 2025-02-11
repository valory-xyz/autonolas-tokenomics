// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/// @dev Zero data.
error ZeroData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a BuyBackBurner proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special buyBackBurner implementation address slot is produced by hashing the "BUY_BACK_BURNER_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title BuyBackBurnerProxy - Smart contract for buyBackBurner proxy
contract BuyBackBurnerProxy {
    // Code position in storage is keccak256("BUY_BACK_BURNER_PROXY") = "c6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19"
    bytes32 public constant BUY_BACK_BURNER_PROXY = 0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19;

    /// @dev BuyBackBurnerProxy constructor.
    /// @param implementation BuyBackBurner implementation address.
    /// @param buyBackBurnerData BuyBackBurner initialization data.
    constructor(address implementation, bytes memory buyBackBurnerData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Check for the zero data
        if (buyBackBurnerData.length == 0) {
            revert ZeroData();
        }

        // Store the buyBackBurner implementation address
        assembly {
            sstore(BUY_BACK_BURNER_PROXY, implementation)
        }
        // Initialize proxy storage
        (bool success, ) = implementation.delegatecall(buyBackBurnerData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        assembly {
            let implementation := sload(BUY_BACK_BURNER_PROXY)
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
    /// @return implementation Implementation address.
    function getImplementation() external view returns (address implementation) {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            implementation := sload(BUY_BACK_BURNER_PROXY)
        }
    }
}