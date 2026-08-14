// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// =============================================================================
// exit fail-open slip — fork PoC for review #306.2
// -----------------------------------------------------------------------------
// Review Medium (#306.2): on the fail-open exit branch (inactive pool / freshly-created / cardinality <= 1),
// _getExitSqrtPrice returns raw slot0 with NO deviation gate, so decreaseLiquidity's amountMin derives from
// the manipulated price and provides zero protection. Dev claim: "capital-bounded slip, never the empty-pool
// catastrophe." The review: attacker-unbounded. This settles it empirically AND checks the reachability question:
//
//   The ENTRY guard fails closed, so the LM only ever holds a position on a pool that was verifiable at mint.
//   The exit therefore only meets fail-open when the pool has since gone INACTIVE. But a sandwich attacker's
//   own front-run swap writes an observation and re-activates the pool, which can re-engage the (stale) TWAP
//   deviation gate. So the real question is whether an attacker can push slot0 far AND still route the LM's
//   exit through the fail-open (ungated) branch.
//
// The test makes the warm pool inactive, then for a sweep of attacker swap sizes: attacker moves slot0, the
// LM exits, and we record whether the exit reverted (gate re-caught it) or went through, and — if it went
// through — the LM's realized loss (withdrawn amounts valued at the honest pre-manipulation price).
//
// Run: forge test --mc LiquidityManagerExitFailOpenForkETH --fork-url $ETH_RPC -vv
// =============================================================================

import "./LiquidityManagerUniV2UniV3.t.sol"; // BaseSetup harness
import {console2} from "forge-std/console2.sol";

interface ILMExit {
    function checkPoolAndGetCenterPrice(address pool) external view returns (uint160);
    function decreaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 decreaseRate,
        uint16 olasBurnRate) external returns (uint256, uint128, uint256[] memory);
}

