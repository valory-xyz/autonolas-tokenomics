// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// =============================================================================
// price-guard fail-open — PERMANENT auditor-certified regression suite (Rule 52)
// -----------------------------------------------------------------------------
// WHO OWNS THIS FILE: the auditor, NOT the developer. It is the
// certified gate for fail-open remediation (PR #306). It must live in
// the project CI (foundry non-fork suite) and stay GREEN. It turns RED the moment
// any future change re-opens the fail-open class (removes a fail-closed branch,
// re-prices an entry off raw slot0, or drops the exit deviation gate). Removing
// or weakening any assertion here requires auditor sign-off.
//
// INVARIANTS ENFORCED (each PASSES on the #306 fix, FAILS if the fix regresses):
//   I1  entry guard fails CLOSED on a fresh pool (cardinality<=1 / no history)
//   I2  entry guard fails CLOSED on a stale/inactive pool (no trade in SECONDS_AGO)
//   I3  entry guard reverts when slot0 deviates > MAX_ALLOWED_DEVIATION from TWAP
//   I4  exit gate reverts on a verifiable pool when slot0 is manipulated > deviation
//   I5  exit is ALWAYS-EXITABLE: on a quiet pool the exit prices off slot0 (no revert)
// The permissionless BuyBackBurner.buyBack path consumes the SAME entry guard
// (BuyBackBurner.checkPoolAndGetCenterPrice) so I1-I3 cover it by construction.
//
// Run: forge test --mc LiquidityManagerPriceGuardRegression -vvv
// =============================================================================

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerCore} from "../contracts/pol/LiquidityManagerCore.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";

/// @dev Programmable mock V3 pool: attacker controls slot0; history drives the
///      fresh / stale / mature branches. observe() returns a flat tick-0 cumulative
///      (TWAP == tick 0) so a slot0 pushed to tick 6931 (~2x) is > the 10% gate.
contract MockV3Pool {
    uint160 public sqrtPriceX96;
    uint16 public observationIndex;
    uint32 public latestObsTimestamp;
    uint16 public cardinality = 1;
    bool public observeReverts;

    function pushPrice(uint160 p) external { sqrtPriceX96 = p; }
    function setCardinality(uint16 c) external { cardinality = c; }
    function setLatestObsTimestamp(uint32 t) external { latestObsTimestamp = t; }
    function setObserveReverts(bool b) external { observeReverts = b; }

    function slot0() external view returns (
        uint160 _p, int24 tick, uint16 _oi, uint16 _c, uint16 _cn, uint8 _fp, bool _u
    ) { _p = sqrtPriceX96; tick = 0; _oi = observationIndex; _c = cardinality; _cn = cardinality; _fp = 0; _u = true; }

    function observations(uint256) external view returns (
        uint32 blockTimestamp, int56 tickCumulative, uint160 spl, bool initialized
    ) { blockTimestamp = latestObsTimestamp; tickCumulative = 0; spl = 0; initialized = true; }

    function observe(uint32[] calldata) external view returns (int56[] memory tc, uint160[] memory spl) {
        if (observeReverts) revert("OLD");
        tc = new int56[](2);   // flat -> average tick 0 -> TWAP == getSqrtRatioAtTick(0)
        spl = new uint160[](2);
    }
}

contract MockPositionManager {
    address public factoryAddr;
    constructor(address f) { factoryAddr = f; }
    function factory() external view returns (address) { return factoryAddr; }
}

/// @dev Concrete LMC exposing the two internal price paths under test.
contract TestLM is LiquidityManagerCore {
    constructor(address pm, address scanner) LiquidityManagerCore(address(1), address(2), pm, scanner, 1) {}
    function _burn(uint256) internal override {}
    function _checkTokensAndRemoveLiquidityV2(address[] memory, bytes32) internal override returns (uint256[] memory a) { a = new uint256[](2); }
    function _feeAmountTickSpacing(int24 f) internal pure override returns (int24) { return f; }
    function _getV3Pool(address[] memory, int24) internal pure override returns (address) { return address(0); }
    function _mintV3(address[] memory, uint256[] memory, uint256[] memory, int24[] memory, int24, uint160)
        internal override returns (uint256, uint128, uint256[] memory) { return (0, 0, new uint256[](2)); }
    // exit price path (internal) exposed for the always-exitable / exit-gate invariants
    function exposedExitSqrtPrice(address p) external view returns (uint160) { return _getExitSqrtPrice(p); }
}

contract LiquidityManagerPriceGuardRegressionTest is Test {
    TestLM internal lm;
    MockV3Pool internal pool;
    uint160 internal manipulated; // ~2x off fair (tick 6931), > the 10% deviation gate

    function setUp() public {
        lm = new TestLM(address(new MockPositionManager(address(0xF))), address(new MockV3Pool()));
        pool = new MockV3Pool();
        manipulated = TickMath.getSqrtRatioAtTick(6931);
        vm.warp(10_000);
    }

    // I1 — entry guard fails CLOSED on a fresh pool (Critical).
    function test_I1_entryGuard_freshPool_failsClosed() public {
        pool.pushPrice(manipulated);
        pool.setCardinality(1);
        pool.setLatestObsTimestamp(uint32(block.timestamp));
        pool.setObserveReverts(true); // no verifiable history
        vm.expectRevert(); // NotEnoughHistory — never price a fresh pool off slot0
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // I2 — entry guard fails CLOSED on a stale/inactive pool (Medium; same on buyBack).
    function test_I2_entryGuard_stalePool_failsClosed() public {
        pool.pushPrice(manipulated);
        pool.setCardinality(60);
        pool.setLatestObsTimestamp(1); // last trade far in the past -> inactive
        vm.expectRevert(); // NotEnoughHistory
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // I3 — entry guard reverts when slot0 is manipulated > MAX_ALLOWED_DEVIATION from the TWAP.
    function test_I3_entryGuard_matureManipulated_reverts() public {
        pool.pushPrice(manipulated);   // slot0 ~ tick 6931
        pool.setCardinality(60);
        pool.setLatestObsTimestamp(uint32(block.timestamp)); // active; observe() -> TWAP tick 0
        vm.expectRevert(); // Overflow(deviation, MAX_ALLOWED_DEVIATION)
        lm.checkPoolAndGetCenterPrice(address(pool));
    }

    // I4 — exit gate reverts on a verifiable pool when slot0 is manipulated > deviation.
    function test_I4_exitGate_matureManipulated_reverts() public {
        pool.pushPrice(manipulated);
        pool.setCardinality(60);
        pool.setLatestObsTimestamp(uint32(block.timestamp));
        vm.expectRevert(); // Overflow — anti-manipulation gate on exit
        lm.exposedExitSqrtPrice(address(pool));
    }

    // I5 — always-exitable: on a quiet pool the exit prices off slot0 and does NOT revert.
    function test_I5_exit_quietPool_alwaysExitable_returnsSlot0() public {
        uint160 fair = TickMath.getSqrtRatioAtTick(0);
        pool.pushPrice(fair);
        pool.setCardinality(60);
        pool.setLatestObsTimestamp(1); // quiet -> gate skipped, returns slot0
        uint160 got = lm.exposedExitSqrtPrice(address(pool));
        assertEq(got, fair, "exit must remain live on a quiet pool (fail-open-soft, capital-bounded)");
    }
}
