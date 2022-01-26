// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRegistry {
    // IPFS hash
    struct Multihash {
        bytes32 hash;
        uint8 hashFunction;
        uint8 size;
    }

    // Create component / agent
    function create(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
        returns (uint256);
}
