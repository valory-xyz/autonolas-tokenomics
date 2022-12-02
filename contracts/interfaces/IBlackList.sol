// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev BlackList interface.
interface IBlackList {
    /// @dev Gets account blacklisting status.
    /// @param account Account address.
    /// @return status Blacklisting status.
    function isBlackListed(address account) external view returns (bool status);
}
