// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerCore, NotEnoughHistory, Overflow, ZeroValue} from "../contracts/pol/LiquidityManagerCore.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

// ---------------------------------------------------------------------------
// Mock contracts
// ---------------------------------------------------------------------------

/// @dev Minimal mock Uniswap V3 pool with configurable slot0 and observations.
contract MockPool {
    uint160 public sqrtPriceX96;
    uint16 public observationIndex;
    uint32 public oldestObservationTimestamp;
    uint16 public cardinality = 1;

    // observe() returns these two cumulative ticks for secondsAgos=[SECONDS_AGO, 0]
    int56 public tickCumOld;
    int56 public tickCumNow;
    bool public observeReverts;

    function setSlot0(uint160 _sqrtPriceX96, uint16 _observationIndex) external {
        sqrtPriceX96 = _sqrtPriceX96;
        observationIndex = _observationIndex;
    }

    function setCardinality(uint16 _cardinality) external {
        cardinality = _cardinality;
    }

    function setOldestTimestamp(uint32 ts) external {
        oldestObservationTimestamp = ts;
    }

    function setObserveData(int56 _old, int56 _now, bool _reverts) external {
        tickCumOld = _old;
        tickCumNow = _now;
        observeReverts = _reverts;
    }

    /// @dev Matches IUniswapV3.slot0() ABI (7 return values in the standard pool).
    function slot0()
        external
        view
        returns (
            uint160 _sqrtPriceX96,
            int24 tick,
            uint16 _observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        _sqrtPriceX96 = sqrtPriceX96;
        tick = 0;
        _observationIndex = observationIndex;
        observationCardinality = cardinality;
        observationCardinalityNext = cardinality;
        feeProtocol = 0;
        unlocked = true;
    }

    /// @dev Matches IUniswapV3.observations() for a given index.
    function observations(uint256 /*index*/)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        blockTimestamp = oldestObservationTimestamp;
        tickCumulative = 0;
        secondsPerLiquidityCumulativeX128 = 0;
        initialized = true;
    }

    /// @dev Matches IUniswapV3.observe().
    /// Returns [tickCumOld, tickCumNow] for secondsAgos = [SECONDS_AGO, 0].
    function observe(uint32[] calldata /*secondsAgos*/)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        if (observeReverts) {
            revert("OLD");
        }
        tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumOld;
        tickCumulatives[1] = tickCumNow;
        secondsPerLiquidityCumulativeX128s = new uint160[](2);
    }
}

/// @dev Minimal mock for positionManagerV3 — only factory() call used in constructor.
contract MockPositionManager {
    address public factoryAddr;

    constructor(address _factory) {
        factoryAddr = _factory;
    }

    function factory() external view returns (address) {
        return factoryAddr;
    }
}

/// @dev Concrete implementation of the abstract LiquidityManagerCore for testing.
///      All abstract virtuals are stubbed — only checkPoolAndGetCenterPrice is under test.
contract TestLiquidityManagerCore is LiquidityManagerCore {
    constructor(address _positionManager, address _neighborhoodScanner)
        LiquidityManagerCore(
            address(1), // _olas
            address(2), // _treasury
            _positionManager,
            _neighborhoodScanner,
            1 // _observationCardinality
        )
    {}

    // Stub virtuals — not exercised in these unit tests
    function _burn(uint256) internal override {}

    function _checkTokensAndRemoveLiquidityV2(address[] memory, bytes32)
        internal
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
    }

    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing)
        internal
        pure
        override
        returns (int24)
    {
        return feeTierOrTickSpacing; // identity stub
    }

    function _getV3Pool(address[] memory, int24) internal pure override returns (address) {
        return address(0);
    }

    function _mintV3(
        address[] memory,
        uint256[] memory,
        uint256[] memory,
        int24[] memory,
        int24,
        uint160
    ) internal override returns (uint256, uint128, uint256[] memory) {
        uint256[] memory a = new uint256[](2);
        return (0, 0, a);
    }

    /// @dev Exposes the internal soft-priced exit helper for unit testing.
    function exposedGetExitSqrtPrice(address pool) external view returns (uint160) {
        return _getExitSqrtPrice(pool);
    }
}

