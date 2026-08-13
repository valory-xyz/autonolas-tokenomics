# Internal Audit 18 — LiquidityManagerCore price-guard fail-closed remediation

**Scope:** PR #306 (`fix/lm-price-guard-failclosed`) + PR #307 (`docs/lm-guard-deployment-runbook`),
base `main` (`029b5574`). Reviewed file: `contracts/pol/LiquidityManagerCore.sol` (production) and the
accompanying deployment runbook / audit-diff (docs). POL subsystem: `convertToV3`, `increaseLiquidity`,
`decreaseLiquidity`, `changeRanges`, `collectFees`, and the price-guard helpers
`checkPoolAndGetCenterPrice` / `getTwapFromOracle` / `_getExitSqrtPrice`, plus the permissionless
`BuyBackBurner.buyBack` V3 path that reuses the same guard.

**Verdict: PASS — 0 Critical / 0 High / 0 Medium.** 5 findings, all Info/Low, none blocking (R1–R5).
The remediation correctly converts the price guard from *fail-open* to *fail-closed* on entries and to a
*deviation-gated soft floor* on exits, closes the fee-collection scope-burn, and is storage-layout safe
for a `changeImplementation` upgrade.

---

## 1. What the change does

The pre-fix guard could, on a pool with **no verifiable 30-minute TWAP** (freshly-created /
`observationCardinality <= 1`, or inactive for more than `SECONDS_AGO = 1800 s`), fall back to the raw,
single-block-manipulable `slot0` price and size/price a value-bearing operation from it (fail-open). The
remediation:

| Change | Effect |
|---|---|
| **FIX-1** — `checkPoolAndGetCenterPrice` fail-closed | On an unverifiable pool the entry path now **reverts** (`NotEnoughHistory`) instead of returning `slot0`; when a TWAP exists it reverts if `|slot0 − TWAP| / TWAP > MAX_ALLOWED_DEVIATION` (10%) and returns the **TWAP-derived** price for minting. |
| **FIX-2a** — `_increaseLiquidity` anchor | `amountMin` and the liquidity math are anchored to the caller's TWAP center (passed as a typed parameter), not the manipulable `slot0`. |
| **FIX-2b** — `_getExitSqrtPrice` soft floor | New exit/maintenance price source: reverts on `slot0`-vs-TWAP deviation `>10%` on a **verifiable** pool, else skips the gate (fail-open) so a withdrawal is **always possible** on a quiet pool; returns raw `slot0` (the exact price the position manager withdraws at). |
| **FIX-3** — `collectFees` scope-burn | New `_manageCollectedAmounts` burns/transfers only the **just-collected** fees, not `balanceOf(this)`, so separately-staged OLAS is no longer griefable and the donation-inflation vector is closed; the guard is removed from `collectFees` (fee collection consumes no price and must stay live). |
| **FIX-5** — cleanup | Rename `oldestTimestamp -> latestObsTimestamp` (the value read is the *latest* observation, not the oldest — the old name was a misnomer) and removal of the now-unused `_getObservationCardinality` helper. |

Both halves were verified first-hand on a mainnet fork (see §6).

---

## 2. Completeness — the fix is final in its class

**Class C = "unverifiable-pool price fail-open".** A bug is in C iff it lets a value-bearing operation be
sized/priced from a pool price the contract cannot verify, such that an attacker who moves that `slot0`
shifts the operation in their favour.

**Surface closure (why the enumeration is exhaustive).** Every value-bearing op that touches a pool price
does so through exactly one of **two** internal price sources — entry/trade via `checkPoolAndGetCenterPrice`,
exit/maintenance via `_getExitSqrtPrice` (or its gate-skip twin inside `_decreaseLiquidity`, which is
dominated by a preceding `checkPoolAndGetCenterPrice` in `changeRanges`). The only `slot0` reader is
`_getPriceAndObservationIndexFromSlot0`, called **only** from those two functions. A proof that both sources
are safe on an unverifiable pool therefore covers **all** of C.

**Coverage map (each member, as shipped):**

