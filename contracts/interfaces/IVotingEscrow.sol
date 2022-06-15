// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/// @dev Interface for voting escrow.
interface IVotingEscrow {
    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Token balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance);

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt);
}
