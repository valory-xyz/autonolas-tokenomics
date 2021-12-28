// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentRegistry.sol";
import "./ComponentRegistry.sol";

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

    // Mint agent function
    // Need to use delegatecall or other more optimal ways in order to save on gas
    function mintAgent(address owner, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        return agReg.createAgent(owner, developer, componentHash, description, dependencies);
    }

    // Mint component function
    function mintComponent(address owner, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        public
        returns (uint256)
    {
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        return compRegistry.createComponent(owner, developer, componentHash, description, dependencies);
    }
}