| # | Member | Source | As-shipped |
|---|---|---|---|
| C1 | `convertToV3` first seed on a fresh pool | entry | **CLOSED** — `NotEnoughHistory` revert |
| C2 | entry on a stale/inactive matured pool | entry | **CLOSED** — inactive revert |
| C3 | permissionless `BuyBackBurner.buyBack` V3 path | entry (same guard) | **CLOSED** — inherits C1/C2/C4 |
| C4 | entry on a mature pool, single-block `slot0` push | entry | **CLOSED** — deviation gate reverts `>10%`, prices off TWAP |
| C5 | `_increaseLiquidity` `amountMin` spot-anchored | entry | **CLOSED** — anchored to TWAP center |
| C6 | `decreaseLiquidity` withdraw-sandwich | exit | **BOUNDED** — §2.1 |
| C7 | `collectFees` burn-all + donation-inflation | none (no price) | **CLOSED** — burns only collected |
| C8 | cardinality/stale liveness | entry | **ACCEPTED** self-healing residual — R1 |

C1–C5, C7 CLOSED; C6 BOUNDED; C8 ACCEPTED. No other callsite reads a pool price ⇒ the map is exhaustive.

### 2.1 The exit member C6 — bounded (soft floor vs a static minimum)

**Lemma L1 (self-defeating sandwich).** To sandwich `decreaseLiquidity`, an attacker must front-run with a
manipulation swap. That swap writes a fresh observation, so the exit's fail-open branch
(`latestObs + SECONDS_AGO < now`) no longer fires and the exit takes the `observe(1800)` path. On any pool
with `≥ SECONDS_AGO` of buffered history — which a **seeded** pool has, since seeding required
`checkPoolAndGetCenterPrice` to pass — the attacker's single-block `slot0` move is **not yet in the TWAP**
(V3 records it only on the next interaction), so `observe(1800)` returns the pre-manipulation price ⇒
deviation `> 10%` ⇒ the exit reverts. The manipulation disables the very fail-open it needs. The residual
fail-open is reachable only by (a) an honest exit on a genuinely-quiet pool (attacker-free ⇒ `slot0` is the
true price ⇒ no loss) or (b) the under-cardinality WRAP edge (R1) — in both cases a **capital-bounded** slip
against the LM's own liquidity, never the empty-pool catastrophe of C1.

A static owner-supplied `amountMin` was considered and is **inferior**: set at proposal time it is stale by
execution across the governance vote+timelock delay (too tight ⇒ DoS the legit exit after any move; too
loose ⇒ no protection). The soft floor derives at execution ⇒ never stale, always-exitable on a fair pool,
and bounds the mature-pool sandwich to the 10% gate. It dominates the static minimum on "no-stale ∧
always-exitable" while matching it on "bounded".

**Lemma L2 (V3 single-block TWAP resistance).** For a 1800 s window, a single-block `slot0` change does not
move the 30-min TWAP by `> MAX_ALLOWED_DEVIATION` unless the manipulated price is *held across* multiple
blocks (each of which the deviation gate re-checks and reverts) or the manipulation's cost against the
pool's own liquidity exceeds the extractable skew. Every member of C reduces to "single-block (caught by
the gate / not in the TWAP) or multi-block (caught per-block / uneconomic)."

**Conclusion.** There is no member of C the fix leaves OPEN. The only ways to re-open C are (a) a *new*
price-consuming callsite bypassing both guards — caught by the §1 surface-closure invariant, which the
regression suite pins — or (b) shrinking `observationCardinality` below the 1800 s span (R1, config,
self-healing, no theft).

---

## 3. No new bug — delta refutation

A fix to a fail-open guard can introduce a new bug only by (M1) locking funds, (M2) changing who may act,
(M3) requiring new ongoing discipline, or (M4) blocking an exit. The change violates none:

| Δ added | New-bug candidate | Refutation |
|---|---|---|
| New reverts `NotEnoughHistory` / deviation `Overflow` | DoS on a quiet/volatile pool | Self-healing: one swap repopulates the buffer / re-convergence clears the gate. Blocks only **entries/trades** (M4); exits unaffected on a quiet pool, only *temporarily* blocked on a genuine extreme move (M1 holds — retry). No permanent lock. |
| `_getExitSqrtPrice` soft floor | withdraw-sandwich | Refuted by L1: attacker's front-run self-defeats the fail-open; quiet residual is capital-bounded. |
| `amountMin` = `amounts(slot0)·(1−maxSlippage)` on exit | "the min protects nothing" | By design — the min is *not* the exit's manipulation defence (the deviation gate is); it only guards intra-tx price drift (nil in one atomic tx). Intended, not a regression; the gate is strictly *added* protection. |
| `collectFees` scope-burn | burns less → strands OLAS? | Strictly safer than burn-all: staged OLAS no longer griefable, donation-inflation closed. Removes value-loss, adds none; permissionless preserved (M2). |
| TWAP anchor on `_increaseLiquidity` | stricter min → DoS legit increase? | On a verifiable pool (required post-FIX-1) TWAP ≈ `slot0` within 10%, so a fair increase satisfies the min; on an unverifiable pool the entry already reverted at FIX-1. |
| `staticcall(this.getTwapFromOracle)` | reentrancy | `view` staticcall — cannot mutate state or reenter; all state-changing externals keep the single `_locked` latch. |
| new `error` + local rename | storage-layout shift → upgrade corruption | Errors/locals occupy no storage; base↔fix state-variable layout is identical (slot0 `owner`/`maxSlippage`/`_locked`, slot1 map). `changeImplementation` is storage-safe. |

