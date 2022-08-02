// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @title ERC20Token - Smart contract for mocking the minimum OLAS token functionality
contract ERC20Token is ERC20, Ownable {
    // Initial timestamp of the token deployment
    uint256 public immutable timeLaunch;
    // Minter address
    address public minter;

    constructor() ERC20("ERC20 generic mocking token", "ERC20Token") {
        timeLaunch = block.timestamp;
        minter = msg.sender;
    }

    /// @dev Changes the minter address.
    /// @param newMinter Address of a new minter.
    function changeMinter(address newMinter) external {
        if (msg.sender != owner()) {
            revert ManagerOnly(msg.sender, owner());
        }

        minter = newMinter;
    }

    function mint(address to, uint256 amount) external {
        // Access control
        if (msg.sender != minter) {
            revert ManagerOnly(msg.sender, minter);
        }

        _mint(to, amount);
    }

    /// @dev Gets the reminder of OLA possible for the mint.
    /// @return remainder OLA token remainder.
    function inflationRemainder() external view returns (uint256 remainder) {
        return totalSupply();
    }
}