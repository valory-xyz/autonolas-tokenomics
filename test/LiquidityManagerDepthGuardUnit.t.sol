// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerUniV2UniV3} from "../contracts/pol/LiquidityManagerUniV2UniV3.sol";

/// @dev Minimal V3 pool mock: only observe() is exercised by the depth views. The two
///      secondsPerLiquidityCumulativeX128 values are set directly so the window harmonic mean is controlled.
contract MockV3Pool {
    uint160 public splOld; // as-of SECONDS_AGO ago
    uint160 public splNow; // as-of now (>= splOld)

    function setSpl(uint160 _splOld, uint160 _splNow) external {
        splOld = _splOld;
        splNow = _splNow;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        // secondsAgos[0] = SECONDS_AGO (older), secondsAgos[1] = 0 (now)
        secondsPerLiquidityCumulativeX128s[0] = splOld;
        secondsPerLiquidityCumulativeX128s[1] = splNow;
    }
}

/// @dev Position-manager mock: the Core constructor reads factory() once.
contract MockPositionManager {
    function factory() external view returns (address) {
        return address(this);
    }
}

/// @dev Harness exposing the internal depth check and a direct factor setter.
contract LMHarness is LiquidityManagerUniV2UniV3 {
    constructor(address pm)
        LiquidityManagerUniV2UniV3(
            address(0xA11CE), // olas (dummy, not called by the views)
            address(0xBEEF), // treasury
            pm, // positionManagerV3 (factory() read in ctor)
            address(0xCAFE), // neighborhoodScanner
            1, // observationCardinality
            address(0xD00D) // routerV2
        )
    {}

    function setFactor(uint256 f) external {
        minDepthFactor = f;
    }

    function checkDepth(address pool, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96) external view {
        _checkPoolDepth(pool, amount0, amount1, sqrtPriceX96);
    }
}

contract LiquidityManagerDepthGuardUnit is Test {
    uint32 constant SECONDS_AGO = 1800;
    uint256 constant Q128 = 1 << 128;
    // sqrtPriceX96 for price 1 (token1/token0 == 1): 2^96.
    uint160 constant SQRT_PRICE_1 = uint160(1) << 96;

    LMHarness lm;
    MockV3Pool pool;

    function setUp() public {
        MockPositionManager pm = new MockPositionManager();
        lm = new LMHarness(address(pm));
        pool = new MockV3Pool();
    }

    /// @dev Sets the pool so its window harmonic-mean in-range liquidity equals (approximately) targetL.
    function _setSustainedLiquidity(uint256 targetL) internal {
        // delta = windowSeconds * 2^128 / L
        uint256 delta = (uint256(SECONDS_AGO) * Q128) / targetL;
        pool.setSpl(uint160(0), uint160(delta));
    }

    function test_harmonicMean_matchesFormula() public {
        _setSustainedLiquidity(1e18);
        uint128 hm = lm.windowHarmonicMeanLiquidity(address(pool));
        // Reconstruct expected from the same integer path.
        uint256 delta = (uint256(SECONDS_AGO) * Q128) / 1e18;
        uint256 expected = (uint256(SECONDS_AGO) * Q128) / delta;
        assertEq(uint256(hm), expected, "harmonic mean != formula");
        // Within rounding of the target.
        assertApproxEqRel(uint256(hm), 1e18, 1e12, "harmonic mean not ~targetL");
    }

    function test_harmonicMean_zeroDelta_failsClosed() public {
        pool.setSpl(uint160(0), uint160(0)); // delta == 0
        assertEq(uint256(lm.windowHarmonicMeanLiquidity(address(pool))), 0, "zero delta should read as 0 depth");
    }

    /// @dev The secondsPerLiquidity accumulator is a uint160 that wraps; the delta must be taken modulo 2^160.
    ///      Here the "older" value is near the top of the range and the "now" value is small, so a checked
    ///      subtraction would underflow/revert — the unchecked modular delta must recover the true elapsed value.
    function test_harmonicMean_handlesAccumulatorWrap() public {
        uint256 targetL = 1e18;
        uint256 delta = (uint256(SECONDS_AGO) * Q128) / targetL;
        uint160 splOld = type(uint160).max - 100; // near the top of the range
        // now = old + delta (mod 2^160): wraps past the max.
        uint160 splNow;
        unchecked {
            splNow = splOld + uint160(delta);
        }
        assertLt(splNow, splOld, "test setup must actually wrap the accumulator");
        pool.setSpl(splOld, splNow);

        uint128 hm = lm.windowHarmonicMeanLiquidity(address(pool));
        // Recovers the same value as the non-wrapping case (no revert).
        uint256 expected = (uint256(SECONDS_AGO) * Q128) / delta;
        assertEq(uint256(hm), expected, "wrapped delta must equal the intended delta");
        assertApproxEqRel(uint256(hm), targetL, 1e12, "wrapped harmonic mean not ~targetL");
    }

    /// @dev JIT resistance: low liquidity for 1788s + a huge spike for the last 12s barely lifts the window mean.
    function test_harmonicMean_jitResistant() public {
        uint256 lowL = 1e18;
        uint256 spikeL = 1_000_000e18; // 1e6x
        // delta = 1788/lowL + 12/spikeL, each scaled by 2^128.
        uint256 delta = (uint256(1788) * Q128) / lowL + (uint256(12) * Q128) / spikeL;
        pool.setSpl(uint160(0), uint160(delta));

        uint256 hm = uint256(lm.windowHarmonicMeanLiquidity(address(pool)));
        // The window mean stays within ~1% of the sustained low liquidity, nowhere near the spike.
        assertApproxEqRel(hm, lowL, 1e16, "JIT spike moved the window mean too much"); // 1% tolerance
        assertLt(hm, lowL * 2, "window mean must stay far below the spike");
    }

    function test_depthNotional_scalesLinearlyWithLiquidity() public {
        _setSustainedLiquidity(1e18);
        uint256 d1 = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);
        _setSustainedLiquidity(2e18);
        uint256 d2 = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);
        assertGt(d1, 0, "depth must be positive");
        assertApproxEqRel(d2, d1 * 2, 1e12, "depth should roughly double with liquidity");
    }

    function test_checkPoolDepth_disabledWhenFactorZero() public {
        lm.setFactor(0);
        _setSustainedLiquidity(1e18);
        // Even an enormous notional passes when the check is inactive.
        lm.checkDepth(address(pool), type(uint128).max, type(uint128).max, SQRT_PRICE_1);
    }

    function test_checkPoolDepth_boundary_passAndRevert() public {
        _setSustainedLiquidity(1e18);
        uint256 depth = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);
        lm.setFactor(1e18); // require depth >= 1x notional (token1 terms)

        // Notional (token1 terms) just BELOW available depth -> passes. Here amount0 = 0, so notional == amount1.
        lm.checkDepth(address(pool), 0, depth - 1, SQRT_PRICE_1);

        // Notional just ABOVE available depth -> reverts InsufficientPoolDepth.
        vm.expectRevert();
        lm.checkDepth(address(pool), 0, depth + 1, SQRT_PRICE_1);
    }

    function test_checkPoolDepth_factorScalesRequirement() public {
        _setSustainedLiquidity(1e18);
        uint256 depth = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);

        // factor 2x: a notional equal to the full depth now fails (requires 2x depth).
        lm.setFactor(2e18);
        vm.expectRevert();
        lm.checkDepth(address(pool), 0, depth, SQRT_PRICE_1);

        // Half the notional passes at 2x factor (required = 2 * depth/2 = depth).
        lm.checkDepth(address(pool), 0, depth / 2, SQRT_PRICE_1);
    }
}
