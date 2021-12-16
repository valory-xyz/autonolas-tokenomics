// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MechMinter.sol";

contract ProxyMinter is Ownable {
    address private _minter;

    constructor() {
    }

    // Mint component according to developer's address and component parameters
    function mintComponent(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
    {
        MechMinter mechMinter = MechMinter(_minter);
        mechMinter.mintComponent(owner, developer, componentHash, description, dependencies);
    }

    // Upgrade the mech minter
    function upgradeMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0));
        _minter = newMinter;
    }
}
