// The following code is from flattening this file: TokenomicsConstants.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title Dispenser - Smart contract with tokenomics constants
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract TokenomicsConstants {
    // One year in seconds
    uint256 public constant oneYear = 1 days * 365;

    /// @dev Gets an inflation cap for a specific year.
    /// @param numYears Number of years passed from the launch date.
    /// @return supplyCap Supply cap.
    function getSupplyCapForYear(uint256 numYears) public pure returns (uint256 supplyCap) {
        // For the first 10 years the supply caps are pre-defined
        if (numYears < 10) {
            uint96[10] memory supplyCaps = [
                548_613_000_0e17,
                628_161_885_0e17,
                701_028_663_7e17,
                766_084_123_6e17,
                822_958_209_0e17,
                871_835_342_9e17,
                913_259_378_7e17,
                947_973_171_3e17,
                976_799_806_9e17,
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
            // TODO study if it's cheaper to allocate new uint256[](10)
            uint88[10] memory inflationAmounts = [
                22_113_000_0e17,
                79_548_885_0e17,
                72_866_778_7e17,
                65_055_459_9e17,
                56_874_085_4e17,
                48_877_133_9e17,
                41_424_035_8e17,
                34_713_792_6e17,
                28_826_635_6e17,
                23_200_193_1e17
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



