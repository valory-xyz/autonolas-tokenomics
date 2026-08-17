# V2 → V3 Liquidity Migration Runbook

Procedure for migrating Protocol-Owned Liquidity (POL) from a V2 pool (Uniswap V2 on Ethereum;
Balancer WeightedPool on Base / Optimism) into a Uniswap V3 / Velodrome Slipstream
concentrated-liquidity position, using the `LiquidityManager*` contracts behind
`LiquidityManagerProxy`.

> Companion docs: [`scripts/deployment/pol/README.md`](../scripts/deployment/pol/README.md)
> (contract deployment, the `changeImplementation` upgrade, and V3 wiring),
> [`lm_price_guard_audit_diff.md`](./lm_price_guard_audit_diff.md) (the price-guard fix),
> [`Vulnerabilities_list_tokenomics.md`](./Vulnerabilities_list_tokenomics.md) items #14 (Balancer
> spot-oracle steerability, accepted residual) and #26 (price-guard fail-closed).

The migration entry point is the owner-only call
`LiquidityManagerCore.convertToV3(tokens, v2Pool, feeTierOrTickSpacing, tickShifts, olasBurnRate, scan)`
(`contracts/pol/LiquidityManagerCore.sol`). It removes V2 liquidity, then mints / increases the V3
position, sweeping leftovers to the treasury.

> **Precondition — deploy the fixed implementation first.** The V3-mint price guard is **fail-closed**:
> `checkPoolAndGetCenterPrice` reverts `NotEnoughHistory` when the target pool cannot produce a
> verifiable 30-minute TWAP (a brand-new pool with no observation history, or one with no trade in the
> last 1800s). So the target pool must be **pre-warmed** (§3, §5) before the first `convertToV3`, and the
> fixed `LiquidityManager*` implementation must be live on the proxy (`changeImplementation`, see the
> deployment README) **before** any POL is seeded.

---

## 1. Migration procedure

### 1.1 Mainnet (Ethereum, Uniswap V2 → Uniswap V3)

1. **No source oracle to deploy.** The V2 exit passes zero per-token floors; source-pool manipulation is
   gated in `convertToV3` by the V2↔V3 ratio cross-check (§3), so there is no `UniswapPriceOracle` to
   deploy or warm for the migration.
2. **Create and initialize the V3 pool ahead of time** (≥10 days), initialized at the actual V2
   reserves / current price.
3. **Pre-warm the V3 pool** (§5): add real wide-range liquidity and let arbitrage / trades populate the
   pool's built-in observation history. This is required for the fail-closed mint-side TWAP guard (§3).
4. **Deploy `LiquidityManagerUniV2UniV3` + `LiquidityManagerProxy`; set Timelock as owner** (or, on the existing
   proxies, upgrade to the fixed impl via `changeImplementation`, deployment README). **Either way, proxy
   ownership must be the Timelock before any POL is seeded** — the EOA-ownership is justified only while POL
   is not operational (seeding makes the LM custodial), and this is exactly what the "inert to non-owners,
   owner is the DAO" safety framing and VL#26's "no funds at risk" rest on.
5. **Transfer V2 LP from Treasury → LiquidityManager** (DAO vote: `Treasury.withdraw(LM, amount, pair)`) —
   only after step 4's ownership handover to the Timelock.
6. **`convertToV3(...)`** with tick shifts defined from the actual center price (DAO).

### 1.2 Base and other L2s (Balancer → Slipstream / Uniswap V3)

1. **No source oracle to deploy or warm.** The Balancer exit passes zero per-token floors; source-pool
   manipulation is gated in `convertToV3` by the V2↔V3 ratio cross-check (§3). There is no
   `BalancerPriceOracle` deploy or warm-up on the migration path anymore.
2. **Create and initialize the V3 pool ahead of time** (≥10 days) at the actual V2 reserves / current
   price.
3. **Pre-warm the V3 pool** (§5) — build observation history and keep the price correct via arbitrage.
4. **Deploy `LiquidityManagerBalancerSlipstream` + `LiquidityManagerProxy`; set the chain's `BridgeMediator` as
   owner** (or upgrade the existing proxy to the fixed impl). **Ownership must be the `BridgeMediator`
   before seeding (step 5)** — same reason as §1.1: seeding makes the LM custodial, so it cannot land in an
   EOA-owned proxy.