Each Δ maps to a refuted candidate; no added behaviour is left unaccounted. The fix is a **conservative
delta** — it only adds reverts on unverifiable entries, tightens an anchor, narrows a burn, and adds an
always-exitable exit gate. **No new bug.**

The three non-obvious "can't-fix-both" traps are individually avoided: fail-closing the exit (would lock
funds on a quiet pool) → kept soft; bluntly ungating the exit (would make the sandwich unbounded) → kept the
deviation gate + L1; owner-gating `collectFees` (would break the permissionless model) → scoped the burn
instead.

---

## 4. Findings (all Info/Low — none blocking)

- **R1 (Low, config) — exit WRAP edge.** `_getExitSqrtPrice` falls open if `observe(1800)` reverts even
  after a swap, i.e. a pool whose `observationCardinality` is too small to span 1800 s at peak churn.
  Verify `observationCardinality` (set at deploy, bumped by the seed runbook) is sized for peak activity of
  each POL pool; assert it spans 1800 s in the runbook.

- **R2 (Low, process) — restore the skipped legacy test.** `testConvertToV3Conversion95ScanCollectFees`
  is `vm.skip`-ped because its 10% drain-swap now correctly trips the fail-closed gate — a *valid*
  invalidation, not a regression. A permanently-skipped fork test is coverage loss; restore it as a
  **pre-warmed** round-trip (convert → scan → collectFees succeeds under fail-closed).

- **R3 (Info, doc) — signature nit.** The deployment/audit-diff note types `checkPoolAndGetCenterPrice`
  as `internal`; in code it is **`public`** (it must be — `BuyBackBurner` calls it cross-contract). Correct
  the doc.

- **R4 (Info, robustness) — the `applyDeviationGate` flag is a caller-precondition trap.**
  `_decreaseLiquidity(pool, id, rate, bool applyDeviationGate)` skips the anti-manipulation gate on the
  `false` branch (raw `slot0`, no deviation check). It is safe **today** — the only `false` caller,
  `changeRanges`, pre-validates via `checkPoolAndGetCenterPrice` on the same pool in the same call, and its
  safety is asserted in a **code comment** ("the pool was just validated above"). But a comment is not a
  compiler check: a future refactor adding a `_decreaseLiquidity(..., false)` caller without that pre-check
  silently re-opens the exit fail-open, and no existing test would catch it. The flag exists only to save a
  second `observe(1800)` (gas) on a security-critical path.

  *We agree the two exit postures are needed* — a soft, always-exitable gate for the withdrawal
  (`decreaseLiquidity`) and a strict fail-closed guard for the reposition (`changeRanges`, an entry-class
  op). We object only to *encoding* that need as a boolean that switches the security gate off and is safe
  only by an unenforced precondition. **Recommended positive change (both postures preserved):** make
  `_decreaseLiquidity` always run `_getExitSqrtPrice` and delete the parameter; `changeRanges` keeps its own
  preceding fail-closed `checkPoolAndGetCenterPrice`, so its strict posture is unchanged and the now-always-on
  gate inside the decrease is only a redundant `observe` on the reposition path (gas, not risk). This makes a
  "gate-off-without-validation" call unwritable. (Equivalent alternative: pass the validated price in as a
  typed parameter — exactly what `_increaseLiquidity` already does in this same change.)

  **Discriminator (one coherent rule, applied to every flag in the file):** a flag that selects between
  *equally-safe* behaviours (e.g. `olasBurnOrTransfer` — burn OLAS vs transfer it to treasury; neither value
  is unsafe, a wrong value is a functional error caught by logic/tests) is fine. A flag that *toggles a
  security control on/off* where one branch is unsafe absent an unenforced precondition (`applyDeviationGate
  = false`) is the anti-pattern. The discriminator is fail-safe-defaults: the former is safe on either value;
  the latter defaults **open**.

