# LiquidityManager source-side manipulation gate — oracle → V3-slot0 cross-check (issue #324)

This note captures the design that lets the LiquidityManager drop its per-chain source-side TWAP oracle
(`oracleV2`) without losing a manipulation gate on the V2/Balancer `removeLiquidity` path. It is the design
half of issue **#324**; the measurement half is the fork prototype
`test/LiquidityManagerV2V3CrossCheckForkETH.t.sol`.

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
rate of the removed OLAS *before* the mint — irreversibly, where leftovers are merely parked. The conclusion
(no value loss) still holds, for a reason worth stating explicitly rather than leaving implicit: once the
cross-check exists it reverts the whole transaction, which unwinds the burn atomically, so placing the gate
*after* the burn is safe. What it does **not** unwind is a *within-tolerance* skew — at a 5% tolerance a
manipulator can shift the burned OLAS by up to ~5% at swap-fee cost, bounded and value-safe by convexity but
real, and more relevant the larger the migration's `olasBurnRate`. An **accepted residual**, recorded here
rather than left for a future reader to find the burn step unconsidered.

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

## Tolerance sizing — the one thing to measure before shipping

The deep-pair basis (≤20 bps) is a *lower bound*. OLAS pools are thinner, so their honest V2↔V3 basis will sit
above that. Before committing the production tolerance, measure the **real OLAS V2↔V3 basis once the target V3
pool is seeded** (i.e. after the migration's own pre-warm), and set `maxSlippage` above that honest basis with
margin, but well below the manipulation regime (whole percent). This is the same class of tuning the current
`maxSlippage` already required.

## Affected code (when implemented)

- `contracts/pol/LiquidityManagerCore.sol` — `convertToV3` would pass the already-computed `sqrtP` into the
  source-side check.
- `contracts/pol/LiquidityManagerSourceBase.sol` — `_fairMinAmountsOut` (+ `oracleV2`) replaced by the ratio
  cross-check; `IOracle` import dropped.
- `contracts/pol/LiquidityManagerSourceUniV2.sol` / `LiquidityManagerSourceBalancer.sol` — call sites updated.
- Deploy globals / scripts — `uniswapPriceOracleAddress` / `balancerPriceOracleAddress` / `oracleV2` constructor
  arg retired; `liquidityManagerMaxSlippage` retained (re-tasked).

This is a security-relevant change on a security-critical path — it needs review + before/after fork tests, per
#324.
