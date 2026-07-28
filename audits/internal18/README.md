# Internal Audit 18 — autonolas-tokenomics (Dispenser rework — releasing audit)

**Audit date**: 2026-07-27
**Audited change**: the Dispenser-rework PR stack **#309 → #310 → #311** (clean stack over `main` `029b557`):
- **#309** `refactor/dispenser-proxy` (`22f5352`) — put the `Dispenser` behind a `DispenserProxy`.
- **#310** `fix/dispenser-vuln-fixes` (`c60fbe5`, stacked on #309) — `Vulnerabilities_list_tokenomics.md` items **#8, #9, #12, #25**.
- **#311** `fix/l2-migrate-withheld` (`396e0a5`, stacked on #310) — item **#10** (`DefaultTargetDispenserL2.migrate()`).

**Deployment status**: pre-deploy. The three PRs are open; deploy scripts + fork tests are a separate follow-up (PR-D) and are **not** in this stack.
**Auditor**: audit-claude
**Scope of change** (release unit = cumulative diff `main..396e0a5`): 3 production contracts —
`contracts/Dispenser.sol` (+157/−104 net over the stack), `contracts/proxies/DispenserProxy.sol` (new, 68 LOC), `contracts/staking/DefaultTargetDispenserL2.sol` (+10/−2). No other production contract changed; no deploy script changed.

## Verdict

**GREEN-LIGHT the code — CONDITIONAL on PR-D before the on-chain deploy.**

