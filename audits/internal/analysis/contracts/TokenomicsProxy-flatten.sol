// The following code is from flattening this file: TokenomicsProxy.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @title TokenomicsProxy - Smart contract for tokenomics proxy
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract TokenomicsProxy {
    // Code position in storage is keccak256("PROXY_TOKENOMICS") = "0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f"
    bytes32 public constant PROXY_TOKENOMICS = 0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f;

    /// @dev TokenomicsProxy constructor.
    /// @param tokenomics Tokenomics implementation address.
    constructor(address tokenomics, bytes memory tokenomicsData) {
        assembly {
            sstore(PROXY_TOKENOMICS, tokenomics)
        }
        // Initialize proxy tokenomics storage
        (bool success, ) = tokenomics.delegatecall(tokenomicsData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let tokenomics := sload(PROXY_TOKENOMICS)
            // Otherwise continue with the delegatecall to the tokenomics implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), tokenomics, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}



