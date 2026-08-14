# External audit candidates — not externally audited smart contracts

## Introduction

This document describes the parts of the protocol code that were not externally audited and for which
an external audit can be performed. Repositories in scope:

- https://github.com/valory-xyz/autonolas-governance/tree/v1.3.0-pre-external-audit
- https://github.com/valory-xyz/autonolas-tokenomics/tree/1.5.0-pre-external-audit

The changes below are a focused follow-up to the previously audited core protocol: a security
hardening of the governance `VoteWeighting` gauge controller, a rework of the tokenomics `Dispenser`
(moved behind a proxy, closed vulnerability-list items, and made the staking-incentive calculation a
pure `view`), a fail-closed price-guard hardening of the protocol-owned-liquidity `LiquidityManagerCore`
(with the deviation gate tightened to 2%), and a decomposition of the two chain-specific liquidity managers
into composable source / target / burn mixins plus one new `Balancer V2 → Uniswap V3` combination. All other
core contracts are unchanged from their last audited state.

For each contract both figures are given: the full SLoC of the file (whole-file audit scope) and the
delta against the previously audited version (lines added / removed), so the review can be scoped
either way.

## Before → after code state (tag diffs)

The changes below are all merged. To see the exact before/after code state, diff the last
externally-audited tag against the pre-external-audit snapshot of each repo:

- **Tokenomics** — `v1.4.3-post-external-audit` → `1.5.0-pre-external-audit`:
  https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.4.3-post-external-audit...1.5.0-pre-external-audit
  The `1.5.0-pre-external-audit` tag is to be cut at the merge of PRs #306/#307/#309/#310/#311/#314/#315
  (currently `main`); until it is pushed, the same diff is
  https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.4.3-post-external-audit...main
