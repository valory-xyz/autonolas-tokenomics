# Autonolas Tokenomics — Internal Audit: Dispenser default-staking-param cleanup (internal19)

Releasing-audit review of **PR #314**
(`refactor(Dispenser): drop default staking-param fallback + obsolete changeStakingParams`),
head `refactor/dispenser-drop-default-staking-params` @ `86b35bf`, base
`test/dispenser-deploy-forktest` @ `4fb597b`. Follow-up cleanup to the Dispenser-proxy rework
(internal18) addressing the #309 review comments. Reviewed by hand + grounded on live mainnet.

**Verdict: GREEN-LIGHT — no blocking finding.** The removals are safe cleanup: the deleted
fallback is provably dead code on the live system, and no storage slot, live caller, or
custody path is affected. One Informational observation (make the now-implicit cross-contract
invariant explicit).

## Scope

| File | Change |
|---|---|
| `contracts/Dispenser.sol` | +5 / −57 — remove `defaultMin/MaxStaking*` immutables + claim-time fallback; remove `changeStakingParams` + event; constructor 5→3 args; pragma 0.8.30 |
| `contracts/proxies/DispenserProxy.sol` | +2 / −1 — pragma 0.8.30 + co-author only |
| `scripts/deployment/deploy_07a_dispenser.sh` | constructor args 5→3 |
| `test/*` (6 files) | updated for the 3-arg constructor; dropped the removed-setter test; re-exercise `Overflow` via a `(1,1)` bounds instance |

## 1. Remove `defaultMinStakingWeight` / `defaultMaxStakingIncentive` + claim-time fallback — SAFE

The removed block, in the staking-incentive claim loop:
```solidity
if (stakingPoint.stakingFraction > 0) {
    if (stakingPoint.minStakingWeight == 0 && stakingPoint.maxStakingIncentive == 0) {
        stakingPoint.minStakingWeight  = uint16(defaultMinStakingWeight);
        stakingPoint.maxStakingIncentive = uint96(defaultMaxStakingIncentive);
    }
} else { continue; }
```
collapses to `if (stakingPoint.stakingFraction == 0) continue;`. The fallback fires only in the
state `stakingFraction > 0 && minStakingWeight == 0 && maxStakingIncentive == 0`. That state is
**unreachable on the live Tokenomics** — verified three ways:

- **`Tokenomics.changeStakingParams` rejects zero** for both params
  (`Tokenomics.sol:767` — `if (_maxStakingIncentive == 0 || _minStakingWeight == 0) revert ZeroValue();`),
  so neither can ever be *set* to zero while the staking system is active.
- **Epoch settlement carries the values forward unconditionally.** At checkpoint, when staking
  params were not re-requested, `mapEpochStakingPoints[eCounter+1].{max,min}` are copied straight
  from `[eCounter]` (`Tokenomics.sol:1236–1237`, the `else` branch). So once non-zero, they stay
  non-zero in every subsequent epoch.
- **On-chain, live Tokenomics proxy `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300`** (read 2026-08-04,
  epochCounter = 46): epochs 44/45/46 each report `stakingFraction = 75`,
  `maxStakingIncentive = 60000e18`, `minStakingWeight = 50` — all non-zero. The fallback trigger
  is absent and, by the two invariants above, cannot arise going forward.

**Blast radius if the invariant were ever broken (defense-in-depth check).** Downstream,
`minStakingWeight` is a *threshold* (`Dispenser.sol:1018` — `if (stakingWeight < minStakingWeight * 1e14)`),
not a divisor, and `maxStakingIncentive` is a *cap* (`:1028`). So a hypothetical
`min == 0 && max == 0` state would make the min-weight gate permissive **but** cap
`availableStakingAmount` at 0 → **zero incentives distributed** — no division-by-zero, no DoS, no
over-payment. The removed net therefore only ever guarded a *benign* degradation, so removing it
carries negligible risk even under invariant violation.

## 2. Remove `Dispenser.changeStakingParams` + `StakingParamsUpdated` — SAFE

- **No live caller.** No deployment or proposal script calls `Dispenser.changeStakingParams`
  (the two `changeStakingParams` references in `scripts/proposals/*` target
  **`Tokenomics.changeStakingParams`**, which is retained). Confirmed by grep across `scripts/`.
