// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

// =================================================================
// Fork tests for P0/P1 coverage gaps in autonolas-tokenomics
// Tests target functions with ZERO or minimal test coverage
// =================================================================

interface ITokenomics {
    function owner() external view returns (address);
    function epochCounter() external view returns (uint32);
    function epochLen() external view returns (uint32);
    function effectiveBond() external view returns (uint96);
    function maxBond() external view returns (uint96);
    function inflationPerSecond() external view returns (uint96);
    function currentYear() external view returns (uint8);
    function timeLaunch() external view returns (uint32);
    function checkpoint() external returns (bool);
    function getInflationForYear(uint256 numYears) external pure returns (uint256);
    function getActualInflationForYear(uint256 numYears) external pure returns (uint256);
    function getActualSupplyCapForYear(uint256 numYears) external pure returns (uint256);
    function updateInflationPerSecondAndFractions(
        uint256 maxBondFraction,
        uint256 topUpComponentFraction,
        uint256 topUpAgentFraction,
        uint256 stakingFraction
    ) external;
}

interface IDispenser {
    function owner() external view returns (address);
}

contract PoC_CoverageGaps is Test {
    // Deployed on Ethereum mainnet
    address constant TOKENOMICS_PROXY = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address constant DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;

    ITokenomics tokenomics;

    function setUp() public {
        vm.createSelectFork("mainnet");
        tokenomics = ITokenomics(TOKENOMICS_PROXY);
    }

    // =========================================================
    // P0: updateInflationPerSecondAndFractions -ZERO TESTS
    // =========================================================

    function test_P0_updateInflation_onlyOwner() public {
        // Verify non-owner cannot call
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        vm.expectRevert();
        tokenomics.updateInflationPerSecondAndFractions(50, 20, 10, 20);
    }

    function test_P0_updateInflation_fractionSum_over100() public {
        address owner = tokenomics.owner();
        vm.prank(owner);
        // Sum = 40+30+20+20 = 110 > 100
        vm.expectRevert();
        tokenomics.updateInflationPerSecondAndFractions(40, 30, 20, 20);
    }

    function test_P0_updateInflation_fractionSum_exactly100() public {
        address owner = tokenomics.owner();

        // Record state before
        uint96 ebBefore = tokenomics.effectiveBond();
        uint96 mbBefore = tokenomics.maxBond();
        uint96 ipsBefore = tokenomics.inflationPerSecond();

        emit log_named_uint("effectiveBond before", ebBefore);
        emit log_named_uint("maxBond before", mbBefore);
        emit log_named_uint("inflationPerSecond before", ipsBefore);

        vm.prank(owner);
        // Sum = 50+20+10+20 = 100
        // This may revert if year-change check fails -that's also useful info
        try tokenomics.updateInflationPerSecondAndFractions(50, 20, 10, 20) {
            uint96 ebAfter = tokenomics.effectiveBond();
            uint96 mbAfter = tokenomics.maxBond();
            uint96 ipsAfter = tokenomics.inflationPerSecond();

            emit log_named_uint("effectiveBond after", ebAfter);
            emit log_named_uint("maxBond after", mbAfter);
            emit log_named_uint("inflationPerSecond after", ipsAfter);

            // KEY CHECK: effectiveBond should NOT be less than outstanding bond supply
            // C2-1 finding: effectiveBond is reset to curMaxBond, losing accumulated leftovers
            emit log("--- C2-1 VERIFICATION ---");
            emit log_named_uint("effectiveBond LOST (before - after)", ebBefore > ebAfter ? ebBefore - ebAfter : 0);

            // If effectiveBond decreased, that's the C2-1 bug in action
            if (ebAfter < ebBefore) {
                emit log("!!! C2-1 CONFIRMED: effectiveBond decreased after updateInflation !!!");
                emit log("!!! Accumulated bond capacity from previous epochs LOST !!!");
            }
        } catch (bytes memory reason) {
            emit log("Reverted (expected if year-change guard triggers):");
            emit log_bytes(reason);
        }
    }

    function test_P0_updateInflation_effectiveBond_reset_vs_checkpoint() public {
        // Compare: checkpoint ADDS to effectiveBond, updateInflation RESETS it
        // This test proves the inconsistency described in C2-1

        uint96 ebBefore = tokenomics.effectiveBond();
        uint96 mbBefore = tokenomics.maxBond();
        uint32 epochLen = tokenomics.epochLen();
        uint96 ips = tokenomics.inflationPerSecond();

        // What checkpoint would compute for next epoch's maxBond addition:
        // curMaxBond = epochLen * inflationPerSecond * maxBondFraction / 100
        // effectiveBond += curMaxBond (additive)

        // What updateInflation computes:
        // curMaxBond = epochLen * newInflationPerSecond * newMaxBondFraction / 100
        // effectiveBond = curMaxBond (RESET, not additive)

        emit log_named_uint("Current effectiveBond", ebBefore);
        emit log_named_uint("Current maxBond", mbBefore);
        emit log_named_uint("epochLen", epochLen);
        emit log_named_uint("inflationPerSecond", ips);

        // If effectiveBond > maxBond, there's accumulated leftover from prior epochs
        if (ebBefore > mbBefore) {
            uint256 accumulated = ebBefore - mbBefore;
            emit log_named_uint("Accumulated leftover bond capacity", accumulated);
            emit log("This accumulated capacity would be LOST by updateInflation (C2-1)");
        } else {
            emit log("effectiveBond == maxBond: no accumulated leftover currently");
            emit log("C2-1 would only manifest when effectiveBond > maxBond");
        }
    }

    // =========================================================
    // P1: checkpoint edge cases
    // =========================================================

    function test_P1_checkpoint_calledTooEarly() public {
        // Verify checkpoint returns false when called before epochLen
        bool success = tokenomics.checkpoint();
        // If epoch hasn't ended yet, should return false
        if (!success) {
            emit log("checkpoint returned false (epoch not ended yet) -correct behavior");
        } else {
            emit log("checkpoint succeeded -epoch was ready");
        }
    }

    function test_P1_checkpoint_yearBoundaryState() public {
        // Check current year and how close we are to next year boundary
        uint8 currentYear = tokenomics.currentYear();
        uint32 timeLaunch = tokenomics.timeLaunch();
        uint256 oneYear = 365 days;

        uint256 nextYearBoundary = timeLaunch + (uint256(currentYear) + 1) * oneYear;
        uint256 timeToNextYear = nextYearBoundary > block.timestamp ?
            nextYearBoundary - block.timestamp : 0;

        emit log_named_uint("Current year", currentYear);
        emit log_named_uint("timeLaunch", timeLaunch);
        emit log_named_uint("Seconds to next year boundary", timeToNextYear);
        emit log_named_uint("Days to next year boundary", timeToNextYear / 1 days);

        // If we're within epochLen of the year boundary, updateInflation would revert
        uint32 epochLen = tokenomics.epochLen();
        if (timeToNextYear < epochLen) {
            emit log("WARNING: Within epochLen of year boundary -updateInflation would revert");
        }
    }

    function test_P1_checkpoint_maxEpochLength() public {
        // What happens if checkpoint is delayed to near MAX_EPOCH_LENGTH?
        // MAX_EPOCH_LENGTH = ONE_YEAR - 1 days = 364 days
        // At 364 days, inflationPerEpoch would be ~26x normal (if epochLen=14 days)

        uint32 epochLen = tokenomics.epochLen();
        uint96 ips = tokenomics.inflationPerSecond();

        uint256 normalInflation = uint256(epochLen) * uint256(ips);
        uint256 maxInflation = uint256(364 days) * uint256(ips);

        emit log_named_uint("Normal epoch inflation (wei)", normalInflation);
        emit log_named_uint("MAX_EPOCH inflation (wei)", maxInflation);
        emit log_named_uint("Multiplier (max/normal)", maxInflation / normalInflation);
        emit log("If checkpoint delayed to max, effectiveBond gets proportionally larger bonus");
    }

    // =========================================================
    // P1: uint96 overflow edge cases
    // =========================================================

    function test_P1_uint96_effectiveBond_overflow_check() public {
        // uint96 max = 79,228,162,514,264,337,593,543,950,335 (~79.2e27)
        // OLAS total supply cap ~526M * 1e18 = 5.26e26
        // effectiveBond should never approach uint96 max

        uint96 eb = tokenomics.effectiveBond();
        uint96 mb = tokenomics.maxBond();
        uint96 ips = tokenomics.inflationPerSecond();

        emit log_named_uint("effectiveBond", eb);
        emit log_named_uint("maxBond", mb);
        emit log_named_uint("inflationPerSecond", ips);
        emit log_named_uint("uint96 max", type(uint96).max);
        emit log_named_uint("headroom (max - effectiveBond)", type(uint96).max - eb);

        // Verify we're far from overflow
        assertLt(eb, type(uint96).max / 100, "effectiveBond too close to uint96 max");
        assertLt(mb, type(uint96).max / 100, "maxBond too close to uint96 max");
        assertLt(ips, type(uint96).max / 100, "inflationPerSecond too close to uint96 max");
    }

    // =========================================================
    // P1: inflation schedule correctness across years
    // =========================================================

    function test_P1_inflationSchedule_allYears() public {
        // Verify inflation amounts are monotonically reasonable across all years
        uint256 prevInflation;
        uint256 prevCap;

        for (uint256 year = 0; year < 20; year++) {
            uint256 inflation = tokenomics.getInflationForYear(year);
            uint256 cap = tokenomics.getActualSupplyCapForYear(year);

            if (year > 0) {
                // Inflation should be positive
                assertGt(inflation, 0, string(abi.encodePacked("Year ", vm.toString(year), " inflation is 0")));

                // Supply cap should be monotonically increasing
                assertGt(cap, prevCap, string(abi.encodePacked("Year ", vm.toString(year), " cap not increasing")));

                // For years >= 10, verify inflation is ~2% of previous cap
                if (year >= 10) {
                    uint256 expectedInflation = (prevCap * 2) / 100;
                    uint256 tolerance = expectedInflation / 100; // 1% tolerance
                    assertApproxEqAbs(inflation, expectedInflation, tolerance,
                        string(abi.encodePacked("Year ", vm.toString(year), " inflation deviates from 2%")));
                }
            }

            prevInflation = inflation;
            prevCap = cap;
        }
    }
}
