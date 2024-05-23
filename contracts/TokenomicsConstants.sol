// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title TokenomicsConstants - Smart contract with tokenomics constants
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract TokenomicsConstants {
    // Tokenomics version number
    string public constant VERSION = "1.2.0";
    // Tokenomics proxy address slot
    // keccak256("PROXY_TOKENOMICS") = "0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f"
    bytes32 public constant PROXY_TOKENOMICS = 0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f;
    // One year in seconds
    uint256 public constant ONE_YEAR = 1 days * 365;
    // Minimum epoch length
    uint256 public constant MIN_EPOCH_LENGTH = 10 days;
    // Max epoch length
    uint256 public constant MAX_EPOCH_LENGTH = ONE_YEAR - 1 days;
    // Minimum fixed point tokenomics parameters
    uint256 public constant MIN_PARAM_VALUE = 1e14;
    // Max staking weight amount
    uint256 public constant MAX_STAKING_WEIGHT = 10_000;

    /// @dev Gets an inflation cap for a specific year.
    /// @param numYears Number of years passed from the launch date.
    /// @return supplyCap Supply cap.
    /// supplyCap = 1e27 * (1.02)^(x-9) for x >= 10
    /// if_succeeds {:msg "correct supplyCap"} (numYears >= 10) ==> (supplyCap > 1e27);  
    /// There is a bug in scribble tools, a broken instrumented version is as follows:
    /// function getSupplyCapForYear(uint256 numYears) public returns (uint256 supplyCap)
    /// And the test is waiting for a view / pure function, which would be correct
    function getSupplyCapForYear(uint256 numYears) public pure returns (uint256 supplyCap) {
        // For the first 10 years the supply caps are pre-defined
        if (numYears < 10) {
            uint96[10] memory supplyCaps = [
                529_659_000e18,
                569_913_084e18,
                610_313_084e18,
                666_313_084e18,
                746_313_084e18,
                818_313_084e18,
                882_313_084e18,
                930_313_084e18,
                970_313_084e18,
                1_000_000_000e18
            ];
            supplyCap = supplyCaps[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            supplyCap = 1_000_000_000e18;
            // After that the inflation is 2% per year as defined by the OLAS contract
            uint256 maxMintCapFraction = 2;

            // Get the supply cap until the current year
            for (uint256 i = 0; i < numYears; ++i) {
                supplyCap += (supplyCap * maxMintCapFraction) / 100;
            }
            // Return the difference between last two caps (inflation for the current year)
            return supplyCap;
        }
    }

    /// @dev Gets an inflation amount for a specific year.
    /// @param numYears Number of years passed from the launch date.
    /// @return inflationAmount Inflation limit amount.
    function getInflationForYear(uint256 numYears) public pure returns (uint256 inflationAmount) {
        // For the first 10 years the inflation caps are pre-defined as differences between next year cap and current year one
        if (numYears < 10) {
            // Initial OLAS allocation is 526_500_000_0e17
            uint88[10] memory inflationAmounts = [
                3_159_000e18,
                40_254_084e18,
                40_400_000e18,
                56_000_000e18,
                80_000_000e18,
                72_000_000e18,
                64_000_000e18,
                48_000_000e18,
                40_000_000e18,
                29_686_916e18
            ];
            inflationAmount = inflationAmounts[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            uint256 supplyCap = 1_000_000_000e18;
            // After that the inflation is 2% per year as defined by the OLAS contract
            uint256 maxMintCapFraction = 2;

            // Get the supply cap until the year before the current year
            for (uint256 i = 1; i < numYears; ++i) {
                supplyCap += (supplyCap * maxMintCapFraction) / 100;
            }

            // Inflation amount is the difference between last two caps (inflation for the current year)
            inflationAmount = (supplyCap * maxMintCapFraction) / 100;
        }
    }
}
