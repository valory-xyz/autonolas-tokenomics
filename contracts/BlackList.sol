// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @title BlackList - Smart contract for account address blacklisting
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract BlackList {
    event OwnerUpdated(address indexed owner);
    event BlackListStatus(address indexed account, bool status);

    // Owner address
    address public owner;
    // Mapping account address => blacklisting status
    mapping(address => bool) public mapBlackListedAddresses;

    /// @dev BlackList constructor.
    constructor() {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Controls account blacklisting status.
    /// @param account Account address.
    /// @param status Sets or unsets blacklisting status.
    /// @return success True, if the function executed successfully.
    function setBlackListStatus(address account, bool status) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (account == address(0)) {
            revert ZeroAddress();
        }

        // Set the account blacklisting status
        mapBlackListedAddresses[account] = status;
        success = true;

        emit BlackListStatus(account, status);
    }

    /// @dev Gets account blacklisting status.
    /// @param account Account address.
    /// @return status Blacklisting status.
    function isBlackListed(address account) external view returns (bool status) {
        status = mapBlackListedAddresses[account];
    }
}
