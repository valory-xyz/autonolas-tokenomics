// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @dev Required interface for the component / agent manipulation.
 */
interface IRegistry is IERC721Enumerable {
    // IPFS hash
    struct Multihash {
        bytes32 hash;
        uint8 hashFunction;
        uint8 size;
    }

    /**
     * @dev Creates component / agent with specified parameters for the ``owner``.
     */
    function create(
        address owner,
        address developer,
        string memory componentHash,
        string memory description,
        uint256[] memory dependencies
    ) external returns (uint256);

    /**
     * @dev Check for the component / agent existence.
     */
    function exists(uint256 tokenId) external view returns (bool);

    /**
     * @dev Gets the component / agent info.
     */
    function getInfo(uint256 tokenId) external view returns (
        address developer,
        string memory agentHash,
        string memory description,
        uint256 numDependencies,
        uint256[] memory dependencies
    );

    /**
     * @dev Returns component base URI.
     */
    function getBaseURI() external view returns (string memory);

    /**
     * @dev Sets component base URI.
     */
    function setBaseURI(string memory bURI) external;
}
