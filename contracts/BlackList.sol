// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

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

    /// @dev Controls accounts blacklisting statuses.
    /// @param accounts Set of account addresses.
    /// @param statuses Set blacklisting statuses.
    /// @return success True, if the function executed successfully.
    function setAccountsStatuses(address[] memory accounts, bool[] memory statuses) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the array length
        if (accounts.length != statuses.length) {
            revert WrongArrayLength(accounts.length, statuses.length);
        }

        for (uint256 i = 0; i < accounts.length; ++i) {
            // Check for the zero address
            if (accounts[i] == address(0)) {
                revert ZeroAddress();
            }
            // Set the account blacklisting status
            mapBlackListedAddresses[accounts[i]] = statuses[i];
            emit BlackListStatus(accounts[i], statuses[i]);
        }
        success = true;
    }

    /// @dev Gets account blacklisting status.
    /// @param account Account address.
    /// @return status Blacklisting status.
    function isBlackListed(address account) external view returns (bool status) {
        status = mapBlackListedAddresses[account];
    }
}
