// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// =============================================================================
// increase dead-band — fork PoC for review #306.1
// -----------------------------------------------------------------------------
// Empirically settles the review High finding (#306.1): _increaseLiquidity anchors the liquidity math and the
// amountMin floor to the TWAP center (checkPoolAndGetCenterPrice), while the Uniswap V3 NPM executes at
// slot0. When slot0 != TWAP but WITHIN the 10% deviation gate, does the amount-space amount{0,1}Min check
// reject the mint — a dead band where the pre-flight gate accepts but increaseLiquidity reverts?
//
// Sweeps {range half-width} x {slot0-vs-TWAP deviation, driven by a real swap} on a real ETH-forked
// OLAS/WETH V3 pool, and for each cell records: measured deviation (bps), whether it is within the gate,
// and whether increaseLiquidity reverts. A dead-band cell is (withinGate == true && increaseReverted == true).
// Fork-only; self-skips off-fork and is NOT in the CI --mc allowlist.
//
// Run: forge test --mc LiquidityManagerIncreaseDeadBandForkETH --fork-url $ETH_RPC -vv
// =============================================================================

import "./LiquidityManagerUniV2UniV3.t.sol"; // BaseSetup harness (fork, OLAS/WETH, _swap, constants)
import {console2} from "forge-std/console2.sol";

interface ILMDev {
    function getTwapFromOracle(address pool) external view returns (uint256 twapPrice, uint160 twapSqrtPriceX96);
    function checkPoolAndGetCenterPrice(address pool) external view returns (uint160);
    function MAX_ALLOWED_DEVIATION() external view returns (uint256);
    function increaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 olasBurnRate)
        external returns (uint256, uint256, uint256[] memory);
}

contract LiquidityManagerIncreaseDeadBandForkETHTest is BaseSetup {
    function setUp() public override {
        if (block.chainid != 1) {
            return; // off-fork: skip the mainnet harness setup
        }
        super.setUp();
    }

    /// @dev slot0-vs-TWAP price deviation scaled to 1e18, matching LiquidityManagerCore._getPoolPriceFacts
    ///      (price space: |slot0^2 - twap^2| / twap^2), computed from sqrt prices without overflow.
    function _deviationE18(uint160 slot0Sqrt, uint160 twapSqrt) internal pure returns (uint256) {
        uint256 r = (uint256(slot0Sqrt) * 1e9) / uint256(twapSqrt); // sqrt(price ratio) * 1e9
        uint256 priceRatioE18 = r * r;                              // price ratio * 1e18
        return priceRatioE18 > 1e18 ? priceRatioE18 - 1e18 : 1e18 - priceRatioE18;
    }

    function _pool() internal view returns (address) {
        return IFactory(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], uint24(FEE_TIER));
    }

    /// @dev One sweep cell: mint a position of the given half-width, move slot0 by a real swap, measure the
    ///      deviation, and (if within the gate) attempt increaseLiquidity.
    function _cell(int24 halfWidth, uint256 swapWeth)
        internal
        returns (uint256 devBps, bool withinGate, bool increaseReverted, bool minted)
    {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -halfWidth;
        tickShifts[1] = halfWidth;

        // Mint the LM's position of this range width (pool is pre-warmed by BaseSetup).
        try liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 0, false) {
            minted = true;
        } catch {
            return (0, false, false, false); // range too narrow / mint failed — record and skip
        }

        address pool = _pool();

        // Move slot0 with a real swap (moves both the slot0 view and the pool's storage price together;
        // observations still hold the pre-swap ticks, so the 30-min TWAP is unmoved -> slot0 != TWAP).
        _swap(WETH, OLAS, swapWeth);

        // Measure the deviation exactly as the contract does.
        (uint160 slot0Sqrt,,,,,,) = IUniswapV3(pool).slot0();
        (, uint160 twapSqrt) = ILMDev(address(liquidityManager)).getTwapFromOracle(pool);
        uint256 deviation = _deviationE18(slot0Sqrt, twapSqrt);
        withinGate = deviation <= ILMDev(address(liquidityManager)).MAX_ALLOWED_DEVIATION();
        // Cap the display for out-of-gate cells (a huge swap can send slot0 far past the range, making the
        // raw ratio meaningless); withinGate already excludes them from the dead-band determination.
        devBps = deviation > 100e18 ? 999999 : deviation / 1e14; // 1e18 -> bps

        if (!withinGate) {
            return (devBps, false, false, true); // outside the gate — checkPool would revert; not a dead band
        }

        // Fund the LM and attempt the increase. Within the gate, the pre-flight guard accepts; the question
        // is whether the TWAP-anchored amountMin then rejects the mint at the NPM's slot0 execution.
        deal(OLAS, address(liquidityManager), 5000 ether);
        deal(WETH, address(liquidityManager), 2 ether);
        try ILMDev(address(liquidityManager)).increaseLiquidity(TOKENS, FEE_TIER, 0) {
            increaseReverted = false;
        } catch {
            increaseReverted = true;
        }
    }

    function test_increase_deadBand_sweep() public {
        if (block.chainid != 1) {
            vm.skip(true);
            return;
        }

        // Range half-widths in ticks (tick spacing 60 for the 0.3% tier): narrow -> wide.
        int24[6] memory halfWidths = [int24(120), int24(600), int24(1800), int24(6000), int24(18000), int24(27000)];
        // WETH swap sizes producing increasingly large slot0 moves — pushed up to straddle the 10% gate so
        // the 4-9%-within-gate window (where a dead band would live) is actually exercised.
        uint256[8] memory swaps = [
            uint256(1 ether), uint256(5 ether), uint256(15 ether), uint256(30 ether),
            uint256(60 ether), uint256(120 ether), uint256(250 ether), uint256(500 ether)
        ];

        console2.log("=== dead-band sweep: halfWidthTicks | swapWeth | deviationBps | withinGate(1) | increaseReverted(1) ===");
        bool anyDeadBand;
        for (uint256 i = 0; i < halfWidths.length; i++) {
            for (uint256 j = 0; j < swaps.length; j++) {
                uint256 snap = vm.snapshotState();
                (uint256 devBps, bool withinGate, bool reverted, bool minted) = _cell(halfWidths[i], swaps[j]);
                console2.log("halfWidth", uint256(uint24(halfWidths[i])), "swapWeth", swaps[j]);
                console2.log("  minted", minted ? 1 : 0, "deviationBps", devBps);
                console2.log("  withinGate", withinGate ? 1 : 0, "increaseReverted", reverted ? 1 : 0);
                if (withinGate && reverted) {
                    anyDeadBand = true;
                }
                vm.revertToState(snap);
            }
        }
        console2.log("=== dead band observed within the gate:", anyDeadBand ? 1 : 0, "===");

        // REGRESSION GUARD (review #306.1): amountMin is now anchored to slot0 (the execution price) on both
        // entry paths (mint and increase), so no cell inside the 10% pre-flight gate should have the entry
        // revert. Before the fix this sweep produced dead-band cells at 0.65%-6.95% deviation for narrow ranges
        // (half-widths 120/600/1800); the fix must keep this empty.
        assertFalse(anyDeadBand, "dead band within the gate after the slot0 re-anchor - regression");
    }
}
