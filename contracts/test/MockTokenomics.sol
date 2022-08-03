// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @dev Contract for mocking several tokenomics functions.
contract MockTokenomics {
    uint256 public epochCounter = 1;

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @return revenueETH Revenue of protocol-owned services.
    /// @return donationETH Donations to services.
    function trackServicesETHRevenue(uint256[] memory, uint256[] memory) external pure
        returns (uint256 revenueETH, uint256 donationETH)
    {
        revenueETH = 1000 ether;
        donationETH = 1 ether;
    }

    /// @dev Gets rewards data of the last epoch.
    /// @return treasuryRewards Treasury rewards.
    /// @return accountRewards Cumulative staker, component and agent rewards.
    /// @return accountTopUps Cumulative staker, component and agent top-ups.
    function getRewardsData() external pure
        returns (uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps)
    {
        treasuryRewards = 10 ether;
        accountRewards = 50 ether;
        accountTopUps = 40 ether;
    }

    /// @dev Checks for the OLA minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLA tokens to mint.
    /// @return True if the mint is allowed.
    function isAllowedMint(uint256 amount) external pure returns (bool) {
        if (amount < 1_000_000_000_000e18) {
            return true;
        }
        return false;
    }

    /// @dev Record global data to the checkpoint
    function checkpoint() external {
        epochCounter = 2;
    }
}
