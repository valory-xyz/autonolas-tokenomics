// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerUniV2UniV3} from "../contracts/pol/LiquidityManagerUniV2UniV3.sol";

/// @dev Minimal V3 pool mock. observe() drives the window harmonic mean; slot0/liquidity/tickSpacing/ticks
///      drive the current tick-aware executable-depth walk. The pool is modelled at price 1 (tick 0) with a
///      single uniform position wide enough to span the ±198-tick band (no tick boundaries inside it, so
///      liquidity stays constant across the band), and `currentLiquidity` set equal to the window mean — so the
///      two depth measures agree and the boundary tests exercise the combined check cleanly.
contract MockV3Pool {
    uint160 public splOld; // as-of SECONDS_AGO ago
    uint160 public splNow; // as-of now (>= splOld)
    uint128 public currentLiquidity;

    function setSpl(uint160 _splOld, uint160 _splNow) external {
        splOld = _splOld;
        splNow = _splNow;
    }

    function setCurrentLiquidity(uint128 l) external {
        currentLiquidity = l;
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

    function slot0()
        external
        pure
        returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool)
    {
        return (uint160(1) << 96, int24(0), 0, 0, 0, 0, false);
    }

    function tickSpacing() external pure returns (int24) {
        return 60;
    }

    function liquidity() external view returns (uint128) {
        return currentLiquidity;
    }

    // No position boundaries inside the band: liquidity is uniform across ±198 ticks.
    function ticks(int24) external pure returns (uint128 liquidityGross, int128 liquidityNet) {
        return (0, 0);
    }
}

/// @dev Slipstream-style pool mock: slot0 returns SIX fields (no feeProtocol), unlike Uniswap V3's seven.
///      Used to prove the depth check reads slot0 variant-tolerantly. Price 1 (tick 0), uniform liquidity.
contract MockSlipstreamPool {
    uint128 public currentLiquidity;

    function setCurrentLiquidity(uint128 l) external {
        currentLiquidity = l;
    }

    // Six-field slot0 (Slipstream): sqrtPriceX96, tick, observationIndex, observationCardinality,
    // observationCardinalityNext, unlocked — no uint8 feeProtocol.
    function slot0() external pure returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, bool) {
        return (uint160(1) << 96, int24(0), 0, 0, 0, false);
    }

    function tickSpacing() external pure returns (int24) {
        return 60;
    }

    function liquidity() external view returns (uint128) {
        return currentLiquidity;
    }

    function ticks(int24) external pure returns (uint128 liquidityGross, int128 liquidityNet) {
        return (0, 0);
    }
}

