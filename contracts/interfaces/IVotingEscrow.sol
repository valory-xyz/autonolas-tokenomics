// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/// @dev Interface for voting escrow.
interface IVotingEscrow is IStructs {
    /// @dev Gets historical points off an account.
    /// @param account Account address.
    /// @return numPoints Number of historical points.
    /// @return points Set of points.
    function getHistoryPoints(address account) external view returns (uint256 numPoints, PointVoting[] memory points);

    /// @dev Gets total supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return Token supply.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256);
}
