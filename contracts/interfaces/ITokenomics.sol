// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/// @dev Interface for tokenomics management.
interface ITokenomics is IStructs {
    /// @dev Converts the block number into epoch number.
    /// @param blockNumber Block number.
    /// @return epochNumber Epoch number
    function getEpoch(uint256 blockNumber) external view returns (uint256 epochNumber);
    function getCurrentEpoch() external view returns (uint256 epochNumber);

    function epochLen() external view returns (uint256);
    function getDF(uint256 epoch) external view returns (uint256 df);
    function getEpochLen() external view returns (uint256);
    function getPoint(uint256 epoch) external view returns (PointEcomonics memory _PE);
    function getLastPoint() external view returns (PointEcomonics memory _PE);
    function calculatePayoutFromLP(address token, uint256 tokenAmount, uint _epoch) external returns (uint256 resAmount);
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external
        returns (uint256 revenueETH, uint256 donationETH);
    function checkpoint() external;
    function getExchangeAmountOLA(address token, uint256 tokenAmount) external returns (uint256 amount);
    function getProfitableComponents() external view returns (address[] memory profitableComponents, uint256[] memory ucfcs);
    function getProfitableAgents() external view returns (address[] memory profitableAgents, uint256[] memory ucfcs);
    function usedBond(uint256 payout) external;
    function allowedNewBond(uint256 amount) external returns(bool);
    function getBondLeft() external view returns (uint256 bondLeft);
    function getBondCurrentEpoch() external view returns (uint256 bondPerEpoch);

    /// @dev Gets the component / agent owner reward and zeros the record of it being written off.
    /// @param account Account address.
    /// @return reward Reward amount.
    function accountOwnerRewards(address account) external returns (uint256 reward);
}
