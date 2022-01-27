// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IRegistry.sol";

/// @title Mech Minter - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract MechMinter is Ownable, Pausable {
    address public immutable componentRegistry;
    address public immutable agentRegistry;
    uint256 private _mintFee;

    constructor(address _componentRegistry, address _agentRegistry) {
        require(_componentRegistry != address(0), "constructor: NULL_ADDRESS");
        componentRegistry = _componentRegistry;
        require(_agentRegistry != address(0), "constructor: NULL_ADDRESS");
        agentRegistry = _agentRegistry;
    }

    // TODO Need to use delegatecall or other more optimal ways in order to save on gas
    /// @dev Mints agent.
    /// @param owner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies.
    /// @return The minted id of the agent.
    function mintAgent(address owner, address developer, string memory agentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        return IRegistry(agentRegistry).create(owner, developer, agentHash, description, dependencies);
    }

    /// @dev Mints component.
    /// @param owner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies.
    /// @return The minted id of the component.
    function mintComponent(address owner, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        return IRegistry(componentRegistry).create(owner, developer, componentHash, description, dependencies);
    }
}
