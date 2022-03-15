// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @dev IPFS multihash.
 */
interface IStructs {
    // Canonical agent Id parameters
    struct AgentParams {
        // Number of agent instances
        uint256 slots;
        // Bond per agent instance
        uint256 bond;
    }

    // Multihash according to self-describing hashes standard. For more information of multihashes please visit https://multiformats.io/multihash/
    struct Multihash {
        // IPFS uses a sha2-256 hashing function. Each IPFS hash has to start with 1220.
        bytes32 hash;
        // Code in hex for sha2-256 is 0x12
        uint8 hashFunction;
        // Length of the hash is 32 bytes, or 0x20 in hex
        uint8 size;
    }
}
