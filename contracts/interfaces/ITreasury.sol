// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Interface for treasury management.
interface ITreasury {
    /// @dev Allows approved address to deposit an asset for OLA.
    /// @param tokenAmount Token amount to get OLA for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLA token issued.
    function depositTokenForOLA(uint256 tokenAmount, address token, uint256 olaMintAmount) external;

    /// @dev Deposits ETH from protocol-owned service.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of amounts.
    function depositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external payable;

    /// @dev Allows manager to withdraw specified tokens from reserves
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token address.
    function withdraw(uint256 tokenAmount, address token) external;

    /// @dev Enables a token to be exchanged for OLA.
    /// @param token Token address.
    function enableToken(address token) external;

    /// @dev Disables a token from the ability to exchange for OLA.
    /// @param token Token address.
    function disableToken(address token) external;

    /// @dev Gets information about token being enabled.
    /// @param token Token address.
    /// @return enabled True is token is enabled.
    function isEnabled(address token) external view returns (bool enabled);

    /// @dev Requests OLA funds from treasury.
    function requestFunds(uint256 amount) external;

    /// @dev Starts a new epoch.
    function allocateRewards() external returns (bool);
}
