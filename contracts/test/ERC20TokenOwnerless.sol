// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../lib/solmate/src/tokens/ERC20.sol";

/// @title ERC20TokenOwnerless - Smart contract for mocking the standard ownerless ERC20 token functionality
contract ERC20TokenOwnerless is ERC20 {
    constructor()
        ERC20("ERC20 ownerless generic token", "ERC20TokenOwnerless", 18)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}