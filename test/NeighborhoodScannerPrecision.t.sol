// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {FullMath} from "../contracts/libraries/FullMath.sol";
import {FixedPoint96} from "../contracts/libraries/LiquidityAmounts.sol";

/// @dev Harness exposing internal `value0InToken1` for unit testing.
///      Also exposes the *previous* two-step implementation so precision can be compared.
contract NeighborhoodScannerHarness is NeighborhoodScanner {
    function value0InToken1Public(uint256 amount, uint160 sqrtP) external pure returns (uint256) {
        return value0InToken1(amount, sqrtP);
    }

    /// @dev Previous (pre-fix) two-step implementation, for precision comparison only.
    ///      Kept as a reference in tests so the improvement vs the two-step form is measurable.
    function value0InToken1LegacyTwoStep(uint256 amount, uint160 sqrtP) external pure returns (uint256) {
        if (amount == 0) return 0;
        uint256 intermediate = FullMath.mulDiv(amount, sqrtP, FixedPoint96.Q96);
        return FullMath.mulDiv(intermediate, sqrtP, FixedPoint96.Q96);
    }
}

/// @dev Unit tests for the C4R 2026-01 L-08 fix: `NeighborhoodScanner.value0InToken1`
///      switched from two-step mulDiv to Uniswap OracleLibrary single-step mulDiv to
///      eliminate cumulative rounding error.
///      Run: forge test --mc NeighborhoodScannerPrecision -vvv
contract NeighborhoodScannerPrecision is Test {
    NeighborhoodScannerHarness internal h;

    function setUp() public {
        h = new NeighborhoodScannerHarness();
    }

    // --------------------------------------------------------------
    // Exact-value checks — sqrtP = 2^k is rounding-free for both paths
    // --------------------------------------------------------------

    /// @dev sqrtP = 2^96 ⇒ price = 1 ⇒ amount maps 1:1 into token1.
    function test_priceEqualsOne() public view {
        uint160 sqrtP = uint160(uint256(1) << 96);
        assertEq(h.value0InToken1Public(1e18, sqrtP), 1e18);
    }

    /// @dev sqrtP = 2^97 ⇒ price = 4 ⇒ amount·4.
    function test_priceFour() public view {
        uint160 sqrtP = uint160(uint256(1) << 97);
        assertEq(h.value0InToken1Public(1e18, sqrtP), 4e18);
    }

    /// @dev sqrtP = 2^95 ⇒ price = 0.25 ⇒ amount/4.
    function test_priceQuarter() public view {
        uint160 sqrtP = uint160(uint256(1) << 95);
        assertEq(h.value0InToken1Public(1e18, sqrtP), 0.25e18);
    }

    /// @dev zero amount must return zero (guarded early path).
    function test_zeroAmount() public view {
        assertEq(h.value0InToken1Public(0, uint160(uint256(1) << 96)), 0);
    }

    // --------------------------------------------------------------
    // Precision regression vs the pre-fix two-step formulation (L-08)
    // --------------------------------------------------------------

    /// @dev For non-power-of-two sqrtP the old path accumulates ≥ 1 wei rounding error per
    ///      mulDiv stage. The new single-step path trucates only once, so `new ≥ old` for
    ///      all inputs where both paths return a non-trivial result, with `new − old`
    ///      strictly positive for inputs crafted to expose the error.
    function test_newPathNotWorseThanOld_fuzzSmall() public view {
        // Deterministic, representative non-round sqrtP and amount.
        uint256 amount = 123_456_789_012_345_678; // ~0.123 ether, non-round
        uint160 sqrtP = uint160(uint256(1) << 96) + 12_345_678_901_234_567; // Q96 + non-round delta

        uint256 nw = h.value0InToken1Public(amount, sqrtP);
        uint256 lg = h.value0InToken1LegacyTwoStep(amount, sqrtP);

        // New path rounds only once → result is ≥ the twice-rounded legacy path.
        assertGe(nw, lg, "new single-step must not under-count vs legacy two-step");
    }

    /// @dev Demonstrates the precision gap is real for a hand-picked input. The new and old
    ///      paths do not need to always differ — but this specific (amount, sqrtP) triggers
    ///      a truncation in the legacy intermediate step that the single-step avoids.
    function test_newPathStrictlyBetterThanOld_craftedInput() public view {
        // Craft sqrtP so that (amount * sqrtP) % Q96 is small but non-zero, making the
        // legacy intermediate lose a wei that the single-step preserves.
        uint160 sqrtP = uint160(uint256(1) << 96) + 1; // Q96 + 1
        // amount chosen so that (amount * sqrtP / Q96) truncates a visible remainder:
        uint256 amount = (uint256(1) << 96) - 1; // just below Q96

        uint256 nw = h.value0InToken1Public(amount, sqrtP);
        uint256 lg = h.value0InToken1LegacyTwoStep(amount, sqrtP);

        // Single-step is strictly larger (lost-wei direction) here.
        assertGt(nw, lg, "single-step should beat two-step for this crafted input");
    }

    // --------------------------------------------------------------
    // Path-switch coverage: single-step vs fallback two-step at sqrtP > 2^128
    // --------------------------------------------------------------

    /// @dev sqrtP exactly at the single-step limit (2^128 − 1) uses ratioX192 = sqrtP²
    ///      (no overflow since sqrtP ≤ 2^128). Asserts the path returns a consistent answer.
    function test_singleStepPath_atLimit() public view {
        uint160 sqrtP = uint160(type(uint128).max); // 2^128 − 1 — largest single-step input
        uint256 r = h.value0InToken1Public(1 ether, sqrtP);
        // With sqrtP ≈ 2^128, price ≈ 2^64, so 1 ether * 2^64 is a very large number.
        assertGt(r, 1 ether, "non-zero amount at very high price must produce a larger result");
    }

    /// @dev sqrtP just above 2^128 engages the two-step fallback (avoids uint256 overflow
    ///      in sqrtP²). Asserts both paths remain consistent by monotonicity: larger sqrtP
    ///      → larger output for the same amount.
    function test_twoStepFallbackPath_engages() public view {
        uint160 sqrtP_lo = uint160(type(uint128).max); // single-step
        uint160 sqrtP_hi = uint160(uint256(type(uint128).max) + 1); // fallback

        uint256 rLo = h.value0InToken1Public(1 ether, sqrtP_lo);
        uint256 rHi = h.value0InToken1Public(1 ether, sqrtP_hi);

        assertGe(rHi, rLo, "monotonic in sqrtP across the single/two-step boundary");
    }

    /// @dev sqrtP near Uniswap V3's MAX_SQRT_RATIO (≈ 2^160) must still produce a finite
    ///      answer via the fallback path without reverting.
    function test_twoStepFallbackPath_nearMaxSqrtRatio() public view {
        // MAX_SQRT_RATIO from TickMath = 1461446703485210103287273052203988822378723970342 (~2^160 − 1)
        uint160 sqrtP = 1461446703485210103287273052203988822378723970342;
        uint256 r = h.value0InToken1Public(1, sqrtP);
        assertGt(r, 0, "must not truncate to zero at near-max sqrtP for amount=1");
    }
}