5. **Transfer V2 LP from Treasury → LiquidityManager via the Wormhole Token Bridge** — Timelock-direct,
   `value 0`, `l2Recipient = LiquidityManagerProxy`; redeem the VAA on L2 (§2).
6. **`convertToV3(...)`** with tick shifts from the actual center price (DAO on L2).

---

## 2. Transferring V2 LP from Treasury (L1) → LiquidityManager (L2)

LP tokens bridged back to their origin L2 (Optimism, Base, Celo) travel via the Wormhole **Token
Bridge**. The transfer is **free and Timelock-direct** — no relayer wrapper. Cost is the Wormhole Core
`messageFee()`, which is **0** on Ethereum L1 today
(`cast call 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B "messageFee()(uint256)"` → `0`); with
`arbiterFee = 0` every call is `value 0`.

> `messageFee()` is a Wormhole-governance-settable parameter — re-check it at execution time and set
> `msg.value` accordingly in the unlikely event it is ever non-zero.

### Workflow

1. **L1 — one DAO proposal; Timelock batches (all `value 0`):**
   ```
   Treasury.withdraw(Timelock, amount, lpToken)         # release wrapped LP to the executor
   lpToken.approve(wormholeTokenBridge, amount)
   wormholeTokenBridge.transferTokens(                  # burns wrapped LP on L1, emits a VAA
       lpToken, amount, l2WormholeChainId,
       bytes32(l2Recipient), 0 /*arbiterFee*/, nonce)
   ```
2. **L2 — redeem the VAA (permissionless):** anyone calls `completeTransfer(vaa)` on the L2 Token
   Bridge, releasing the native L2 LP (the Balancer BPT) to `l2Recipient`. No governance, no fee, no
   `msg.value` matching.
3. **L2 — one DAO proposal converts:** the L2 `BridgeMediator` (the LM owner) calls
   `LiquidityManagerProxy.convertToV3(...)`.

### Set `l2Recipient = LiquidityManagerProxy` (bridge straight to the LM)

`completeTransfer` is a plain ERC20 credit — it does not call the recipient — so the LP can land
directly in the `LiquidityManagerProxy`, and step 3 is a single `convertToV3` call with no intermediate
`BridgeMediator → LM` transfer. This is safe:

- **Inert to non-owners while idle:** every value-moving LM function (`convertToV3`, `increaseLiquidity`,
  `transferToken`, …) is `onlyOwner`, and the owner is the L2 `BridgeMediator`.
- **Fully rescuable:** if the migration must be aborted or redirected, the `BridgeMediator` (owner) pulls
  the LP back out via `LiquidityManagerCore.transferToken(lpToken, to, amount)`.

Routing through the `BridgeMediator` first also works but only adds a hop — prefer direct-to-LM.

---

## 3. Price guards and the pre-warm prerequisite

For a `convertToV3` tx to succeed, **both** the V2 pool (migrated *from*) and the V3 pool (migrated *to*)
must be verifiable and un-manipulated at execution time. The contract enforces this with **two
independent guards**:

| Leg | Where | Oracle used | Mechanism |
|---|---|---|---|
| **V2 exit** | `_checkTokensAndRemoveLiquidityV2` (`LiquidityManagerUniV2UniV3.sol` / `LiquidityManagerBalancerSlipstream.sol`) | none (source oracle removed) | The exit passes **zero per-token floors** (a proportional removal cannot lose value — convexity). Source-pool manipulation is instead gated in `convertToV3`, which cross-checks the removed token ratio against the gate-verified V3 `slot0` and reverts `RatioDeviation` when it diverges by more than `maxSlippage`. |
| **V3 mint** | `checkPoolAndGetCenterPrice` (`LiquidityManagerCore.sol`) | The V3 pool's own built-in `observe()` TWAP | **Fail-closed:** reverts `NotEnoughHistory` if the pool cannot produce a 30-minute TWAP; otherwise reverts `Overflow` if the instantaneous `slot0` price deviates from the TWAP by more than `MAX_ALLOWED_DEVIATION`; mints at the TWAP-derived sqrt price. |

The two bounds are **no longer mirrored**, and deliberately so. `MAX_ALLOWED_DEVIATION` (pre-flight,
price space) is the anti-manipulation gate and is now the *sole* entry defence; the deploy-time
`maxSlippage` (post-flight, amount space) no longer backstops entries at all, because #306 re-anchored
`amount{0,1}Min` to `slot0` — the exact price the NPM executes at — which makes that check vacuous by
construction. Its live role is now the **V2↔V3 ratio tolerance** in `convertToV3`'s source cross-check
(the former source-side exit floor and its oracle were removed); tightening it to "match" the gate would
risk reverting legitimate exits on a shallow source pool for no gain.