/// @dev Pool mock with a configurable STORED slot0 tick and per-tick liquidityNet, for exact-boundary tests
///      where the stored tick differs from the price-derived tick.
contract MockV3PoolTicks {
    uint160 internal sp;
    int24 internal storedTick;
    uint128 internal liq;
    mapping(int24 => int128) internal net;

    function set(uint160 _sp, int24 _storedTick, uint128 _liq) external {
        sp = _sp;
        storedTick = _storedTick;
        liq = _liq;
    }

    function setNet(int24 tick, int128 n) external {
        net[tick] = n;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sp, storedTick, 0, 0, 0, 0, false);
    }

    function tickSpacing() external pure returns (int24) {
        return 60;
    }

    function liquidity() external view returns (uint128) {
        return liq;
    }

    function ticks(int24 tick) external view returns (uint128 liquidityGross, int128 liquidityNet) {
        return (0, net[tick]);
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
        // Current in-range liquidity equal to the window mean, so the tick-aware executable depth agrees with
        // the band-inventory estimate for these synthetic (uniform, non-depleted) scenarios.
        pool.setCurrentLiquidity(uint128(targetL));
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

    // _checkPoolDepth requires BOTH the window estimate and the current tick-aware executable depth, so the
    // binding (smaller) of the two is the available depth. They differ by a few wei (per-segment rounding).
    function _bindingDepth() internal view returns (uint256) {
        uint256 est = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);
        uint256 exe = lm.currentExecutableDepthToken1(address(pool), SQRT_PRICE_1);
        return est < exe ? est : exe;
    }

    function test_checkPoolDepth_boundary_passAndRevert() public {
        _setSustainedLiquidity(1e18);
        uint256 depth = _bindingDepth();
        lm.setFactor(1e18); // require depth >= 1x notional (token1 terms)

        // Notional (token1 terms) just BELOW available depth -> passes. Here amount0 = 0, so notional == amount1.
        lm.checkDepth(address(pool), 0, depth - 1, SQRT_PRICE_1);

        // Notional just ABOVE available depth -> reverts InsufficientPoolDepth.
        vm.expectRevert();
        lm.checkDepth(address(pool), 0, depth + 1, SQRT_PRICE_1);
    }

    function test_checkPoolDepth_factorScalesRequirement() public {
        _setSustainedLiquidity(1e18);
        uint256 depth = _bindingDepth();

        // factor 2x: a notional equal to the full depth now fails (requires 2x depth).
        lm.setFactor(2e18);
        vm.expectRevert();
        lm.checkDepth(address(pool), 0, depth, SQRT_PRICE_1);

        // Half the notional passes at 2x factor (required = 2 * depth/2 = depth).
        lm.checkDepth(address(pool), 0, depth / 2, SQRT_PRICE_1);
    }

    // Current executable depth from the tick walk ~matches the band-inventory estimate on a uniform pool.
    function test_executableDepth_matchesEstimate_onUniformPool() public {
        _setSustainedLiquidity(1e18);
        uint256 est = lm.estimatedBandInventoryToken1(address(pool), SQRT_PRICE_1);
        uint256 exe = lm.currentExecutableDepthToken1(address(pool), SQRT_PRICE_1);
        assertApproxEqRel(exe, est, 1e12, "walked executable depth should track the estimate on a uniform pool");
    }

    // The tick walk reads slot0 variant-tolerantly: a six-field Slipstream pool does not revert on ABI decode
    // and yields the same executable depth as the seven-field Uniswap V3 pool with equal liquidity.
    function test_executableDepth_slipstreamSlot0Compatible() public {
        _setSustainedLiquidity(1e18); // sets the 7-field pool's current liquidity to 1e18
        uint256 uni = lm.currentExecutableDepthToken1(address(pool), SQRT_PRICE_1);

        MockSlipstreamPool slip = new MockSlipstreamPool();
        slip.setCurrentLiquidity(uint128(1e18));
        uint256 slipDepth = lm.currentExecutableDepthToken1(address(slip), SQRT_PRICE_1);

        assertGt(slipDepth, 0, "six-field pool must not revert and must report depth");
        assertEq(slipDepth, uni, "Slipstream (6-field) depth must equal Uniswap (7-field) depth at equal state");
    }

    // At an exact tick boundary reached by a DOWNWARD crossing, the pool stores tickNext-1 while the
    // price-derived tick is tickNext. The walk seeds from the stored tick's active liquidity, so it must use the
    // STORED tick: a derived off-by-one would include phantom liquidity above the boundary and re-apply the
    // boundary crossing going down, over-stating depth. Position [-60, 0], liquidity 1e18, price = sqrt(tick 0),
    // stored tick -1: correct depth is the [-60,0] token1 (~2.995e15), not the ~2.27e16 derived-tick result.
    function test_executableDepth_usesStoredTick_downwardBoundary() public {
        MockV3PoolTicks p = new MockV3PoolTicks();
        p.set(SQRT_PRICE_1, int24(-1), uint128(1e18));
        p.setNet(int24(-60), int128(uint128(1e18))); // lower boundary of [-60,0]
        p.setNet(int24(0), -int128(uint128(1e18))); // upper boundary of [-60,0]

        uint256 depth = lm.currentExecutableDepthToken1(address(p), SQRT_PRICE_1);
        assertApproxEqRel(depth, 2995354955910780, 1e16, "stored-tick depth should match the piecewise value");
        assertLt(depth, 1e16, "must not over-state via a price-derived off-by-one tick");
    }

    // Control: at the same price reached by an UPWARD crossing the stored tick (0) equals the derived tick.
    // Position [0, 60], liquidity 1e18: depth is the [0,60] token0 valued in token1 (~2.995e15).
    function test_executableDepth_usesStoredTick_upwardBoundary() public {
        MockV3PoolTicks p = new MockV3PoolTicks();
        p.set(SQRT_PRICE_1, int24(0), uint128(1e18));
        p.setNet(int24(0), int128(uint128(1e18))); // lower boundary of [0,60]
        p.setNet(int24(60), -int128(uint128(1e18))); // upper boundary of [0,60]

        uint256 depth = lm.currentExecutableDepthToken1(address(p), SQRT_PRICE_1);
        assertApproxEqRel(depth, 2995354955910780, 1e16, "upward-boundary depth should match the piecewise value");
    }

    // Depletion proxy: current liquidity drops while the window mean stays high -> executable check binds low.
    function test_checkPoolDepth_currentDepletionRejectedWhileWindowHigh() public {
        _setSustainedLiquidity(1e18); // window mean = 1e18, current = 1e18
        uint256 depth = _bindingDepth();
        lm.setFactor(1e18);

        // Deplete current liquidity to 1% while leaving the window mean (observe delta) unchanged.
        pool.setCurrentLiquidity(uint128(1e16));
        // Window estimate still passes a near-full-depth notional, but the current executable depth does not.
        vm.expectRevert();
        lm.checkDepth(address(pool), 0, (depth * 9) / 10, SQRT_PRICE_1);
    }
}
