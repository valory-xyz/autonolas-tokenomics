// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ComponentRegistry.sol";

contract MechMinter is ERC721Pausable, Ownable {
    address public immutable componentRegistry;
    address public immutable agentRegistry;
    uint256 private _mintFee;

    constructor(address compReg, address agReg) ERC721("MechMinter", "MECHMINT") {
        componentRegistry = componentRegistry;
        agentRegistry = agReg;
    }

    // Change the minter
    function changeMinterInRegistry(address newMinter) public onlyOwner {
        require(newMinter != address(0));
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        compRegistry.changeMinter(newMinter);
        transferOwnership(newMinter);
    }

    // Mint component function
    function mintComponent(uint256 tokenId, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        external
    {
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        compRegistry.createComponent(owner, developer, componentHash, description, dependencies);
    }
}
