# LiquidityManager price-guard fix — audit-state diff

Short, tagged map of **prior audit state → new state** for the `LiquidityManagerCore` price-guard fix
(the `changeImplementation` upgrade). Companion to `docs/Vulnerabilities_list_tokenomics.md` §26 and to
the git diff. Tags let a reviewer trace each behavioural change.

**Tags:** `[GUARD-FAILOPEN]` the fail-open class · `[VL#15]` / `[VL#16]` vulnerabilities-list items ·
`[FIX-1]` guard fail-closed · `[FIX-2a]` increase TWAP anchor · `[FIX-2b]` soft-priced exit floor ·
`[FIX-3]` collectFees scope-burn · `[FIX-5]` cleanup.

| Tag | Prior state (deployed impl) | New state (upgraded impl) |
|---|---|---|
| `[GUARD-FAILOPEN][FIX-1]` (new-pool) | `checkPoolAndGetCenterPrice` returns raw `slot0` (no deviation check) on a freshly-created pool (cardinality ≤ 1) | Reverts `NotEnoughHistory`; the first seed requires a pre-warmed pool (deployment README) |
| `[GUARD-FAILOPEN][FIX-1]` (inactive) | Returns raw `slot0` on a pool with no trade in `SECONDS_AGO` (1800s) — reachable on `convertToV3` / `changeRanges` / `increaseLiquidity` / permissionless `buyBack` | Reverts `NotEnoughHistory` on the same trigger — same defect, same fix. Self-heals: one swap repopulates the buffer |
| `[FIX-2b]` | `decreaseLiquidity` gated by the shared guard; `amountMin` derived from raw `slot0` | Guard gate dropped; `amountMin` derived at execution from `_getExitSqrtPrice` (TWAP when verifiable with slot0 bounded to it, else slot0 fail-open) × `(1 − maxSlippage)`. Always-exitable on a quiet pool, deviation-bounded on a mature pool, never stale across a governance delay |
| `[VL#16][FIX-2a]` | `increaseLiquidity` / re-seed `amountMin` anchored to raw `slot0` (Low, bounded) | `_increaseLiquidity` anchors `amountMin` to the TWAP center (entry side of #16 closed; exit side improved via `[FIX-2b]`) |
| `[VL#15][FIX-3]` | `collectFees` permissionless + burns the contract's **whole** OLAS balance (Low) | Guard gate dropped; burns **only the just-collected fee** via `_manageCollectedAmounts`; stays permissionless |
| `[FIX-5]` | `oldestTimestamp` mislabeled; unused `_getObservationCardinality`; VL#16 / `bbb_update_options.md` claim the deviation guard runs on unverifiable pools | Renamed `latestObsTimestamp`; helper removed; doc claims corrected (VL#16 already updated; `bbb_update_options.md` at deployment) |

## New behaviour to note (not a new vulnerability)

- **Fail-closed liveness residual.** Entries/trades (`convertToV3` / `increaseLiquidity` / `changeRanges` /
  `buyBack`) revert on a pool quiet for >1800s until the next swap. Intended, self-healing, never locks
  funds, and **exits always work** (`[FIX-2b]`). Documented in VL#26 so it is not re-triaged as a DoS.
- **Deliberate entry/exit asymmetry.** Entries/trades fail-**closed** (an empty pool's `slot0` is free to
  move → catastrophic); the exit path fails-**open**-soft (an exit pool always holds our own liquidity →
  the residual is a capital-bounded slip, never the empty-pool catastrophe).

## Coverage / access unchanged

Storage layout unchanged (function bodies + one `error` only) → `changeImplementation` is storage-safe.
`collectFees` and `buyBack` stay permissionless; owner-only functions unchanged. No new external attack
surface: `collectFees` consumes no price; `decreaseLiquidity` stays owner-only; the other consumers only
get stricter (fail-closed / TWAP-anchored).
