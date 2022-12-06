// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title TokenomicsProxy - Smart contract for tokenomics proxy
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract TokenomicsProxy {
    event TokenomicsUpdated(address indexed tokenomics);

    /// @dev TokenomicsProxy constructor.
    /// @param tokenomics Tokenomics implementation address.
    constructor(address tokenomics, bytes memory tokenomicsData) {
        // Code position in storage is keccak256("PROXY_TOKENOMICS") = "0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f"
        assembly {
            sstore(0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f, tokenomics)
        }
        // Initialize tokenomics storage
//        (bool success, bytes memory result) = tokenomics.delegatecall(tokenomicsData);
//        if (!success) {
//            revert();
//        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let tokenomics := sload(0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f)
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
