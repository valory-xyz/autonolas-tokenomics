// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {Test} from "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniV3Pool {
    function slot0()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint16 obsIndex, uint16 obsCard, uint16 obsCardNext, uint8 feeProtocol, bool unlocked);
    function liquidity() external view returns (uint128);
    function token0() external view returns (address);
}

/// @title LiquidityManager source-side manipulation cross-check — ETH fork prototype (issue #324)
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @dev PROTOTYPE / MEASUREMENT harness. Nothing here is wired into the production contracts yet — it exists to
///      de-risk the design proposed in issue #324 before a tolerance is committed. It reads live mainnet state and
///      exercises the proposed check as a pure helper (`_ratioDivergenceBps`).
///
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// BACKGROUND — what #324 wants to drop, and why it is safe to
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// The source side of the LiquidityManager (`_checkTokensAndRemoveLiquidityV2` in the UniV2 / Balancer source
/// mixins) derived a manipulation-resistant `minAmountsOut` from a per-chain TWAP oracle (a shared
/// `_fairMinAmountsOut` helper -> `IOracle(oracleV2).getTWAP()`). That min-out was the SOLE
/// purpose of the `oracleV2` deployment and — post-#306.1 — the only live use of the `liquidityManagerMaxSlippage`
/// deploy parameter. #324 proposes dropping it, because a proportional `removeLiquidity` CANNOT be sandwiched for a
/// value loss: burning `L` LP at manipulated reserves `(RA', RB')` with `RA'·RB' = k` yields a basket worth
/// `L/TS · RB · (m + 1/m)` at the true price, and `m + 1/m ≥ 2` for any manipulation `m` — i.e. ALWAYS ≥ the fair
/// (balanced) value. A skewed pool hands the remover MORE value at the true price, never less (constant-product
/// convexity; the same result proved for the V3 exit in audits/internal20 R6 / vulnerabilities-list #26).
///
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// THE RESIDUAL CONCERN, AND WHY THE V3-SIDE CHECKS DON'T COVER IT
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// `convertToV3` removes from V2 and, in the SAME tx, mints the basket into a V3 position. With the oracle gone, a
/// V2 pool manipulated to skew `(A, B)` is not caught by the V3-side defences, because those defend the V3 POOL,
/// not the incoming basket:
///   • `MAX_ALLOWED_DEVIATION` (2%) gate (`checkPoolAndGetCenterPrice`) reverts if the V3 pool's slot0 deviates
///     from its own TWAP — it verifies the V3 pool is un-manipulated; it never inspects the `(A, B)` ratio.
///   • the mint's `amount{0,1}Min` are slot0-anchored post-#306.1 (they equal what is minted) — vacuous here.
/// So a skewed removal mints what the V3 ratio accepts and sweeps the excess of the over-represented token to the
/// treasury (see `convertToV3`'s trailing `_manageUtilityAmounts(tokens, MAX_BPS, false)` — leftovers are
/// TRANSFERRED to treasury, not burned/lost). Net: no value loss (convexity + leftover retained), but a lopsided,
/// inefficient conversion — most POL parked idle in treasury instead of placed in V3.
///
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// THE PROPOSED REPLACEMENT — cross-check the V2-removed ratio against the gate-verified V3 slot0
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// `convertToV3` ALREADY computes a trusted price it isn't reusing: `sqrtP = checkPoolAndGetCenterPrice(v3Pool)`,
/// gate-proven within 2% of the V3 pool's own TWAP. The V2-removed amounts are reserve-proportional, so their
/// ratio `A:B` IS the V2 spot price. Two pools tracking the same OLAS price arbitrage to the same level, therefore:
///
///     assert | ratio(A:B) − price(V3 slot0) | / price(V3 slot0) ≤ tolerance
///
/// is exactly today's "V2 spot vs a trusted reference" check — with the reference swapped from an external TWAP
/// oracle to the V3 pool's own slot0, which is already on hand and already gate-verified. This DROPS the per-chain
/// oracle (the #324 goal) yet KEEPS a manipulation gate, and re-tasks `maxSlippage` as the V2↔V3 tolerance rather
/// than retiring it. Prefer this input-RATIO check over a "leftover must be small" check: leftover size after a
/// CONCENTRATED mint depends on the tick range the scanner picks, not just price, so it conflates a narrow range
/// with manipulation; the `A:B`-vs-slot0 ratio is range-independent.
///
/// TRUST PRECONDITION (important, and already enforced): the reference is only meaningful on a WARMED V3 pool. An
/// empty pool's slot0 is a stale artifact — see `test_olasV3Pool_unseeded_referenceIsStale` (OLAS/WETH V3 on ETH is
/// unseeded today: `liquidity()==0`, slot0 ~93% off the live V2 price). That is precisely the state the 2%
/// `MAX_ALLOWED_DEVIATION` gate + the runbook pre-warm already reject BEFORE any mint, so the cross-check is never
/// consulted against an untrustworthy reference. The two checks compose: the gate guarantees the reference is
/// trustworthy; the cross-check guarantees the V2 input matches that trustworthy reference.
///
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/// WHAT THIS TEST MEASURES / DEMONSTRATES (self-skips off an ETH mainnet fork)
/// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
///   1. test_deepPairBasis_isTiny            — natural V2↔V3 basis on a deep, heavily-arbitraged pair (WETH/USDC):
///                                             MEASURED 0–20 bps. Honest pools agree to <0.2%, so any workable OLAS
///                                             tolerance (whole percent) clears honest flow with room to spare.
///   2. test_olasV3Pool_unseeded_referenceIsStale — the trust precondition, shown live: OLAS/WETH V3 unseeded,
///                                             slot0 useless as a reference (MEASURED ~9361 bps off V2) → the exact
///                                             state the 2% gate rejects.
///   3. test_crossCheck_catchesV2Manipulation — a REAL sandwich swap on the live OLAS/WETH V2 pair (50 WETH into a
///                                             ~272 WETH pool) moves the removed `A:B` ratio MEASURED ~4007 bps
///                                             (~40%) off the pre-trade (true) price → the cross-check would revert,
///                                             vs 0 bps for the honest baseline in the same test.
///   4. test_crossCheck_passesHonestRemoval  — an un-manipulated removal vs a reference seeded at the true price
///                                             diverges 0 bps → honest flow is untouched.
contract LiquidityManagerV2V3CrossCheckForkETHTest is Test {
    // OLAS/WETH — OLAS is live on Uniswap V2 (deep) but its V3 pool is unseeded (that's what POL migration seeds).
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant OLAS_WETH_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant OLAS_WETH_V3_1PCT = 0x18f7B33172F5150949EeF05EbB3b5D4Fe245f391; // fee 10000
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // WETH/USDC — live on BOTH Uniswap V2 and Uniswap V3; a proxy for the natural V2↔V3 basis on a deep pair.
    address internal constant WETH_USDC_V2 = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant WETH_USDC_V3_005PCT = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // fee 500
    address internal constant WETH_USDC_V3_030PCT = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8; // fee 3000

    uint256 internal constant Q96 = 0x1000000000000000000000000; // 2**96

    function setUp() public {
        // Self-skip when not on an ETH mainnet fork (chainId 1). Run with:
        //   forge test -f $FORK_ETH_NODE_URL --mc LiquidityManagerV2V3CrossCheckForkETH -vv
        if (block.chainid != 1) {
            vm.skip(true);
        }
    }

    // ─── proposed cross-check, prototyped as pure helpers (mirror what production would inline) ───

    /// @dev V3 price (token1 per token0), 1e18-scaled, from a sqrtPriceX96. Overflow-safe for realistic sqrtP:
    ///      staged mulDiv keeps every intermediate under 2**256 (sqrtP² fits for OLAS/WETH ~1e54 and WETH/USDC ~3e66).
    function _priceFromSqrt(uint160 sqrtP) internal pure returns (uint256) {
        uint256 sp = uint256(sqrtP);
        // (sqrtP² / 2**96) — this is price·2**96
        uint256 priceX96 = FixedPointMathLib.mulDivDown(sp, sp, Q96);
        // ·1e18 / 2**96 — drops the last 2**96 and rescales to 1e18
        return FixedPointMathLib.mulDivDown(priceX96, 1e18, Q96);
    }

    /// @dev Divergence in bps between the V2-removed ratio (amount1/amount0 == V2 spot, amounts being
    ///      reserve-proportional) and the gate-verified V3 slot0 price. This is the quantity the proposed
    ///      `require(divergence <= maxSlippage)` would gate on.
    function _ratioDivergenceBps(uint256 amount0, uint256 amount1, uint160 sqrtP) internal pure returns (uint256) {
        uint256 pV2 = FixedPointMathLib.mulDivDown(amount1, 1e18, amount0); // token1 per token0
        uint256 pV3 = _priceFromSqrt(sqrtP);
        uint256 diff = pV2 > pV3 ? pV2 - pV3 : pV3 - pV2;
        return (diff * 10000) / pV3;
    }

    /// @dev sqrtPriceX96 corresponding to a reserve pair — the price a V3 pool seeded at that pair's spot would show.
    function _sqrtFromReserves(uint256 reserve0, uint256 reserve1) internal pure returns (uint160) {
        // sqrtP = sqrt(reserve1/reserve0)·2**96 = sqrt(reserve1·1e18/reserve0)·2**96/1e9  (staged to avoid overflow)
        uint256 price1e18 = FixedPointMathLib.mulDivDown(reserve1, 1e18, reserve0);
        uint256 sqrt1e9 = FixedPointMathLib.sqrt(price1e18); // == sqrt(price)·1e9
        return uint160(FixedPointMathLib.mulDivDown(sqrt1e9, Q96, 1e9));
    }

    function _reserves(address pair) internal view returns (uint256 r0, uint256 r1) {
        (uint112 a, uint112 b,) = IUniV2Pair(pair).getReserves();
        (r0, r1) = (uint256(a), uint256(b));
    }

    function _sqrt0(address pool) internal view returns (uint160 sqrtP) {
        (sqrtP,,,,,,) = IUniV3Pool(pool).slot0();
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    // 1. Natural V2↔V3 basis on a deep pair: honest pools agree to <0.2% → tolerance has ample headroom.
    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    function test_deepPairBasis_isTiny() public {
        (uint256 r0, uint256 r1) = _reserves(WETH_USDC_V2);

        uint256 basis005 = _ratioDivergenceBps(r0, r1, _sqrt0(WETH_USDC_V3_005PCT));
        uint256 basis030 = _ratioDivergenceBps(r0, r1, _sqrt0(WETH_USDC_V3_030PCT));
        emit log_named_uint("WETH/USDC V2 vs V3 0.05% basis (bps)", basis005);
        emit log_named_uint("WETH/USDC V2 vs V3 0.30% basis (bps)", basis030);

        // A deep, heavily-arbitraged pair keeps its V2↔V3 basis well under 1% — the honest floor a tolerance
        // must clear. OLAS being thinner will sit above this, but the mechanism (honest << manipulated) holds.
        assertLt(basis005, 100, "deep-pair V2<->V3 basis unexpectedly wide");
        assertLt(basis030, 100, "deep-pair V2<->V3 basis unexpectedly wide");
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    // 2. Trust precondition, live: an unseeded V3 pool's slot0 is a stale artifact — the state the 2% gate rejects.
    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    function test_olasV3Pool_unseeded_referenceIsStale() public {
        // OLAS/WETH V3 has no in-range liquidity: nothing arbitrages its slot0 toward the true price.
        assertEq(IUniV3Pool(OLAS_WETH_V3_1PCT).liquidity(), 0, "assumed-unseeded OLAS/WETH V3 now has liquidity");
        assertEq(IUniV3Pool(OLAS_WETH_V3_1PCT).token0(), OLAS, "unexpected V3 token0 ordering");

        (uint256 r0, uint256 r1) = _reserves(OLAS_WETH_V2);
        uint256 divergence = _ratioDivergenceBps(r0, r1, _sqrt0(OLAS_WETH_V3_1PCT));
        emit log_named_uint("OLAS/WETH live-V2 vs unseeded-V3 slot0 divergence (bps)", divergence);

        // The stale slot0 sits absurdly far from the live V2 price (~9000+ bps). Cross-checking against THIS would
        // be meaningless — which is why the design only ever runs the cross-check AFTER the 2% MAX_ALLOWED_DEVIATION
        // gate (checkPoolAndGetCenterPrice) + the runbook pre-warm have accepted the pool. An unseeded pool fails
        // that gate and never reaches the mint, let alone the cross-check.
        assertGt(divergence, 200, "unseeded V3 slot0 unexpectedly near the live V2 price");
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    // 3. A real sandwich on the live OLAS/WETH V2 pair moves the removed ratio far past any sane tolerance.
    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    function test_crossCheck_catchesV2Manipulation() public {
        (uint256 r0Before, uint256 r1Before) = _reserves(OLAS_WETH_V2);

        // Reference = the true price a warmed V3 pool reflects. The attacker touches only V2 within this tx, so the
        // V3 reference stays at the pre-trade price (cross-pool arb is not instant intra-tx).
        uint160 sqrtRef = _sqrtFromReserves(r0Before, r1Before);

        // Honest baseline: removed ratio at the un-manipulated reserves matches the reference ~exactly.
        uint256 honest = _ratioDivergenceBps(r0Before, r1Before, sqrtRef);
        emit log_named_uint("honest removed-ratio vs reference (bps)", honest);
        assertLt(honest, 50, "reserve-derived reference should match its own reserves");

        // Attacker front-runs: dump 50 WETH into the V2 pair (pool holds ~272 WETH → a large but plausible sandwich).
        uint256 attackWeth = 50 ether;
        deal(WETH, address(this), attackWeth);
        IERC20(WETH).approve(ROUTER_V2, attackWeth);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = OLAS;
        IUniV2Router(ROUTER_V2).swapExactTokensForTokens(attackWeth, 0, path, address(this), block.timestamp + 1);

        // Now a removal would pull this skewed basket; its ratio is the post-trade reserve ratio.
        (uint256 r0After, uint256 r1After) = _reserves(OLAS_WETH_V2);
        uint256 manipulated = _ratioDivergenceBps(r0After, r1After, sqrtRef);
        emit log_named_uint("manipulated removed-ratio vs reference (bps)", manipulated);

        // The skewed removal is worth >= fair value at the true price (convexity — no loss). But its RATIO is now
        // wildly off the trusted V3 reference, so the proposed cross-check catches it and reverts — preventing the
        // lopsided, treasury-parking conversion described in the header. A few-hundred-bps tolerance rejects it
        // outright, while the honest case above passes with <50 bps.
        assertGt(manipulated, 500, "cross-check failed to flag a real V2 manipulation");
        assertGt(manipulated, honest * 10, "manipulation not clearly separated from honest flow");
    }

    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    // 4. An honest removal against a reference seeded at the true price passes with ~0 divergence.
    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    function test_crossCheck_passesHonestRemoval() public {
        (uint256 r0, uint256 r1) = _reserves(OLAS_WETH_V2);
        uint160 sqrtRef = _sqrtFromReserves(r0, r1); // V3 seeded at the true OLAS price
        uint256 divergence = _ratioDivergenceBps(r0, r1, sqrtRef);
        emit log_named_uint("honest OLAS removal vs seeded-at-true-price V3 (bps)", divergence);
        assertLt(divergence, 50, "honest removal should sail through the cross-check");
    }
}
