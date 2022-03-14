// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IMultihash.sol";

/**
 * @dev Required interface for the component / agent manipulation.
 */
interface IRegistry is IMultihash, IERC721Enumerable {
    /// @dev Creates component / agent.
    /// @param owner Owner of the component / agent.
    /// @param developer Developer of the component / agent.
    /// @param mHash IPFS hash of the component / agent.
    /// @param description Description of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address owner,
        address developer,
        Multihash memory mHash,
        string memory description,
        uint256[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param tokenId Token Id.
    /// @param mHash New IPFS hash of the component / agent.
    function updateHash(address owner, uint256 tokenId, Multihash memory mHash) external;

    /// @dev Check for the component / agent existence.
    /// @param tokenId Token Id.
    /// @return true if the component / agent exists, false otherwise.
    function exists(uint256 tokenId) external view returns (bool);

    /// @dev Gets the component / agent info.
    /// @param tokenId Token Id.
    /// @return owner Owner of the component / agent.
    /// @return developer The component developer.
    /// @return mHash The primary component / agent IPFS hash.
    /// @return description The component / agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 tokenId) external view returns (
        address owner,
        address developer,
        Multihash memory mHash,
        string memory description,
        uint256 numDependencies,
        uint256[] memory dependencies
    );

    /// @dev Gets component / agent dependencies.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 tokenId) external view returns (
        uint256 numDependencies,
        uint256[] memory dependencies
    );

    /// @dev Gets component / agent hashes.
    /// @param tokenId Token Id.
    /// @return numHashes Number of hashes.
    /// @return mHashes The list of component / agent hashes.
    function getHashes(uint256 tokenId) external view returns (uint256 numHashes, Multihash[] memory mHashes);

    /// @dev Returns component / agent base URI.
    /// @return base URI string.
    function getBaseURI() external view returns (string memory);

    /// @dev Sets component / agent base URI.
    /// @param bURI base URI string.
    function setBaseURI(string memory bURI) external;
}
