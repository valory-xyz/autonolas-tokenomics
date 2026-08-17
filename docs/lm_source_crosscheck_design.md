# LiquidityManager source-side manipulation gate — oracle → V3-slot0 cross-check (issue #324)

This note captures the design that lets the LiquidityManager drop its per-chain source-side TWAP oracle
(`oracleV2`) without losing a manipulation gate on the V2/Balancer `removeLiquidity` path — issue **#324**.

**Status: implemented.** The cross-check is wired into `convertToV3` (`LiquidityManagerCore._checkRemovedRatioAgainstV3`)
and `oracleV2` / `_fairMinAmountsOut` are removed. Fork evidence: the design prototype
`test/LiquidityManagerV2V3CrossCheckForkETH.t.sol` (measurements on live pools) and the integration test
`test/LiquidityManagerV2V3RatioCheckForkETH.t.sol` (the real deployed path: honest convert passes, a real
V2 sandwich reverts `RatioDeviation`, and the 5% tolerance boundary is measured).

## Today

The source mixins (`LiquidityManagerSourceUniV2` / `LiquidityManagerSourceBalancer`) derive a
manipulation-resistant `minAmountsOut` for the withdrawal from a per-chain TWAP oracle, in
`LiquidityManagerSourceBase._fairMinAmountsOut` → `IOracle(oracleV2).getTWAP()`. That min-out is:

- the **sole** purpose of the `oracleV2` deployment on every chain, and
- post-#306.1, the **only live use** of the `liquidityManagerMaxSlippage` deploy parameter (its V3
  `amount{0,1}Min` uses are vacuous — slot0-anchored).

So the oracle is a standing deployment + "is this oracle still current?" maintenance burden whose only job is
this one floor.

## Why the floor isn't protecting value

A proportional `removeLiquidity` **cannot be sandwiched for a value loss**. Burning `L` LP at manipulated
reserves `(RA', RB')` with `RA'·RB' = k` yields a basket worth `L/TS · RB · (m + 1/m)` at the *true* price,
and `m + 1/m ≥ 2` for any manipulation factor `m`. A skewed pool hands the remover **≥ the fair (balanced)
value**, never less — the same constant-product convexity proved for the V3 exit in `audits/internal20` R6 /
vulnerabilities-list #26 (`dV/dPm = (L/2√Pm)(1 − Pt/Pm)`). Removing the floor cannot cause a value loss.

## The residual concern — and why the existing V3-side checks don't cover it

`convertToV3` removes from V2 and, in the **same transaction**, mints the basket into a V3 position. With the
oracle gone, a V2 pool manipulated to skew `(A, B)` is **not** caught by the V3-side defences, because those
defend the V3 *pool*, not the incoming basket:

- `MAX_ALLOWED_DEVIATION` (2%) gate (`checkPoolAndGetCenterPrice`) reverts if the V3 pool's slot0 deviates from
  its own TWAP — it verifies the V3 pool is un-manipulated; it never inspects the `(A, B)` ratio.
- the mint's `amount{0,1}Min` are slot0-anchored post-#306.1 (they equal what is minted) — vacuous here.

A skewed removal therefore mints what the V3 ratio accepts and **sweeps the excess of the over-represented
token to the treasury** (`convertToV3`'s trailing `_manageUtilityAmounts(tokens, MAX_BPS, false)` — leftovers
are *transferred* to treasury, not burned/lost). Net result: **no value loss** (convexity + leftover retained),
but a lopsided, inefficient conversion — most POL parked idle in treasury instead of placed in V3.

One step sits between removal and mint that the removal → mint → leftovers walk above skips: when `convertToV3`
is called with a non-zero `olasBurnRate`, `_manageUtilityAmounts(tokens, olasBurnRate, true)` **burns** that
rate of the removed OLAS *before* the mint — irreversibly, where leftovers are merely parked. The cross-check
runs *after* this burn, which is safe precisely because `convertToV3` is one transaction: a `RatioDeviation`
revert unwinds the burn atomically (so placement after the burn is deliberate, not a bug — hoisting it earlier
buys nothing). What the cross-check does **not** unwind is a *within-tolerance* skew: at 500 bps a manipulator
can shift the burned OLAS by up to ~5% at swap-fee cost. That is bounded and value-safe by convexity, but it is
a real property of a rate-on-realized-amounts design, and it matters more the larger the migration's
`olasBurnRate` — an **accepted residual**, recorded here rather than left implicit.

## Proposed replacement — cross-check the V2-removed ratio against the gate-verified V3 slot0

`convertToV3` already computes a trusted price it isn't reusing:
`sqrtP = checkPoolAndGetCenterPrice(v3Pool)`, gate-proven within 2% of the V3 pool's own TWAP. The V2-removed
amounts are reserve-proportional, so their ratio `A:B` **is** the V2 spot price. Two pools tracking the same
OLAS price arbitrage to the same level, hence:

```
assert | ratio(A:B) − price(V3 slot0) | / price(V3 slot0) ≤ tolerance
```

This is exactly today's "V2 spot vs a trusted reference" check — with the reference swapped from an **external
TWAP oracle** to the **V3 pool's own slot0**, which is already on hand and already gate-verified. It:

