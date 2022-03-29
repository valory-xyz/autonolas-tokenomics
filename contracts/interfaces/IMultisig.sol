// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Generic multisig.
interface IMultisig {
    /// @dev Creates a multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Packed data related to the creation of a chosen multisig.
    /// @return multisig Address of a created multisig.
    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig);

    /// @dev Executes transaction on behalf of the multisig.
    /// @param destination Destination address.
    /// @param value Value to be sent, if any.
    /// @param data Packed data related to the chosen multisig, including payload data and other.
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v}).
    /// @param success True if the function executes correctly.
    function execute(
        address destination,
        uint256 value,
        bytes memory data,
        bytes memory signatures
    ) external returns (bool success);

    /// @dev Adds owner to the multisig and updates a threshold in the same transaction, if needed.
    /// @param owner New owner address.
    /// @param threshold New signature threshold.
    /// @param success True if the function executes correctly.
    function addOwner(address owner, uint256 threshold) external returns (bool success);

    /// @dev Removes owner from the multisig and updates a threshold in the same transaction, if needed.
    /// @param owner Owner address to be removed.
    /// @param threshold New signature threshold.
    /// @param success True if the function executes correctly.
    function removeOwner(address owner, uint256 threshold) external returns (bool success);

    /// @dev Changes signature threshold.
    /// @param threshold New signature threshold.
    /// @param success True if the function executes correctly.
    function changeThreshold(uint256 threshold) external returns (bool success);
}