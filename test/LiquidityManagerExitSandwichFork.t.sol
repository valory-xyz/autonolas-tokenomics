// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// =============================================================================
// exit soft-floor — AUDITOR-OWNED fork PoC of the load-bearing exit claim (L1)
// -----------------------------------------------------------------------------
// Empirically confirms, on a REAL mainnet-forked Uniswap V3 pool, the Goal-2
// Lemma L1 ("self-defeating sandwich"): an attacker who manipulates slot0 in a
// single block (slot0 jumps; observations() still record the pre-swap tick, so
// the 30-min TWAP is unmoved) CANNOT sandwich the owner's decreaseLiquidity —
// the exit deviation gate reverts. And the honest owner exit on the same pool
// SUCCEEDS (always-exitable). This is the exit analog of the dev's
// testCheckPoolAndGetCenterPrice_FlashManipulationReverts, extended to the exit
// path (_getExitSqrtPrice) which #306's soft floor relies on.
//
// Run: forge test --mc LiquidityManagerExitSandwichFork --fork-url $ETH_RPC -vvv
// =============================================================================

import "./LiquidityManagerETH.t.sol"; // LiquidityManagerETHTest harness + IUniswapV3 + IFactory

contract LiquidityManagerExitSandwichForkTest is LiquidityManagerETHTest {
    function test_L1_exitSandwich_manipulatedSlot0_reverts_honestExit_succeeds() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;

        // Seed a real V3 position so the pool has a verifiable observation history.
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 0, true);
        address pool = IFactory(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], uint24(FEE_TIER));
        (uint160 realSqrtP, , uint16 realObsIdx, , , , ) = IUniswapV3(pool).slot0();

        // Advance to open the 30-min TWAP window (pool stays just-active, gate applies).
        vm.warp(block.timestamp + 1800);

        // --- Attack: single-block slot0 manipulation (3x ~ 9x price, > 10% gate).
        // observations() are NOT mocked -> they still reflect the pre-manipulation
        // history, exactly as a real single-block swap leaves the 30-min TWAP.
        uint160 manip = uint160(uint256(realSqrtP) * 3);
        vm.mockCall(
            pool,
            abi.encodeWithSignature("slot0()"),
            abi.encode(manip, int24(0), realObsIdx, uint16(60), uint16(60), uint8(0), true)
        );

        // L1: the owner's exit under the sandwich must REVERT (Overflow deviation gate).
        vm.expectRevert();
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, 1000, 0);

        vm.clearMockedCalls();

        // Always-exitable: the honest owner exit on the same real pool SUCCEEDS.
        liquidityManager.decreaseLiquidity(TOKENS, FEE_TIER, 1000, 0);
    }
}