- **drops the per-chain oracle** (the #324 goal), and
- **keeps a manipulation gate**, and
- **re-tasks `maxSlippage`** as the V2↔V3 tolerance instead of retiring it.

### Ratio check, not "small leftover" check

Prefer the input-**ratio** check over a "leftover must be small after mint" check. Leftover size after a
*concentrated* mint depends on the tick range the scanner picks, not just price, so a leftover test conflates a
narrow range with manipulation. The `A:B`-vs-slot0 ratio is range-independent.

### Trust precondition (already enforced)

The reference is only meaningful on a **warmed** V3 pool. An empty pool's slot0 is a stale artifact — the
prototype shows OLAS/WETH V3 on ETH today is unseeded (`liquidity()==0`, slot0 ~9361 bps off the live V2
price). That is precisely the state the 2% `MAX_ALLOWED_DEVIATION` gate + the runbook pre-warm already reject
**before** any mint, so the cross-check is never consulted against an untrustworthy reference. The two checks
**compose**: the gate guarantees the reference is trustworthy; the cross-check guarantees the V2 input matches
that trustworthy reference.

## Fork evidence (`test/LiquidityManagerV2V3CrossCheckForkETH.t.sol`, ETH mainnet)

| Scenario | Measured divergence | Meaning |
| --- | --- | --- |
| Deep dual-live pair WETH/USDC, V2 vs V3 (0.05% / 0.30%) | 20 bps / 0 bps | honest V2↔V3 basis is tiny — the tolerance floor |
| Honest OLAS removal vs V3 seeded at the true price | 0 bps | honest flow sails through |
| **Real 50-WETH sandwich on the ~272-WETH OLAS/WETH V2 pool** | **~4007 bps (~40%)** | **cross-check reverts** |
| Unseeded OLAS/WETH V3 slot0 vs live V2 | ~9361 bps | untrustworthy reference — rejected by the 2% gate first |

Honest flow lands at 0–20 bps; a real manipulation lands ~40%. Any tolerance in the low single-digit-percent
range separates them cleanly.

## Tolerance chosen: `maxSlippage = 500` bps (5%)

There is no live OLAS V2↔V3 basis to measure (OLAS is not seeded on a V3 pool anywhere — that is exactly what
POL migration creates), so the tolerance is anchored to the fork-seeded measurements below, not derived from a
formula. The check compares the **V2 removed ratio against the V3 slot0**; their honest divergence is the
cross-pool arbitrage basis (thin for OLAS, but never exactly zero). **5%** is chosen to sit **above the measured
honest basis and below the manipulation regime** — the table is the evidence, not an additive band budget.

(The 2% `MAX_ALLOWED_DEVIATION` is *not* a term in that budget: it bounds a **different** quantity — V3 slot0
vs the V3 TWAP — so it does not add to the V2↔V3 arb basis. Its role is orthogonal: it guarantees the slot0 the
check compares *against* is itself trustworthy. See the unseeded-pool row in
`test/LiquidityManagerV2V3CrossCheckForkETH.t.sol`, which the gate rejects before the cross-check is ever
consulted.)

Measured on an ETH-fork-seeded OLAS/WETH V3 pool (`test/LiquidityManagerV2V3RatioCheckForkETH.t.sol`), a real
sandwich on the ~272-WETH V2 pool:

| WETH swapped into V2 | removed-ratio vs V3 | rejected by 500 bps? |
| --- | --- | --- |
| honest (0) | 0 bps | — |
| 5 | 371 bps | no |
| 10 | 748 bps | **yes** |
| 20 | 1523 bps | **yes** |
| 40 | 3154 bps | **yes** |

Honest flow is 0 bps; the 5% line catches sandwiches from ~7 WETH up. **Accepted residual:** the 5-WETH row
(371 bps) is *not* rejected — a cheap, sub-tolerance manipulation passes the gate. This is deliberate and safe:
by convexity the removal is still worth ≥ fair value at the true price, so a sub-5% skew is a bounded efficiency
loss, never a value loss (and it feeds the within-tolerance burn residual noted above when `olasBurnRate > 0`).
`changeMaxSlippage` allows per-chain retuning against thinner/deeper source pools.

## Affected code (implemented)

- `contracts/pol/LiquidityManagerCore.sol` — `convertToV3` passes the removed ratio + the already-computed
  `sqrtP` into the new `_checkRemovedRatioAgainstV3`; `RatioDeviation` error + `Q96` constant added.
- `contracts/pol/LiquidityManagerSourceBase.sol` — `_fairMinAmountsOut` + `oracleV2` + `IOracle` removed; now a
  thin shared base.
- `contracts/pol/LiquidityManagerSourceUniV2.sol` / `LiquidityManagerSourceBalancer.sol` — drop the `oracleV2`
  constructor arg; the removal/exit passes zero per-token floors.
- The four leaves — drop the `_oracleV2` constructor arg.
- Deploy scripts (`deploy_02_*`) — `oracleV2` constructor arg + `*PriceOracleAddress` read removed;
  `liquidityManagerMaxSlippage` set to `500` in the pol globals (re-tasked as the V2↔V3 tolerance).

This is a security-relevant change on a security-critical path; it ships with before/after fork tests across all
four source/target combinations.
