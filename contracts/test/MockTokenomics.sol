// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Contract for mocking several tokenomics functions.
contract MockTokenomics {
    uint256 public epochCounter = 1;
    uint256 public mintCap = 1_000_000_000e18;
    uint256 public topUps = 40 ether;
    address public serviceRegistry;
    bool public initialized;

    function initialize() external {
        if (initialized) {
            revert();
        }
        initialized = true;
    }

    /// @dev Gets the tokenomics implementation address.
    function tokenomicsImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f)
        }
        return implementation;
    }

    /// @dev Changes the mint cap.
    /// @param _mintCap New mint cap.
    function changeMintCap(uint256 _mintCap) external {
        mintCap = _mintCap;
    }

    /// @dev Changes the top-ups value.
    /// @param _topUps New top-up value.
    function changeTopUps(uint256 _topUps) external {
        topUps = _topUps;
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @return donationETH Donations to services.
    function trackServiceDonations(address, uint256[] memory, uint256[] memory) external pure
        returns (uint256 donationETH)
    {
        donationETH = 1 ether;
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