// ---------------------------------------------------------------------------
// Helper — computes a tick-cumulative pair that produces `targetTick` as TWAP
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Test contract
// ---------------------------------------------------------------------------

/// @dev Unit tests for the LiquidityManagerCore price guard (checkPoolAndGetCenterPrice), fail-closed.
///      Covers T1 (both triggers revert), T13 (mature-pool deviation still reverts), and the healthy
///      within-deviation path that returns the TWAP sqrt price.
///      Run: forge test --mc LiquidityManagerCorePriceGuard -vvv
contract LiquidityManagerCorePriceGuardTest is Test {
    uint32 internal constant SECONDS_AGO = 1800;
    uint256 internal constant MAX_ALLOWED_DEVIATION = 1e17; // 10% in 1e18

    MockPool internal pool;
    TestLiquidityManagerCore internal lm;

    function setUp() public {
        // Deploy mock position manager pointing to a dummy factory
        MockPositionManager positionManager = new MockPositionManager(address(0xF));

        // Deploy mock neighborhood scanner (address non-zero; not called in these tests)
        address scanner = address(new MockPool()); // reuse any non-zero contract

        lm = new TestLiquidityManagerCore(address(positionManager), scanner);
        pool = new MockPool();

        // Start at a known timestamp so arithmetic is deterministic
        vm.warp(10_000);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// @dev Configures pool so that the oldest observation is recent enough to trigger
    ///      TWAP comparison (oldestTimestamp + SECONDS_AGO >= block.timestamp).
    ///      Sets both instant sqrtPriceX96 (slot0) and the TWAP tick cumulatives
    ///      that produce `twapTick`.
    function _configurePoolWithHistory(
        uint160 instantSqrtPriceX96,
        int24 twapTick
    ) internal {
        // oldestTimestamp must satisfy: oldestTimestamp + SECONDS_AGO >= block.timestamp
        // i.e. oldestTimestamp >= block.timestamp - SECONDS_AGO
        // Use block.timestamp exactly (always satisfies the condition)
        pool.setSlot0(instantSqrtPriceX96, 0);
        pool.setOldestTimestamp(uint32(block.timestamp));

        // Produce tick cumulatives whose delta / SECONDS_AGO == twapTick
        // tickCumNow - tickCumOld = twapTick * SECONDS_AGO
        int56 delta = int56(twapTick) * int56(uint56(SECONDS_AGO));
        pool.setObserveData(0, delta, false);
    }

    // -----------------------------------------------------------------------
    // test_checkPoolAndGetCenterPrice_revertsOnManipulation (#17/#18)
    // -----------------------------------------------------------------------

    /// @dev Instant price is manipulated >10% above TWAP → must revert Overflow.
    function test_checkPoolAndGetCenterPrice_revertsOnManipulation() public {
        // TWAP tick = 0 → TWAP sqrtPriceX96 = Q64.96 for price = 1 (tick 0)
        int24 twapTick = 0;
        uint160 twapSqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);

        // Instant tick = 1000 → a price noticeably above TWAP (well over 10%)
        int24 instantTick = 1000;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        _configurePoolWithHistory(instantSqrtPriceX96, twapTick);

        // Calculate expected deviation for the error selector match
        uint256 twapPrice = mulDiv(uint256(twapSqrtPriceX96), uint256(twapSqrtPriceX96), (1 << 64));
        uint256 instantPrice = mulDiv(uint256(instantSqrtPriceX96), uint256(instantSqrtPriceX96), (1 << 64));
        uint256 deviation = mulDiv((instantPrice - twapPrice), 1e18, twapPrice);

        // Deviation must exceed MAX_ALLOWED_DEVIATION for the test premise to hold
        assertGt(deviation, MAX_ALLOWED_DEVIATION, "test setup: deviation must exceed 10%");

        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, deviation, MAX_ALLOWED_DEVIATION));
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // -----------------------------------------------------------------------
    // test_checkPoolAndGetCenterPrice_withinDeviation (#17/#18)
    // -----------------------------------------------------------------------

    /// @dev Instant price is within deviation → no revert, returns TWAP sqrt price.
    function test_checkPoolAndGetCenterPrice_withinDeviation() public {
        int24 twapTick = 0;
        uint160 twapSqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);

        // Instant tick = 3 ticks away from TWAP → tiny deviation, well within 10%
        int24 instantTick = 3;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        _configurePoolWithHistory(instantSqrtPriceX96, twapTick);

        uint160 result = lm.checkPoolAndGetCenterPrice(address(pool));

        // Must return TWAP-derived sqrt price (not instant)
        assertEq(result, twapSqrtPriceX96, "should return TWAP sqrt price, not instant");
        assertFalse(result == instantSqrtPriceX96, "must not return raw slot0 price");
    }

    // -----------------------------------------------------------------------
    // T1 (inactive-pool trigger): fail closed instead of returning slot0
    // -----------------------------------------------------------------------

    /// @dev Latest observation older than SECONDS_AGO (inactive pool) → the guard used to return the
    ///      raw slot0; after the fix it fails closed with NotEnoughHistory rather than pricing against
    ///      the manipulable slot0.
    function test_checkPoolAndGetCenterPrice_revertsWhenInactive() public {
        int24 instantTick = 500;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        pool.setSlot0(instantSqrtPriceX96, 0);
        // latest observation is in the far past — (latestObsTimestamp + SECONDS_AGO < block.timestamp)
        // is TRUE → inactive-pool trigger → must revert
        pool.setOldestTimestamp(1); // timestamp = 1, far before block.timestamp = 10_000

        vm.expectRevert(abi.encodeWithSelector(NotEnoughHistory.selector, address(pool)));
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // -----------------------------------------------------------------------
    // test_checkPoolAndGetCenterPrice_revertsZeroSlot0
    // -----------------------------------------------------------------------

    /// @dev slot0 sqrtPriceX96 = 0 → revert ZeroValue().
    function test_checkPoolAndGetCenterPrice_revertsZeroSlot0() public {
        pool.setSlot0(0, 0);
        pool.setOldestTimestamp(1);

        vm.expectRevert(ZeroValue.selector);
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // -----------------------------------------------------------------------
    // T1 (new-pool trigger): fail closed when observe() cannot produce a TWAP
    // -----------------------------------------------------------------------

    /// @dev observe() reverts on a matured pool (cardinality >= 2) that claims history → no verifiable
    ///      TWAP → fail closed with NotEnoughHistory (never returns slot0).
    function test_checkPoolAndGetCenterPrice_revertsOnObserveRevert() public {
        int24 instantTick = 100;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        pool.setSlot0(instantSqrtPriceX96, 0);
        pool.setCardinality(60);                    // active pool claiming rich history
        // Recent enough that the inactive-pool early-return does NOT fire; the function commits to the
        // TWAP branch and must enforce it.
        pool.setOldestTimestamp(uint32(block.timestamp));
        // Make observe() revert → staticcall returns success=false → revert expected.
        pool.setObserveData(0, 0, true);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughHistory.selector, address(pool)));
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    /// @dev observe() reverts on a freshly-created pool (cardinality == 1, no history) → the guard used
    ///      to fall back to raw slot0 (the fail-open the migration exploited); after the fix it fails
    ///      closed with NotEnoughHistory. The legitimate first seed is instead enabled by pre-warming
    ///      the pool per the migration runbook (covered in the fork suite).
    function test_checkPoolAndGetCenterPrice_revertsOnObserveRevertWithCardinalityOne() public {
        int24 instantTick = 100;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        pool.setSlot0(instantSqrtPriceX96, 0);
        pool.setCardinality(1);                     // fresh pool, no history recorded yet
        pool.setOldestTimestamp(uint32(block.timestamp));
        pool.setObserveData(0, 0, true);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughHistory.selector, address(pool)));
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // -----------------------------------------------------------------------
    // _getExitSqrtPrice — soft-priced exit floor (decreaseLiquidity)
    // Unlike checkPoolAndGetCenterPrice this fails OPEN on an unverifiable pool (returns slot0) so an
    // exit is always possible, but still fail-CLOSED on a mature pool whose slot0 deviates > 10%.
    // -----------------------------------------------------------------------

    /// @dev Inactive pool (latest observation older than SECONDS_AGO): returns raw slot0 (fail-open), so
    ///      a withdrawal is never bricked on a quiet pool. Contrast with checkPoolAndGetCenterPrice which
    ///      reverts here.
    function test_getExitSqrtPrice_inactivePool_returnsSlot0() public {
        int24 instantTick = 500;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        pool.setSlot0(instantSqrtPriceX96, 0);
        pool.setOldestTimestamp(1); // far past -> inactive trigger

        uint160 result = lm.exposedGetExitSqrtPrice(address(pool));
        assertEq(result, instantSqrtPriceX96, "inactive pool must fall back to slot0 for the exit");
    }

    /// @dev Fresh pool (cardinality == 1, observe reverts): returns raw slot0 (fail-open).
    function test_getExitSqrtPrice_freshPool_returnsSlot0() public {
        int24 instantTick = 100;
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(instantTick);

        pool.setSlot0(instantSqrtPriceX96, 0);
        pool.setCardinality(1);
        pool.setOldestTimestamp(uint32(block.timestamp)); // not inactive -> goes to observe
        pool.setObserveData(0, 0, true); // observe reverts

        uint160 result = lm.exposedGetExitSqrtPrice(address(pool));
        assertEq(result, instantSqrtPriceX96, "fresh pool must fall back to slot0 for the exit");
    }

    /// @dev Mature pool, slot0 within deviation: returns the gated slot0 price (NOT the TWAP), so amountMin
    ///      is computed at the exact price the position manager withdraws at (no PSC / "too little" edge).
    function test_getExitSqrtPrice_matureWithinDeviation_returnsSlot0() public {
        int24 twapTick = 0;
        uint160 twapSqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(3); // tiny deviation

        _configurePoolWithHistory(instantSqrtPriceX96, twapTick);
        pool.setCardinality(60);

        uint160 result = lm.exposedGetExitSqrtPrice(address(pool));
        assertEq(result, instantSqrtPriceX96, "mature pool must price the exit off slot0 (gated), not the TWAP");
        assertTrue(result != twapSqrtPriceX96, "must not return the TWAP sqrt price");
    }

    /// @dev Mature pool, slot0 near the deviation bound but within it (~9.4%): still passes the gate and
    ///      returns slot0. This is the case that would previously mis-price amountMin at the TWAP and could
    ///      revert the exit; now a fair exit is always satisfiable.
    function test_getExitSqrtPrice_matureNearBound_returnsSlot0() public {
        int24 twapTick = 0;
        // tick 900 -> price ~1.0942 -> ~9.4% deviation, just under MAX_ALLOWED_DEVIATION (10%)
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(900);

        _configurePoolWithHistory(instantSqrtPriceX96, twapTick);
        pool.setCardinality(60);

        uint160 result = lm.exposedGetExitSqrtPrice(address(pool));
        assertEq(result, instantSqrtPriceX96, "near-bound-but-within must return slot0 without reverting");
    }

    /// @dev Mature pool, slot0 deviates > 10% from TWAP: still fail-CLOSED (reverts Overflow), so the
    ///      exit cannot be sandwiched on a mature pool.
    function test_getExitSqrtPrice_matureDeviation_reverts() public {
        int24 twapTick = 0;
        uint160 twapSqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);
        uint160 instantSqrtPriceX96 = TickMath.getSqrtRatioAtTick(1000); // > 10% off

        _configurePoolWithHistory(instantSqrtPriceX96, twapTick);
        pool.setCardinality(60);

        uint256 twapPrice = mulDiv(uint256(twapSqrtPriceX96), uint256(twapSqrtPriceX96), (1 << 64));
        uint256 instantPrice = mulDiv(uint256(instantSqrtPriceX96), uint256(instantSqrtPriceX96), (1 << 64));
        uint256 deviation = mulDiv((instantPrice - twapPrice), 1e18, twapPrice);

        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, deviation, MAX_ALLOWED_DEVIATION));
        lm.exposedGetExitSqrtPrice(address(pool));
    }
}