- **Governance** — last external-audit tag → `v1.3.0-pre-external-audit`:
  https://github.com/valory-xyz/autonolas-governance/compare/<last-audited-tag>...v1.3.0-pre-external-audit
  (per-contract diff is PR https://github.com/valory-xyz/autonolas-governance/pull/215).

Per-contract line deltas below are the raw `git diff` (added / removed) against
`v1.4.3-post-external-audit`; the SLoC figures are `cloc` code lines on the merged file.

## Governance

The following needs to be audited:

1. VoteWeighting.sol — 437 SLoC — delta: +63 / −39 (~102 lines changed)

**Contracts Number: 1**
**Total SLoC (full file): 437 — Changed lines: ~102**

### Scope of changes for VoteWeighting

- Reconciles the `removeNominee` accounting so a removed-then-re-added nominee no longer strands weight
  bookkeeping and no longer bricks the gauge `checkpoint` path (checkpoint DoS).
- The fix touches the core weight/bias/slope checkpoint machinery, so the whole contract is listed for
  full-file context; alternatively the review can be scoped to the changed functions plus the
  `checkpoint` / `nomineeRelativeWeight` paths they interact with (~102 changed lines).

Ref. PR https://github.com/valory-xyz/autonolas-governance/pull/215

## Tokenomics

The following needs to be audited:

1. Dispenser.sol — 717 SLoC — delta: +211 / −90 (~301 lines changed)
2. DispenserProxy.sol — 34 SLoC — new file (entire file new)
3. LiquidityManagerCore.sol — 657 SLoC — delta: +210 / −95 (~305 lines changed; price-guard fail-closed + the R6 gate tightening)

LiquidityManager refactor — the former `LiquidityManagerETH` / `LiquidityManagerOptimism` are removed and
their bodies decomposed into composable source / target / burn mixins over `LiquidityManagerCore`, plus one
new combination (`LiquidityManagerBalancerUniV3`). All are new files (whole-file scope), but the mixin bodies
are an extraction of the two removed leaves — diff-reviewable against them — so the genuinely new surface is
the composition seams and the new leaf:

4. LiquidityManagerSourceBase.sol — 34 SLoC — new file (shared source-side TWAP fair-min math)
5. LiquidityManagerSourceUniV2.sol — 55 SLoC — new file (extracted from LiquidityManagerETH)
6. LiquidityManagerSourceBalancer.sol — 71 SLoC — new file (extracted from LiquidityManagerOptimism)
7. LiquidityManagerTargetUniV3.sol — 46 SLoC — new file (extracted from LiquidityManagerETH)
8. LiquidityManagerTargetSlipstream.sol — 58 SLoC — new file (extracted from LiquidityManagerOptimism)
9. LiquidityManagerBurnViaBridge.sol — 15 SLoC — new file (L2 bridge-burn, extracted)
10. LiquidityManagerUniV2UniV3.sol — 24 SLoC — new file (leaf; replaces LiquidityManagerETH)
11. LiquidityManagerBalancerSlipstream.sol — 25 SLoC — new file (leaf; replaces LiquidityManagerOptimism)
12. LiquidityManagerBalancerUniV3.sol — 25 SLoC — new file (leaf; new Balancer V2 → Uniswap V3 combination)
13. LiquidityManagerUniV2UniV3Bridge.sol — 25 SLoC — new file (leaf; Uniswap V2 → Uniswap V3 with L2 bridge burn, e.g. Ubeswap → Uniswap V3 on Celo)

**Contracts Number: 13**
**Total SLoC (full files): 1786** — Dispenser 717, DispenserProxy 34, LiquidityManagerCore 657, and the
LiquidityManager refactor 378 (mixins 279 + leaves 99). Changed-lines scope: ~301 in Dispenser, 34 new in
DispenserProxy, ~305 in LiquidityManagerCore, and the 378-SLoC refactor (mostly extraction; ~99 SLoC of
genuinely new leaf/composition code across the four leaves).

### Scope of changes for Dispenser / DispenserProxy

- **Proxy conversion.** `Dispenser` is deployed behind the new `DispenserProxy` (EIP-1967-style,
  implementation slot `keccak256("PROXY_DISPENSER")`, delegatecall fallback). Constructor immutables are
  reduced to `(olas, tokenomics, retainer)`; the mutable managers and bounds (`treasury`, `voteWeighting`,
  `maxNumClaimingEpochs`, `maxNumStakingTargets`) move to `initialize()`, and `changeImplementation`
  (owner/DAO-gated) enables future logic upgrades without a redeploy cascade.
- **Vulnerability-list items closed** (#8, #9, #12, #25): guard against changing managers while staking
  incentives are unpaused; refund/return correctness; and the removed-then-re-added nominee interaction.
- **`calculateStakingIncentives` is now a pure `view`.** It no longer checkpoints the nominee, sets the
  one-time zero-weight-epoch refund flag, or refunds; instead it returns a sparse `zeroWeightEpochs[]` and
  folds the zero-weight incentive into the returned `totalReturnAmount`. All state effects
  (`checkpointNominee`, `mapZeroWeightEpochRefunded`, the aggregated `refundFromStaking`) move up into the
  two claim paths. This makes the item-12 hazard impossible by construction (a standalone call mutates
  nothing) and makes the function directly `staticcall`-able for off-chain estimation.
- **Default staking-param fallback removed** together with the now-obsolete `Dispenser.changeStakingParams`;
  the staking min-weight / max-incentive are read solely from Tokenomics.
- Because the proxy conversion changes storage/initialization semantics, the whole `Dispenser` +
  `DispenserProxy` pair is listed for a full-file audit; the ~247-line delta is given for a scoped review.

Ref. PRs https://github.com/valory-xyz/autonolas-tokenomics/pull/309,
https://github.com/valory-xyz/autonolas-tokenomics/pull/310,
https://github.com/valory-xyz/autonolas-tokenomics/pull/314,
https://github.com/valory-xyz/autonolas-tokenomics/pull/315 —
internal-audit records in `audits/internal18/README.md` and `audits/internal19/README.md`.

### Scope of changes for LiquidityManagerCore

- **Price guard fails closed on entries/trades.** `checkPoolAndGetCenterPrice` now reverts
  `NotEnoughHistory` whenever it cannot produce a verifiable 30-minute TWAP — both on a freshly-created
  pool (cardinality ≤ 1) and on an inactive pool (no trade within `SECONDS_AGO`) — instead of falling
  open to the raw, manipulable `slot0`. Every price-consuming caller (`convertToV3`, `changeRanges`,
  `increaseLiquidity`, permissionless `BuyBackBurner.buyBack`) inherits the revert; it is a refusal, not a
  permanent denial (one subsequent swap repopulates the observation buffer).
- **Exits stay live via a soft-priced floor.** `decreaseLiquidity` keeps its 4-arg signature and derives
  its slippage floor at execution from a new `_getExitSqrtPrice`: the TWAP when the pool is verifiable
  (`slot0` bounded to it within `MAX_ALLOWED_DEVIATION`), otherwise `slot0`. A withdrawal is always
  possible on a quiet pool, deviation-bounded on a mature pool, and never goes stale across a
  governance vote + timelock delay. Deliberate distinction: entries/trades fail-closed; the exit path
  fails-open-soft.
- **Other changes:** `collectFees` drops the guard gate and burns only the just-collected fee (not the
  whole balance); the entry `amountMin` (mint + `increaseLiquidity`) is anchored to `slot0` (the execution
  price) rather than the TWAP center, closing an in-gate dead band (#306.1); `oldestTimestamp` →
  `latestObsTimestamp` rename; removed the now-unused `_getObservationCardinality`.
- **R6 gate tightening.** `MAX_ALLOWED_DEVIATION` is tightened 10% → 2% — post-#306.1 the entry `amountMin` is
  vacuous, so this gate is the sole entry manipulation defence (see `audits/internal20/README.md` R6).
- Storage layout is preserved (external signatures unchanged, one new `error` only), so the change ships to
  the live proxies via a `changeImplementation` upgrade. `LiquidityManagerCore` is the shared implementation
  base for the mixin-composed leaf managers (below); the guard + tightening changes are confined to the base.
  ~305-line delta on a 657-SLoC file; listed for a full-file audit.

Ref. PRs https://github.com/valory-xyz/autonolas-tokenomics/pull/306 (deployment routine + audit-diff in
https://github.com/valory-xyz/autonolas-tokenomics/pull/307) and
https://github.com/valory-xyz/autonolas-tokenomics/pull/318 (R6 tightening).

### Scope of changes for the LiquidityManager refactor

- **Mixin decomposition.** The two leaf managers only ever varied along three orthogonal axes — the source
  DEX the POL is withdrawn from, the target concentrated-liquidity DEX it is minted into, and how OLAS is
  burned (L1 direct vs L2 bridge). These are factored into abstract mixins over `LiquidityManagerCore`:
  source (`SourceUniV2` | `SourceBalancer`, sharing `SourceBase`'s TWAP fair-min math), target
  (`TargetUniV3` | `TargetSlipstream`), and burn (`BurnViaBridge`; L1 direct burn inlined in the UniV2→UniV3
  leaf). The three leaves are then pure composition.
- **Behavior-preserving extraction.** The mixin bodies are moved verbatim from the removed `LiquidityManagerETH`
  / `LiquidityManagerOptimism`, so each is diff-reviewable against those files. Verified by the existing fork
  suites (ETH UniV2→UniV3, Base Balancer→Slipstream) passing unchanged, plus the #306 dead-band / fail-open
  proofs. The genuinely new surface an auditor should focus on is the **composition seams** (constructor
  arg-threading, diamond linearization, which mixin overrides which `Core` hook) and the one **new leaf**,
  `LiquidityManagerBalancerUniV3` (Balancer source + UniV3 target + L2 burn), proven end-to-end on a Base
  fork.
- Storage lives entirely in `Core` (mixins add only immutables), so `changeImplementation` upgrades stay safe.

Ref. PR https://github.com/valory-xyz/autonolas-tokenomics/pull/319.

## Contracts and SLoC

Overall: **14 contracts and 2223 SLoC** — governance `VoteWeighting.sol` (437) and 13 tokenomics contracts
(1786): `Dispenser.sol` 717, `DispenserProxy.sol` 34, `LiquidityManagerCore.sol` 657, and the 10-file
LiquidityManager refactor 378 (source/target/burn mixins 279 + four leaves 99). Changed-lines scope:
~102 in VoteWeighting, ~301 in Dispenser, 34 new in DispenserProxy, ~305 in LiquidityManagerCore, and the
378-SLoC refactor (mostly behavior-preserving extraction from the two removed leaves; ~99 SLoC of genuinely
new leaf/composition code across the four leaves).
