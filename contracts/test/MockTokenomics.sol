// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Contract for mocking several tokenomics functions.
contract MockTokenomics {
    uint32 public epochCounter = 1;
    uint96 public mintCap = 1_000_000_000e18;
    uint96 public topUps = 40 ether;
    address public serviceRegistry;

    /// @dev Changes the mint cap.
    /// @param _mintCap New mint cap.
    function changeMintCap(uint96 _mintCap) external {
        mintCap = _mintCap;
    }

    /// @dev Changes the top-ups value.
    /// @param _topUps New top-up value.
    function changeTopUps(uint96 _topUps) external {
        topUps = _topUps;
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @return revenueETH Revenue of protocol-owned services.
    /// @return donationETH Donations to services.
    function trackServicesETHRevenue(uint32[] memory, uint96[] memory) external pure
        returns (uint96 revenueETH, uint96 donationETH)
    {
        revenueETH = 1000 ether;
        donationETH = 1 ether;
    }

    /// @dev Gets rewards data of the last epoch.
    /// @return treasuryRewards Treasury rewards.
    /// @return accountRewards Cumulative staker, component and agent rewards.
    /// @return accountTopUps Cumulative staker, component and agent top-ups.
    function getRewardsData() external view
        returns (uint96 treasuryRewards, uint96 accountRewards, uint96 accountTopUps)
    {
        treasuryRewards = 10 ether;
        accountRewards = 50 ether;
        accountTopUps = topUps;
    }

    /// @dev Checks for the OLA minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLA tokens to mint.
    /// @return True if the mint is allowed.
    function isAllowedMint(uint256 amount) external view returns (bool) {
        if (amount < mintCap) {
            return true;
        }
        return false;
    }

    /// @dev Record global data to the checkpoint.
    function checkpoint() external {
        epochCounter = 2;
    }

    /// @dev Sets service registry contract address.
    function setServiceRegistry(address _serviceRegistry) external {
        serviceRegistry = _serviceRegistry;
    }
}
