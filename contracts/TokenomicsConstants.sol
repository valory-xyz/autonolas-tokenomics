// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title TokenomicsConstants - Smart contract with tokenomics constants
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract TokenomicsConstants {
    // Tokenomics version number
    string public constant VERSION = "1.3.0";
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
                635_573_107e18,
                661_590_930e18,
                688_389_288e18,
                715_991_597e18,
                744_421_975e18,
                773_705_264e18,
                803_867_052e18
            ];
            supplyCap = supplyCaps[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            // This number must follow the actual supply cap after 10 years of inflation
            supplyCap = 761_726_593e18;
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
                25_260_023e18,
                26_017_823e18,
                26_798_358e18,
                27_602_309e18,
                28_430_378e18,
                29_283_289e18,
                30_161_788e18
            ];
            inflationAmount = inflationAmounts[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            // This number must follow the actual supply cap after 10 years of inflation
            uint256 supplyCap = 761_726_593e18;
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

    /// @dev Gets actual inflation cap for a specific year.
    /// @param numYears Number of years passed from the launch date.
    /// @return supplyCap Supply cap.
    function getActualSupplyCapForYear(uint256 numYears) public pure returns (uint256 supplyCap) {
        // For the first 10 years the supply caps are pre-defined
        if (numYears < 10) {
            uint96[10] memory supplyCaps = [
                526_500_000e18,
                543_648_331e18,
                568_172_625e18,
                593_432_648e18,
                619_450_471e18,
                646_248_829e18,
                673_851_138e18,
                702_281_516e18,
                731_564_805e18,
                761_726_593e18
            ];
            supplyCap = supplyCaps[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            supplyCap = 761_726_593e18;
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

    /// @dev Gets actual inflation amount for a specific year.
    /// @param numYears Number of years passed from the launch date.
    /// @return inflationAmount Inflation limit amount.
    function getActualInflationForYear(uint256 numYears) public pure returns (uint256 inflationAmount) {
        // For the first 10 years the inflation caps are pre-defined as differences between next year cap and current year one
        if (numYears < 10) {
            // Initial OLAS allocation is 526_500_000_0e17
            uint88[10] memory inflationAmounts = [
                0,
                17_148_331e18,
                24_524_294e18,
                25_260_023e18,
                26_017_823e18,
                26_798_358e18,
                27_602_309e18,
                28_430_378e18,
                29_283_289e18,
                30_161_788e18
            ];
            inflationAmount = inflationAmounts[numYears];
        } else {
            // Number of years after ten years have passed (including ongoing ones)
            numYears -= 9;
            // Max cap for the first 10 years
            uint256 supplyCap = 761_726_593e18;
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