- `maxNumClaimingEpochs` / `maxNumStakingTargets` are set (with a zero-check) in `initialize()`
  (`Dispenser.sol:389–390`, in `initialize()`), so they are established at proxy init.
- **Consequence — deliberate:** these two bounds become **set-once at `initialize()`** with no
  runtime setter. This removes a governance tuning lever; it is recoverable because the Dispenser
  is proxy-upgradeable (a future implementation can reintroduce a setter). Acceptable design
  reduction, flagged by the author.

## 3. Constructor 5→3 + immutable removal — storage-layout-safe (proxy)

The removed `defaultMin/MaxStaking*` are **immutables** (implementation bytecode, not proxy
storage), and only a function + an event were removed besides — **no storage variable was removed
or reordered**, so the proxy storage layout is preserved and the upgrade is safe. The constructor
now takes `(olas, tokenomics, retainer)`; `deploy_07a_dispenser.sh` was updated to the 3-arg
`abi-encode("constructor(address,address,bytes32)")`. `DispenserProxy.sol` changes are pragma +
co-author only — `PROXY_DISPENSER` slot (`keccak256("PROXY_DISPENSER")`) and the delegatecall path
are untouched.

## 4. Tests

- **`forge test --mc Dispenser` (unit) — 17/17 PASS, re-run firsthand:** DispenserProxy 9 (incl.
  `changeImplementation_swapsLogicAndPreservesState`, reinit guards), DispenserFixes 5 (the
  vuln-list #8/#9/#12/#25 regressions), Dispenser 3 (the incentive-loop claim path that exercises
  the now-fallback-free branch). `DispenserFixes` correctly sets the staking params explicitly and
  the `(1,1)` bounds instance re-exercises the `Overflow` paths that the dropped DAO-setter test
  used to cover.
- **`StakingClaimForkETH` (mainnet-fork proxied claim path) — dev reports 3/3;** not re-run here
  (the fork needs an archive mainnet RPC / alias not available in this environment). The specific
  claim it validates — the live staking points carry non-zero `min`/`max` so the removed fallback
  never fires — is instead grounded independently by the on-chain reads in §1.

## 5. Out of scope (flagged by the author — acknowledged)

- `abis/*/Dispenser.json` + `docs/configuration.json` still carry a stale Dispenser ABI (old 9-arg
  constructor, already stale since the #309 proxy refactor). ABI regeneration is a release-artifact
  step at redeploy — correct to defer.
- `Vulnerabilities_list_tokenomics.md` unchanged — those entries clear only after the physical
  redeploy + rewiring.

## 6. Observation (Informational — non-blocking)

**OBS-1 — the removed fallback made an implicit cross-contract invariant load-bearing.** After
this change the Dispenser claim path relies on Tokenomics never emitting a `stakingFraction > 0`
StakingPoint with `minStakingWeight == 0 && maxStakingIncentive == 0`. That holds today (§1), but
it is now an *undocumented* dependency spanning two independently-upgradeable proxies. Recommend
making it explicit — a one-line NatSpec at the claim site (e.g. "assumes Tokenomics guarantees
non-zero min/max whenever stakingFraction > 0; enforced by changeStakingParams zero-reject +
epoch carry-forward") and/or a note in `Vulnerabilities_list_tokenomics.md` — so a future
Tokenomics change that could set `stakingFraction > 0` before the staking params (e.g. a fresh
deployment ordering) surfaces the Dispenser dependency rather than silently distributing zero
incentives. Cheap, and it removes the only non-obvious risk in this PR.

## Verdict

**GREEN-LIGHT.** The default-staking-param fallback is proven dead code on the live Tokenomics
(zero-reject + unconditional epoch carry-forward, confirmed by on-chain reads), its removal is
behavior-neutral on the live system and benign even under invariant violation; `changeStakingParams`
had no live caller and its bounds are set at `initialize()`; the immutable/constructor changes
touch no proxy storage slot; 17/17 unit tests pass firsthand. Address **OBS-1** (document the
cross-contract invariant) as hardening — not a blocker.
