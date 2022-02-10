// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IMultihash.sol";

/**
 * @dev Required interface for the component / agent manipulation.
 */
interface IRegistry is IMultihash, IERC721Enumerable {
    /**
     * @dev Creates component / agent with specified parameters for the ``owner``.
     */
    function create(
        address owner,
        address developer,
        Multihash memory componentHash,
        string memory description,
        uint256[] memory dependencies
    ) external returns (uint256);

    /**
     * @dev Updates the component / agent hash.
     */
    function updateHash(address owner, uint256 tokenId, Multihash memory componentHash) external;

    /**
     * @dev Check for the component / agent existence.
     */
    function exists(uint256 tokenId) external view returns (bool);

    /**
     * @dev Gets the component / agent info.
     */
    function getInfo(uint256 tokenId) external view returns (
        address developer,
        Multihash memory agentHash,
        string memory description,
        uint256 numDependencies,
        uint256[] memory dependencies
    );

    /**
     * @dev Gets the component / agent hashes.
     */
    function getHashes(uint256 tokenId) external view returns (uint256 numHashes, Multihash[] memory componentHashes);

    /**
     * @dev Returns component base URI.
     */
    function getBaseURI() external view returns (string memory);

    /**
     * @dev Sets component base URI.
     */
    function setBaseURI(string memory bURI) external;
}
