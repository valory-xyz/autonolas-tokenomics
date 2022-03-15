// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IRegistry.sol";

/// @title Registries Manager - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract RegistriesManager is IStructs, Ownable, Pausable {
    address public immutable componentRegistry;
    address public immutable agentRegistry;
    uint256 private _mintFee;

    constructor(address _componentRegistry, address _agentRegistry) {
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
    }

    /// @dev Mints agent.
    /// @param owner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted agent.
    function mintAgent(address owner, address developer, Multihash memory agentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        return IRegistry(agentRegistry).create(owner, developer, agentHash, description, dependencies);
    }

    /// @dev Updates the agent hash.
    /// @param tokenId Token Id.
    /// @param agentHash New IPFS hash of the agent.
    function updateAgentHash(uint256 tokenId, Multihash memory agentHash) public {
        return IRegistry(agentRegistry).updateHash(msg.sender, tokenId, agentHash);
    }

    /// @dev Mints component.
    /// @param owner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component.
    function mintComponent(address owner, address developer, Multihash memory componentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        return IRegistry(componentRegistry).create(owner, developer, componentHash, description, dependencies);
    }

    /// @dev Updates the component hash.
    /// @param tokenId Token Id.
    /// @param componentHash New IPFS hash of the component.
    function updateComponentHash(uint256 tokenId, Multihash memory componentHash) public {
        return IRegistry(componentRegistry).updateHash(msg.sender, tokenId, componentHash);
    }
}