All five vuln-list items (#8/#9/#10/#12/#25) are correctly closed, the proxy refactor is behaviour-preserving, and no regression was found. The contract changes are sound to merge. The **on-chain deployment**, however, should wait on the planned **PR-D** (deploy scripts + an L1 mainnet-fork test of the proxied claim path), because the constructor/`initialize` signatures changed and none of that deploy machinery is present or exercised yet (§5).

## Method (everything verified first-hand)

Built the release tree with Foundry, ran the Dispenser test suites, traced the staking-incentive accounting by hand across both claim paths, recomputed the proxy storage slot, and swept every changed signature for downstream callers. `forge test --mc Dispenser` on the release head: **17/17** (DispenserProxy 9, DispenserFixes 5, Dispenser 3); committed tree compiles clean.

## 1. #309 — proxy refactor: behaviour-preserving

The `main → #309` diff is **plumbing only** — new errors/events, storage-declaration moves, `constructor → initialize` split, `changeImplementation`, and the `changeManagers` signature. **No `claim` / nominee / `calculateStakingIncentives` / withheld / checkpoint logic is touched**, so the "no behavior change" claim holds by inspection.

Proxy security (`DispenserProxy.sol` + the implementation's `initialize`/`changeImplementation`):

- **Implementation slot.** `PROXY_DISPENSER = keccak256("PROXY_DISPENSER") = 0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83` — recomputed and confirmed. Both the proxy `fallback` (`sload`) and `changeImplementation` (`sstore`) use this exact constant, so the read and write slots agree — the upgrade path is self-consistent. The slot is a pseudo-random high slot and cannot collide with the sequential Dispenser storage.
- **Constructor / init.** The `DispenserProxy` constructor rejects a zero implementation and empty init-data, then `delegatecall`-s the implementation's `initialize`, reverting on failure. `initialize` is guarded by `owner != address(0) → AlreadyInitialized`; `owner` is set to the deployer atomically inside that constructor delegatecall, so there is **no front-run window** on the live proxy.
- **`changeImplementation`.** Owner-gated (`OwnerOnly`), zero-checked, writes the slot, emits `ImplementationUpdated`.
- **Storage.** Marked `frozen append-only`. Moving `tokenomics` from storage to an implementation immutable shifts slot indices, which is safe here **because this is a greenfield proxy deployment**, not an upgrade over pre-existing storage. This is a deploy-runbook invariant (never point the proxy at an old storage image) and is called out again in §5.
- **Tests.** `DispenserProxy.t.sol` (9/9) covers the constructor guards, proxy re-init AND implementation-direct re-init reverts, owner/zero guards on `changeImplementation`, and an upgrade that swaps logic while preserving state.

Two informational notes (no action required):
- `changeImplementation` asserts non-zero but not is-contract — this matches the sibling proxies (`LiquidityManagerCore`, `BuyBackBurner`), so it is a consistent owner-trusted convention.
- The standalone implementation can be `initialize`-d by anyone in its own storage (the standard UUPS "uninitialized implementation" consideration); it is harmless here because the implementation has no `selfdestruct` or arbitrary `delegatecall`, and the direct-reinit revert is tested.

## 2. #310 — vuln-list fixes: correct, no regression

Each fix was checked against the intended remediation in `Vulnerabilities_list_tokenomics.md` and traced for double-refund / missing-refund on both the single and batch claim paths.

- **#12 (High).** `calculateStakingIncentives` now writes the one-way `mapZeroWeightEpochRefunded[j]` flag **and** calls `Tokenomics.refundFromStaking(...)` atomically in the same call, and the zero-weight amount is dropped from `totalReturnAmount`. Trace:
  - single `claimStakingIncentives`: refunds `returnAmount` (non-zero-weight returns) and `withheldUsed` separately; zero-weight is already refunded inline inside `calculateStakingIncentives`.
  - batch `_calculateStakingIncentivesBatch`: aggregates non-zero-weight returns + `withheldUsed` into `totalAmounts[2]` and refunds once; zero-weight is again refunded inline per target.
  Every `refundFromStaking` sum is disjoint — **no double-count and no missing refund**. `Tokenomics.refundFromStaking` is `dispenser`-gated with a `uint96` overflow check, so the now-reachable "public state-mutating call performs the refund" path is authorized and bounded (once per epoch via the flag). `calculateStakingIncentives` has only the two internal state-mutating callers (no on-chain `staticcall` consumer), so the added external call breaks no preview path.
- **#9 (Low).** The withheld-covered portion (`withheldUsed`, paid from OLAS already minted under a previous allocation) is returned to staking inflation on both paths — disjoint from the other refunds.
- **#25 (Informative).** `delete mapRemovedNomineeEpochs[nomineeHash]` in `addNominee` (option (a) from the vuln-list note) — a no-op on a first-time add, and it unblocks a remove→re-add lifecycle. The Dispenser no longer depends on upstream VoteWeighting enforcing "remove is final", which matters now that `changeManagers` can repoint `voteWeighting`.
- **#8 (Informative).** The `voteWeighting` swap in `changeManagers` now requires `StakingIncentivesPaused` / `AllPaused`. Deploy-time wiring is unaffected because `voteWeighting` is set in `initialize`, not `changeManagers`.

`DispenserFixes.t.sol` is **5/5** on this branch. The suite is written against the new `Unpaused` error / 2-arg `changeManagers`, so it is tightly coupled to the fixes — a good indication it exercises the changed behaviour rather than passing vacuously.

## 3. #311 — item #10: event-only

`DefaultTargetDispenserL2.migrate()` now emits `withheldAmount` alongside the migrated OLAS balance. The value is the current storage `withheldAmount` — the exact amount the DAO must restore via `updateWithheldAmountMaintenance()` on the new dispenser. The fund transfer, owner-zeroing and permanent lock are unchanged, and the change lives in the abstract base so all chain variants (Arbitrum / Gnosis / Optimism / Polygon) inherit it. **Operational note:** the 4-argument `Migrated` is an ABI change — any off-chain indexer / migration tooling parsing the previous 3-argument signature must be updated.

## 4. Regression sweep

- **Signature changes.** `Dispenser.changeManagers` (3→2 args) and the new `Dispenser` constructor signature are not called by any deployment or proposal script — those scripts call `changeManagers` on `Tokenomics` / `Treasury` (unchanged), not on the Dispenser. No script or on-chain caller breaks.
- **Build.** The committed release tree compiles clean.

## 5. Deploy readiness — the release condition

The constructor now takes five bytecode immutables and `initialize` is new, so the deploy order inverts (Tokenomics proxy → Dispenser implementation + proxy → repoint). The implementation itself documents that **"a wrong constructor immutable silently rewires the proxy"** — i.e. the deploy arguments are safety-critical and, as of this stack, **unaudited**. Therefore the on-chain deploy green-light requires the planned **PR-D**:

1. Foundry/hardhat deploy scripts for the Dispenser implementation + `DispenserProxy` (correct immutables + `initialize` args), reviewed.
2. An **L1 mainnet-fork test of the proxied claim path** against the real Tokenomics / Treasury / deposit-processor wiring (the current unit tests use mocks).
3. Off-chain tooling updated for the 4-argument `Migrated` event.

## 6. Note on Immunefi 85857

`#311` touches the same contract as Immunefi report **85857** (`redeem()` not re-verifying a since-removed staking target), but does **not** address it. 85857 has been finalized **BY-DESIGN / Informational, no change** — the allocation's validity is fixed at the epoch it was funded, and a nominee de-authorized on L1 never has its emissions forwarded to the L2 queue in the first place, so there is no reclaimable amount stranded there. Nothing is owed here on that axis.

## Compliance summary

| Item | Severity (vuln-list) | Fix location | Verdict |
|---|---|---|---|
| #8 changeManagers voteWeighting | Informative | #310 `changeManagers` pause-gate | ✔ correct |
| #9 withheld reuse inflation accounting | Low | #310 both claim paths | ✔ correct |
| #10 migrate withheldAmount visibility | Low | #311 `Migrated` event | ✔ correct (event-only) |
| #12 zero-weight refund atomicity | High | #310 `calculateStakingIncentives` | ✔ correct (atomic; no double-refund) |
| #25 addNominee removed-epoch clearing | Informative | #310 `addNominee` | ✔ correct |
| Proxy refactor (#309) | — | new `DispenserProxy` + `initialize`/`changeImplementation` | ✔ behaviour-preserving; upgrade path consistent |
| Regression | — | changed signatures | ✔ no script/caller breaks; tree compiles |
| Deploy readiness | — | — | ⚠ conditional on PR-D (deploy scripts + L1 fork test) |
