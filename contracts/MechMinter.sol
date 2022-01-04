// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentRegistry.sol";
import "./ComponentRegistry.sol";

/// @title Mech Minter - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract MechMinter is ERC721Pausable, Ownable {
    address public immutable componentRegistry;
    address public immutable agentRegistry;
    uint256 private _mintFee;

    // name = "mech minter", symbol = "MECHMINTER"
    constructor(address _componentRegistry, address _agentRegistry, string memory _name, string memory _symbol)
        ERC721(_name, _symbol) {
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
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        return agReg.createAgent(owner, developer, agentHash, description, dependencies);
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
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        return compRegistry.createComponent(owner, developer, componentHash, description, dependencies);
    }
}
