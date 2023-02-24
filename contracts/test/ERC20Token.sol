// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @dev Provided zero address.
error ZeroAddress();

/// @title ERC20Token - Smart contract for mocking the minimum OLAS token functionality
contract ERC20Token is ERC20 {
    // Initial timestamp of the token deployment
    uint256 public immutable timeLaunch;
    // Owner address
    address public owner;
    // Minter address
    address public minter;

    constructor() ERC20("ERC20 generic token", "ERC20Token", 18) {
        timeLaunch = block.timestamp;
        minter = msg.sender;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert ManagerOnly(msg.sender, owner);
        }

        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
    }

    /// @dev Changes the minter address.
    /// @param newMinter Address of a new minter.
    function changeMinter(address newMinter) external {
        if (msg.sender != owner) {
            revert ManagerOnly(msg.sender, owner);
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
        return totalSupply;
    }
}