- **R5 (Info, maintainability) — duplication of a security-relevant routine.** Two cases:
  (a) `_manageCollectedAmounts` (FIX-3) is a near-verbatim copy of `_manageUtilityAmounts` — identical OLAS
  ordering, burn/transfer branches and event, differing only in the source of the amounts (explicit vs
  `balanceOf * rate`). (b) more importantly, `_getExitSqrtPrice` is ~90% a copy of
  `checkPoolAndGetCenterPrice` — identical `slot0` read, inactive check, `observe` staticcall and deviation
  math, differing only in policy (entry: revert + return TWAP; exit: return raw `slot0`). A fix to the
  deviation math or the observe-failure handling in one must be mirrored to the other; a missed mirror is a
  silent inconsistency on the security-critical path. **Recommendation (reconciles with R4 — do not de-dup
  with a flag):** extract the policy-free computation (read `slot0` → check inactivity → get TWAP → return
  the facts `(slot0, twapAvailable, deviation)`) into one shared helper, and keep the fail-open-vs-closed
  policy explicit at each callsite. That removes the duplication without a security-gate-toggling boolean.
  (Minor sub-note: the OLAS leg uses plain `transfer` while the second token uses `safeTransfer` — safe
  because OLAS is trusted, but `safeTransfer` on both is the fail-safe default; pre-existing.)

**Accepted residuals (documented, self-healing, no funds at risk):** quiet-pool → entries/buyBack revert
until the next swap; a genuine extreme move → exit temporarily reverts until re-convergence. Both never lock
funds.

---

## 5. Recommendation philosophy (framing for R4/R5)

These robustness findings apply one standing lens: **security > economy; robust-and-explicit over
elegant-and-fragile.** Prefer code that fails *safe* over clever code whose correctness depends on an
invariant the compiler does not enforce. This is codified secure-design doctrine, not style — Saltzer &
Schroeder's *fail-safe defaults* (every path defaults to deny/safe) and *economy of mechanism* (small enough
to verify); the *temporal-coupling* anti-pattern ("correct only if X was called first, unenforced");
*make-illegal-states-unrepresentable* (type-driven design); and the general guidance to validate assumptions
at the point of use, not by caller convention. None of R1–R5 is a live bug; each closes a latent
robustness/maintenance gap before any future change to the POL subsystem.

---

## 6. Test artifacts (regression PoCs)

Two proof-of-concept tests accompany this audit and are intended to become part of the permanent negative-test
base (not side artifacts):

- **`LiquidityManagerPriceGuardRegression.t.sol`** (non-fork, 5/5 green) — invariants I1 (fresh pool →
  fail-closed revert), I2 (stale/inactive → fail-closed revert), I3 (entry deviation → revert), I4 (mature
  manipulated exit → deviation revert), I5 (quiet pool → always-exitable). I1/I2 provably fail against the
  pre-fix code.
- **`LiquidityManagerExitSandwichFork.t.sol`** (mainnet fork; requires an `ETH_RPC` fork URL) — seeds a real
  position, warps `SECONDS_AGO`, mocks a manipulated `slot0`, asserts `decreaseLiquidity` reverts, then a
  honest `decreaseLiquidity` succeeds. Demonstrates L1 on a live pool.

| Property | PoC | Result vs fix |
|---|---|---|
| always-exitable (M1) | `…Regression::I5` | PASS (exit returns `slot0`, no revert) |
| exit gate not bypassable | `…Regression::I4` + `…ExitSandwichFork` | PASS (revert on manipulation) |
| entry fail-closed (C1/C2/C4) | `…Regression::I1/I2/I3` | PASS (revert; I1/I2 fail on pre-fix) |
| collectFees scope-burn (C7) | dev `test_collectFees_scopesToCollectedAmounts_*` | PASS (staged untouched) |
| storage-layout equality | base↔fix state-var diff = ∅ | PASS |
| no reentrancy | `staticcall` is `view`; `_locked` latch | by construction |

If the CI has no mainnet `ETH_RPC` secret, the fork PoC must be conditionally skipped so it does not block;
the non-fork regression runs everywhere.
