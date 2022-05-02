// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/// @dev Interface for voting escrow.
interface IVotingEscrow {
    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Token balance.
    /// @return pointIdx Index of a point with the requested block number balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance, uint256 pointIdx);

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    /// @return pointIdx Index of a point with the requested block number balance.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt, uint256 pointIdx);
}
