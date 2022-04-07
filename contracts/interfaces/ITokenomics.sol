// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Interface for tokenomics management.
interface ITokenomics {
    function getDF(uint256 epoch) external view returns (uint256 df);
    function getEpochLen() external view returns (uint256);
    function calculatePayoutFromLP(address token, uint256 tokenAmount, uint _epoch) external returns (uint256 resAmount);
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external;
}
