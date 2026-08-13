# LiquidityManager price-guard fix — audit-state diff

Short, tagged map of **prior audit state → new state** for the `LiquidityManagerCore` price-guard fix
(the `changeImplementation` upgrade). Companion to `docs/Vulnerabilities_list_tokenomics.md` §26 and to
the git diff. Tags let a reviewer trace each behavioural change.

**Baseline:** the prior state is the released, audited **`v1.4.3`** implementation — the tag that first
introduced `LiquidityManagerCore` (see `CHANGELOG.md`, "Added — Protocol-Owned Liquidity"), and the impl
currently behind the deployed proxies. The new state is the `changeImplementation` upgrade shipped in
**PR #306** (the first `LiquidityManagerCore` change after `v1.4.3`; `CHANGELOG.md` `[Unreleased]`). Rows
`[FIX-*]` map `v1.4.3 → shipped` and are the behavioural changes. Rows `[R4]`/`[R5]` are behaviour-preserving
robustness follow-ups from the internal audit and instead map `initial fix → shipped` (both within PR #306):
they refine mechanisms the fix itself introduced, so their "prior" column is the initial fix, not `v1.4.3`.

**Tags:** `[GUARD-FAILOPEN]` the fail-open class · `[VL#15]` / `[VL#16]` vulnerabilities-list items ·
`[FIX-1]` guard fail-closed · `[FIX-2a]` increase TWAP anchor · `[FIX-2b]` soft-priced exit floor ·
`[FIX-3]` collectFees scope-burn · `[FIX-5]` cleanup · `[R4]` fail-safe exit gate · `[R5]` shared-primitive de-dup.

| Tag | Prior state (deployed impl) | New state (upgraded impl) |
|---|---|---|
| `[GUARD-FAILOPEN][FIX-1]` (new-pool) | `checkPoolAndGetCenterPrice` returns raw `slot0` (no deviation check) on a freshly-created pool (cardinality ≤ 1) | Reverts `NotEnoughHistory`; the first seed requires a pre-warmed pool (deployment README) |
| `[GUARD-FAILOPEN][FIX-1]` (inactive) | Returns raw `slot0` on a pool with no trade in `SECONDS_AGO` (1800s) — reachable on `convertToV3` / `changeRanges` / `increaseLiquidity` / permissionless `buyBack` | Reverts `NotEnoughHistory` on the same trigger — same defect, same fix. Self-heals: one swap repopulates the buffer |
| `[FIX-2b]` | `decreaseLiquidity` gated by the shared guard; `amountMin` derived from raw `slot0` | `_decreaseLiquidity` prices the exit via `_getExitSqrtPrice`, which reverts if `slot0` is >`MAX_ALLOWED_DEVIATION` off the TWAP on a verifiable pool (anti-manipulation gate), else skips the gate (quiet / fresh), and in both cases returns raw `slot0`; `amountMin = amounts(slot0) × (1 − maxSlippage)` is computed at the same price the position manager withdraws at, so a fair exit is always satisfiable within the gate and never stale across a governance delay |
| `[VL#16][FIX-2a]` | `increaseLiquidity` / re-seed `amountMin` anchored to raw `slot0` (Low, bounded) | `_increaseLiquidity` anchors `amountMin` to the TWAP center (entry side of #16 closed; exit side improved via `[FIX-2b]`) |
| `[VL#15][FIX-3]` | `collectFees` permissionless + burns the contract's **whole** OLAS balance (Low) | Guard gate dropped; burns **only the just-collected fee** via the shared `_manageAmounts` primitive; stays permissionless |
| `[FIX-5]` | `oldestTimestamp` mislabeled; unused `_getObservationCardinality`; VL#16 / `bbb_update_options.md` claim the deviation guard runs on unverifiable pools | Renamed `latestObsTimestamp`; helper removed; doc claims corrected (VL#16 already updated; `bbb_update_options.md` at deployment) |
| `[R4]` (behaviour-preserving) | `_decreaseLiquidity(pool, id, rate, bool applyDeviationGate)` — `changeRanges` passed `false` to skip the exit gate, safe only by an unenforced caller precondition | Boolean removed; `_decreaseLiquidity` **always** runs `_getExitSqrtPrice` (fail-safe default). `changeRanges` keeps its own preceding fail-closed `checkPoolAndGetCenterPrice`, so its posture is unchanged and the now-always-on gate is only a redundant `observe` there. The "gate-off-without-validation" call is now unrepresentable |
| `[R5]` (behaviour-preserving) | `checkPoolAndGetCenterPrice` / `_getExitSqrtPrice` ~90% duplicate; `_manageUtilityAmounts` / `_manageCollectedAmounts` a byte-identical burn/transfer tail | Extracted the policy-free price compute into `_getPoolPriceFacts` (each call-site keeps its fail-open-vs-closed policy explicit, no gate-toggling flag); merged the burn/transfer tail into one `_manageAmounts` primitive |

## New behaviour to note (not a new vulnerability)

- **Quiet-pool liveness residual.** Entries/trades (`convertToV3` / `increaseLiquidity` / `changeRanges` /
  `buyBack`) revert on a pool quiet for >1800s until the next swap. Intended, self-healing, never locks
  funds; exits are unaffected (the exit gate is skipped on a quiet pool). Documented in VL#26 so it is not
  re-triaged as a DoS.
- **Extreme-move exit residual (audit M-1).** On a verifiable pool the exit deviation gate can't tell
  manipulation from genuine fast volatility, so `decreaseLiquidity` reverts while `slot0` is
  >`MAX_ALLOWED_DEVIATION` off the lagging TWAP. Funds are never at risk; retry after re-convergence.
  Accepted (POL exits are governance-timed). Documented in VL#26.
- **Deliberate entry/exit asymmetry.** Entries/trades fail-**closed** (an empty pool's `slot0` is free to
  move → catastrophic); the exit path only gates on deviation and otherwise fails-**open** on a quiet pool
  (an exit pool always holds our own liquidity → the residual is a capital-bounded slip, never the
  empty-pool catastrophe).

## Coverage / access unchanged

Storage layout unchanged → `changeImplementation` is storage-safe. All changes are function bodies, one
renamed `error`, and internal helper add/rename/param-removal (`_getPoolPriceFacts`, `_manageAmounts`, the
dropped `applyDeviationGate` param) — none occupies storage, and no state variable's slot/order/width moves.
`collectFees` and `buyBack` stay permissionless; owner-only functions unchanged. No new external attack
surface: `collectFees` consumes no price; `decreaseLiquidity` stays owner-only; the other consumers only
get stricter (fail-closed / TWAP-anchored).
