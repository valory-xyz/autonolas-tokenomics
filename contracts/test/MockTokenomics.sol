// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Contract for mocking several tokenomics functions.
contract MockTokenomics {
    uint256 public epochCounter = 1;
    uint256 public mintCap = 1_000_000_000e18;
    uint256 public topUps = 40 ether;
    uint256 public lastIDF = 1e18;
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
    function trackServiceDonations(address, uint256[] memory, uint256[] memory, uint256 donationETH) external pure
    {
    }

    /// @dev Record global data to the checkpoint.
    function checkpoint() external {
        epochCounter = 2;
    }

    /// @dev Sets service registry contract address.
    function setServiceRegistry(address _serviceRegistry) external {
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Simulates the function that fails.
    function simulateFailure() external pure {
        revert();
    }

    /// @dev Reserves OLAS amount from the effective bond to be minted during a bond program.
    function reserveAmountForBondProgram(uint256) external pure returns (bool) {
        return true;
    }

    /// @dev Refunds unused bond program amount when the program is closed.
    function refundFromBondProgram(uint256) external {
    }

    /// @dev Gets last IDF
    function getLastIDF() external view returns (uint256) {
        return lastIDF;
    }
}