contract LiquidityManagerExitFailOpenForkETHTest is BaseSetup {
    uint32 internal constant SECONDS_AGO = 1800;

    function setUp() public override {
        if (block.chainid != 1) {
            return;
        }
        super.setUp();
    }

    function _pool() internal view returns (address) {
        return IFactory(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], uint24(FEE_TIER));
    }

    /// @dev WETH-per-OLAS price * 1e18 from a sqrt price (token0 = OLAS < token1 = WETH), overflow-safe.
    function _priceE18(uint160 sqrtP) internal pure returns (uint256) {
        uint256 r = (uint256(sqrtP) * 1e9) / (uint256(1) << 96); // sqrt(price) * 1e9
        return r * r;                                            // price * 1e18
    }

    /// @dev Value both withdrawn amounts in WETH at a fixed (honest) price. amounts[0]=OLAS, amounts[1]=WETH.
    function _valueWeth(uint256[] memory amounts, uint256 priceE18) internal pure returns (uint256) {
        return amounts[1] + (amounts[0] * priceE18) / 1e18;
    }

    function test_exit_failOpen_slip_sweep() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        // Mint the LM's position on the warm pool (moderate range).
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 0, false);
        address pool = _pool();

        // Make the pool INACTIVE (no trade within SECONDS_AGO) so the exit meets the fail-open branch.
        vm.warp(block.timestamp + SECONDS_AGO + 60);

        // Sanity: the pool is now unverifiable (entry would fail closed here).
        bool entryFailsClosed;
        try ILMExit(address(liquidityManager)).checkPoolAndGetCenterPrice(pool) {
            entryFailsClosed = false;
        } catch {
            entryFailsClosed = true;
        }
        console2.log("pool inactive -> entry fails closed:", entryFailsClosed ? 1 : 0);

        // Honest price and honest-exit baseline (fail-open uses raw slot0 == honest price when unmanipulated).
        (uint160 sqrtP0,,,,,,) = IUniswapV3(pool).slot0();
        uint256 price0 = _priceE18(sqrtP0);

        uint256 snapH = vm.snapshotState();
        (, , uint256[] memory hAmts) = ILMExit(address(liquidityManager)).decreaseLiquidity(TOKENS, FEE_TIER, 2000, 0);
        uint256 honestValue = _valueWeth(hAmts, price0);
        console2.log("honest exit value (WETH-e18):", honestValue);
        vm.revertToState(snapH);

        // Sweep attacker OLAS-dump sizes (crash OLAS price before the LM exits).
        uint256[6] memory atk =
            [uint256(50_000 ether), uint256(200_000 ether), uint256(1_000_000 ether),
             uint256(5_000_000 ether), uint256(20_000_000 ether), uint256(80_000_000 ether)];

        console2.log("=== attackerOlasIn | slot0DevBps | exitReverted(1) | lossBps ===");
        bool anyExploited;
        for (uint256 k = 0; k < atk.length; k++) {
            uint256 snap = vm.snapshotState();

            // Attacker front-runs: dump OLAS -> WETH to crash the OLAS price (writes an observation).
            _swap(OLAS, WETH, atk[k]);
            (uint160 sqrtM,,,,,,) = IUniswapV3(pool).slot0();
            uint256 devBps;
            {
                uint256 pm = _priceE18(sqrtM);
                devBps = pm > price0 ? (pm - price0) * 1e4 / price0 : (price0 - pm) * 1e4 / price0;
            }

            // The LM owner exits into the (possibly re-activated) pool.
            try ILMExit(address(liquidityManager)).decreaseLiquidity(TOKENS, FEE_TIER, 2000, 0)
                returns (uint256, uint128, uint256[] memory aAmts)
            {
                uint256 attackedValue = _valueWeth(aAmts, price0); // value at the HONEST price
                uint256 lossBps = honestValue > attackedValue ? (honestValue - attackedValue) * 1e4 / honestValue : 0;
                console2.log("  atkOlas", atk[k], "slot0DevBps", devBps);
                console2.log("    exitReverted 0  lossBps", lossBps);
                if (lossBps > 0) anyExploited = true;
            } catch {
                console2.log("  atkOlas", atk[k], "slot0DevBps", devBps);
                console2.log("    exitReverted 1  (gate re-caught the manipulation)");
            }

            vm.revertToState(snap);
        }

        console2.log("=== exit fail-open exploited for non-zero loss:", anyExploited ? 1 : 0, "===");

        // FINDING (review #306.2) — INACTIVE-pool fail-open trigger: NOT exploitable for the LM's positions.
        //  (1) the ENTRY guard fails closed, so the LM only holds positions on pools that were verifiable at
        //      mint; this exit only meets fail-open when such a pool later goes INACTIVE.
        //  (2) a sandwich attacker's front-run swap re-activates the pool (writes an observation), re-engaging
        //      the deviation gate against the still-stale TWAP: every manipulation large enough to move slot0
        //      past ~10% is caught (exit reverts Overflow), and every smaller one produces no measurable loss.
        // So on THIS trigger the "no empty-pool catastrophe" property holds via gate re-engagement, not a
        // capital bound. NOTE: the SECOND fail-open trigger — observe(1800) reverting because the buffer wrapped
        // below 1800s under churn — is genuinely reachable (re-activation does NOT rescue it), but the test
        // below shows it still extracts no value from a decreaseLiquidity. Guard against regressions:
        assertFalse(anyExploited, "inactive-pool fail-open exit produced a measurable loss - branch became exploitable");
    }

    /// @dev The OTHER fail-open trigger: observe(1800) reverts because the observation buffer no longer spans
    ///      1800s (cardinality wrapped under churn). Unlike the inactive-pool branch, re-activation does NOT
    ///      rescue it — a front-run swap writes an observation but that shortens the buffer's span, it does not
    ///      extend it — so the exit deviation gate genuinely stays OFF (confirmed below: entry fails closed, and
    ///      a 20M-OLAS manipulation the gate would otherwise catch does not revert the exit). And yet the LM
    ///      loses no value: removing liquidity at a manipulated price returns amounts worth >= the fair value at
    ///      the true price (the standard LP result — the exit amountMin guards the token SPLIT, not value). So
    ///      the gate being off on this branch is not a value-extraction hole for decreaseLiquidity; the R1
    ///      cardinality gate is defense-in-depth (keep the gate on, avoid the unbalanced-split residual), not a
    ///      fix for a loss. Simulated by mocking observe() to revert while the pool stays active.
    function test_exit_failOpen_bufferWrap_noValueLoss() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -6000;
        tickShifts[1] = 6000;
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 0, false);
        address pool = _pool();

        // Honest price + baseline exit (pool verifiable, gate passes with no manipulation).
        (uint160 sqrtP0,,,,,,) = IUniswapV3(pool).slot0();
        uint256 price0 = _priceE18(sqrtP0);
        uint256 snap = vm.snapshotState();
        (, , uint256[] memory hAmts) = ILMExit(address(liquidityManager)).decreaseLiquidity(TOKENS, FEE_TIER, 2000, 0);
        uint256 honestValue = _valueWeth(hAmts, price0);
        vm.revertToState(snap);

        // Buffer-wrap state: observe(1800) reverts while observations() (the inactivity check) still reads
        // recent, so the pool is "active" but has no verifiable TWAP -> _getExitSqrtPrice fails open, no gate.
        vm.mockCallRevert(pool, abi.encodeWithSelector(bytes4(keccak256("observe(uint32[])"))), bytes(""));

        // Sanity: the entry guard fails closed here (a mint would refuse), but the exit falls open below.
        bool entryFailsClosed;
        try ILMExit(address(liquidityManager)).checkPoolAndGetCenterPrice(pool) { entryFailsClosed = false; }
        catch { entryFailsClosed = true; }
        assertTrue(entryFailsClosed, "entry should fail closed under a buffer-wrap");

        // Attacker manipulates slot0 (a real swap; does not call observe(), so the mock persists), then the LM
        // exits into the ungated fail-open branch at the manipulated price. This is a manipulation the deviation
        // gate WOULD have caught on a verifiable pool (>10% off TWAP); here the gate is off, yet the exit does
        // NOT revert — proving the branch is genuinely reachable, not gate-rescued like the inactive one.
        _swap(OLAS, WETH, 20_000_000 ether);
        (, , uint256[] memory aAmts) = ILMExit(address(liquidityManager)).decreaseLiquidity(TOKENS, FEE_TIER, 2000, 0);
        uint256 attackedValue = _valueWeth(aAmts, price0); // withdrawn amounts valued at the HONEST price
        uint256 lossBps = honestValue > attackedValue ? (honestValue - attackedValue) * 1e4 / honestValue : 0;
        console2.log("buffer-wrap fail-open lossBps (at true price):", lossBps);

        // No value extraction: even with the gate provably off, removing liquidity at the manipulated price
        // returns amounts worth >= the fair value at the true price (the amountMin guards the token split, not
        // value). So the buffer-wrap fail-open is reachable but not a decreaseLiquidity value-loss hole; R1
        // (sizing observationCardinality for peak churn) is defense-in-depth, not a loss fix.
        assertLe(lossBps, 10, "buffer-wrap fail-open should not extract value from a liquidity removal");
    }
}
