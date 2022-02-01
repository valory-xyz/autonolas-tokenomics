// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev IPFS multihash.
 */
interface IMultihash {
    struct Multihash {
        bytes32 hash;
        uint8 hashFunction;
        uint8 size;
    }
}
