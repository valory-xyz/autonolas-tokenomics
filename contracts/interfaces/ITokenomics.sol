// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./IStructs.sol";

/// @dev Interface for tokenomics management.
interface ITokenomics is IStructs {
    /// @dev Gets the current epoch number.
    /// @return Current epoch number.
    function getCurrentEpoch() external view returns (uint256);

    /// @dev Gets effective bond (bond left).
    /// @return Effective bond.
    function effectiveBond() external pure returns (uint256);

    function epochLen() external view returns (uint256);
    function getDF(uint256 epoch) external view returns (uint256 df);
    function getPoint(uint256 epoch) external view returns (PointEcomonics memory _PE);
    function getLastPoint() external view returns (PointEcomonics memory _PE);
    function calculatePayoutFromLP(address token, uint256 tokenAmount) external returns (uint256 amountOLA);
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external
        returns (uint256 revenueETH, uint256 donationETH);
    function checkpoint() external;
    function getExchangeAmountOLA(address token, uint256 tokenAmount) external returns (uint256 amount);
    function getProfitableComponents() external view returns (address[] memory profitableComponents, uint256[] memory ucfcs);
    function getProfitableAgents() external view returns (address[] memory profitableAgents, uint256[] memory ucfcs);
    function usedBond(uint256 payout) external;
    function allowedNewBond(uint256 amount) external returns(bool);

    /// @dev Gets the component / agent owner reward and zeros the record of it being written off.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerRewards(address account) external returns (uint256 reward, uint256 topUp);

    /// @dev Calculates staking rewards.
    /// @param account Account address.
    /// @param startEpochNumber Epoch number at which the reward starts being calculated.
    /// @return reward Reward amount up to the last possible epoch.
    /// @return topUp Top-up amount up to the last possible epoch.
    /// @return endEpochNumber Epoch number where the reward calculation will start the next time.
    function calculateStakingRewards(address account, uint256 startEpochNumber) external view
        returns (uint256 reward, uint256 topUp, uint256 endEpochNumber);

    /// @dev Checks for the OLA minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLA tokens to mint.
    /// @return True if the mint is allowed.
    function isAllowedMint(uint256 amount) external returns (bool);
}
