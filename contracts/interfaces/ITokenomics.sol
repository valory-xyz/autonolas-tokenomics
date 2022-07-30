// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @dev Interface for tokenomics management.
interface ITokenomics {
    /// @dev Gets effective bond (bond left).
    /// @return Effective bond.
    function effectiveBond() external pure returns (uint256);

    /// @dev Record global data to the checkpoint
    function checkpoint() external;

    /// @dev Calculates the amount of OLAS tokens based on LP.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutFromLP(uint256 tokenAmount, uint256 priceLP) external
        returns (uint256 amountOLAS);

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external
        returns (uint256 revenueETH, uint256 donationETH);

    /// @dev Increases the bond per epoch with the OLAS payout for a Depository program
    /// @param payout Payout amount for the LP pair.
    function usedBond(uint256 payout) external;

    /// @dev Checks if the the effective bond value per current epoch is enough to allocate the specific amount.
    /// @notice Programs exceeding the limit in the epoch are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return True if effective bond threshold is not reached.
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

    /// @dev Gets rewards data of the last epoch.
    /// @return treasuryRewards Treasury rewards.
    /// @return accountRewards Cumulative staker, component and agent rewards.
    /// @return accountTopUps Cumulative staker, component and agent top-ups.
    function getRewardsData() external view
        returns (uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps);

    /// @dev Get reserveX/reserveY at the time of product creation.
    /// @param token Token address.
    /// @return priceLP Resulting reserve ratio.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP);
}