Mirroring them was the earlier guidance, and it was unsound even then: a price-space tolerance does not
map to an equal amount-space tolerance, and the gap widens as the tick range narrows. Anchoring the floor
to the TWAP while the NPM minted at `slot0` opened an in-gate dead band where the pre-flight guard accepted
a mint the amount-min check then rejected (internal20 finding #306.1). Do not re-couple them.

### 3.1 The pre-warm is a functional prerequisite (all chains)

Because the V3-mint guard is **fail-closed**, the first `convertToV3` into a pool that cannot produce a
verifiable TWAP **reverts** (`NotEnoughHistory`). So a pool that is brand-new (no observation history) or
quiet (no trade within `SECONDS_AGO` = 1800s) cannot be seeded until it is warmed. This is not a
mitigation for a defect — it is how the fixed contract works, and it means a manipulated empty pool can
never be seeded at a bad price (the guard refuses). Before the first seed on any chain:

1. **Pre-seed real wide-range liquidity ≥10 days ahead** (§5) and let arbitrage stabilize the price.
   Once the pool holds real liquidity, `slot0` is no longer free to move — manipulation needs real
   capital and is arbitraged back.
2. **Warm the observation buffer.** A mint or swap does not grow cardinality while `cardinalityNext == 1`,
   so call `increaseObservationCardinalityNext(N)` **as its own tx, ahead of time**, then let
   observations fill via trading. Immediately before converting, confirm off-chain that:
   - `observe([1800, 0])` succeeds,
   - the latest observation is younger than 1800s (else the guard has no *recent* anchor and reverts),
   - the buffer actually spans ≥ 1800s (`N` large enough for the pool's peak trade rate; an undersized
     `N` on a busy pool wraps the ring inside the window and `observe` reverts).

   With the pool warm, the guard runs: a seed whose `slot0` is within `MAX_ALLOWED_DEVIATION` of the TWAP
   mints at the TWAP price; a larger deviation reverts.

   Sizing `N` for **peak** churn is a **hard release gate**, not just a mint prerequisite. An undersized
   buffer that later wraps below 1800s makes the *mint* fail closed (safe — it refuses), but it also makes the
   **exit** deviation gate fail *open*: `observe(1800)` reverting sends `_getExitSqrtPrice` to raw `slot0` with
   no gate, so a sandwich can move the exit price. Crucially, a front-run swap re-activating the pool does
   **not** rescue this branch (writing an observation shortens the buffer's span, it does not extend it) —
   unlike the inactive-pool fail-open, which is self-defeating for an attacker. So `N` must cover the pool's
   peak swap rate before any POL is seeded, and the buffer-span check is a release gate per pool, not a
   one-time confirmation.

3. **Optional defense-in-depth — submit privately where available.** On **ETH (L1)** the seed can be
   submitted through a builder/private relay so it is not exposed to public-mempool ordering. On
   **L2 (OP-stack)** a Timelock-triggered `convertToV3` runs as a deterministic deposit transaction with
   no private path, but OP-stack has no public L2 mempool, so the only exposure is the L1 trigger. With
   the pre-warm in place (steps 1–2) the pool is not manipulable for free and any move beyond
   `MAX_ALLOWED_DEVIATION` reverts, so the residual on L2 is at most griefing (forced reverts, which merely
   delay the migration) or a slip bounded by that same gate — never a catastrophic mis-seed.

### 3.2 Source-side residual (V2↔V3 ratio cross-check)

The source oracle is gone; source-pool manipulation is now gated in `convertToV3` by cross-checking the
removed token ratio against the gate-verified V3 `slot0` (`_checkRemovedRatioAgainstV3`), reverting
`RatioDeviation` beyond `maxSlippage` (default 5%). A proportional removal cannot lose value at the true
price (constant-product convexity), so the only residual is a **within-tolerance skew**: a sub-`maxSlippage`
manipulation passes the gate and, with a non-zero `olasBurnRate`, skews the burned OLAS by up to `maxSlippage`
at swap-fee cost — bounded and value-safe, tracked in `docs/lm_source_crosscheck_design.md`. Controls:

- **`convertToV3` is owner-only** — an attacker cannot trigger it; the only vector is front-running /
  sandwiching the governance migration tx.
- **Submit the conversion via a private mempool / builder bundle** where available, and rely on OP-stack's
  absence of a public mempool otherwise, so the migration tx is not exposed to public-mempool sandwiching.
- **Off-chain pre-flight:** immediately before submitting, assert the source-pool spot ratio agrees with the
  V3 `slot0` within `maxSlippage` (otherwise `convertToV3` reverts `RatioDeviation`); abort otherwise.

### 3.3 Uniswap V3 `initialize()` front-run

A created-but-uninitialized Uniswap V3 pool can be initialized by anyone with arbitrary values (known
Uniswap design). Create + initialize the V3 pool **atomically** (or back-to-back from the same sender) so
no one can race the `initialize()` and set a wrong price. On ETH do it in a private bundle; on L2 the
create/init/pre-seed is done by a native-L2 actor during prep, where OP-stack's absence of a public
mempool already makes it effectively private.

---

## 4. Source oracle warm-up — no longer applicable

Earlier revisions warmed a per-chain source oracle (`UniswapPriceOracle` / `BalancerPriceOracle`) that the
V2/Balancer exit read via `getTWAP()`. That oracle has been **removed**: the exit passes zero per-token
floors, and source-pool manipulation is gated by the in-contract V2↔V3 ratio cross-check (§3), which needs
no external oracle and no warm-up. The only history the migration still builds is the **V3 pool's own**
observation buffer for the mint-side fail-closed guard — covered in §5, not here.

---

## 5. Pre-seed: making the V3 pool "live" before migration

After creation/initialization (§1), seed the pool so the market maintains its price and the V3 built-in
oracle accrues history ahead of the real migration (this is the *V3-mint* guard's history; there is no
separate source-side oracle to warm — the V2 exit is gated by the ratio cross-check, §3):

- **Add a small, very-wide-range position** — e.g. ~1–5 ETH-equivalent of value, range roughly
  `[tick − 200000, tick + 200000]` (near full-range).
- **Get the pool indexed by aggregators** — one small test swap is usually enough for the pool to appear
  in 1inch / Paraswap / Uniswap UI routes.
- After that the V3 price is maintained by arbitrage, and the built-in oracle fills its observation
  buffer (bumped via `increaseObservationCardinalityNext`, see the `observationCardinality` notes in the
  deployment README).

---

## 6. Quick checklist (per chain, before submitting `convertToV3`)

- [ ] **Fixed `LiquidityManager*` implementation live on the proxy** (`changeImplementation`) — before any
      seed.
- [ ] V3 pool created + initialized ≥10 days prior at the true price (all chains, incl. ETH).
- [ ] **Pre-warm (1) — pool not empty:** pre-seeded with real wide-range liquidity (§5), indexed by
      aggregators, price stabilized by arbitrage.
- [ ] **Pre-warm (2) — guard verifiable at seed time:** `increaseObservationCardinalityNext(N)` called as
      its own tx ahead of time; `observe([1800, 0])` returns a TWAP, the latest observation is younger
      than 1800s, and the buffer spans ≥ 1800s. (Otherwise `convertToV3` reverts `NotEnoughHistory`.)
- [ ] **Optional (3) — private submission:** ETH — `convertToV3` via a private bundle; L2 — rely on the
      absence of a public mempool (no private path via Timelock; the pre-warm carries the risk).
- [ ] `LiquidityManager*` deployed; owner = Timelock (ETH) / `BridgeMediator` (L2).
- [ ] V2 LP transferred Treasury → LiquidityManager (ETH: `Treasury.withdraw`; L2: Wormhole Token Bridge
      `transferTokens` `value 0` to `l2Recipient = LiquidityManagerProxy`, VAA redeemed).
- [ ] `maxSlippage` set to 5% (`500` bps) on the proxy. (Sized as the **V2↔V3 ratio-cross-check tolerance** —
      deliberately *not* matched to `MAX_ALLOWED_DEVIATION`; see the note above.)
- [ ] Off-chain pre-flight: source-pool spot ratio agrees with the V3 `slot0` within `maxSlippage`
      (otherwise `convertToV3` reverts `RatioDeviation`) — §3.2.
- [ ] `convertToV3(...)` submitted with tick shifts from the actual center price.
