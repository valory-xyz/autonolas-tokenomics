// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/// @dev Interface for tokenomics management.
interface ITokenomics is IStructs {

    function epochLen() external view returns (uint256);
    function getDF(uint256 epoch) external view returns (uint256 df);
    function getEpochLen() external view returns (uint256);
    function getLastPoint() external view returns (PointEcomonics memory _PE);
    function calculatePayoutFromLP(address token, uint256 tokenAmount, uint _epoch) external returns (uint256 resAmount);
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external;
    function checkpoint() external;
    function getExchangeAmountOLA(address token, uint256 tokenAmount) external returns (uint256 amount);
    function getProfitableComponents() external view returns (address[] memory profitableComponents, uint256[] memory ucfcs);
    function getProfitableAgents() external view returns (address[] memory profitableAgents, uint256[] memory ucfcs);
}
