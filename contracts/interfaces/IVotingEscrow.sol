// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/// @dev Interface for voting escrow.
interface IVotingEscrow {
    /// @dev Gets historical points of an account.
    /// @param account Account address.
    /// @param startBlock Starting block.
    /// @param endBlock Ending block.
    /// @return numBlockCheckpoints Number of distinct block numbers where balances change.
    /// @return blocks Set of block numbers where balances change.
    /// @return balances Set of balances correspondent to set of block numbers.
    function getHistoryAccountBalances(address account, uint256 startBlock, uint256 endBlock) external view
        returns (uint256 numBlockCheckpoints, uint256[] memory blocks, uint256[] memory balances);

    /// @dev Gets historical total supply values.
    /// @param startBlock Starting block.
    /// @param endBlock Ending block.
    /// @return numBlockCheckpoints Number of distinct block numbers where balances change.
    /// @return blocks Set of block numbers where balances change.
    /// @return balances Set of balances correspondent to set of block numbers.
    function getHistoryTotalSupply(uint256 startBlock, uint256 endBlock) external view
        returns (uint256 numBlockCheckpoints, uint256[] memory blocks, uint256[] memory balances);
}
