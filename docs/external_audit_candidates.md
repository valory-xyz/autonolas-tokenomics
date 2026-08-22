# External audit candidates — not externally audited smart contracts

## Introduction

This document describes the parts of the protocol code that were not externally audited and for which
an external audit can be performed. Repositories in scope:

- https://github.com/valory-xyz/autonolas-governance/tree/v1.3.0-pre-external-audit
- https://github.com/valory-xyz/autonolas-tokenomics/tree/v1.5.0-pre-external-audit

The changes below are a focused follow-up to the previously audited core protocol: a security
hardening of the governance `VoteWeighting` gauge controller, a rework of the tokenomics `Dispenser`
(moved behind a proxy, closed vulnerability-list items, and made the staking-incentive calculation a
pure `view`), a fail-closed price-guard hardening of the protocol-owned-liquidity `LiquidityManagerCore`
(deviation gate tightened to 2%, and the source-side withdrawal TWAP oracle replaced by an in-contract
V2↔V3 ratio cross-check), and a decomposition of the two chain-specific liquidity managers into composable
source / target / burn mixins plus one new `Balancer V2 → Uniswap V3` combination. All other core contracts
are unchanged from their last audited state.

For each contract both figures are given: the full SLoC of the file (whole-file audit scope) and the
delta against the previously audited version (lines added / removed), so the review can be scoped
either way.

## Before → after code state (tag diffs)

The changes below are all merged. To see the exact before/after code state, diff the last
externally-audited tag against the pre-external-audit snapshot of each repo:

- **Tokenomics** — `v1.4.3-post-external-audit` → `v1.5.0-pre-external-audit`:
  https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.4.3-post-external-audit...v1.5.0-pre-external-audit
  The `v1.5.0-pre-external-audit` tag is cut on `main`. The **contract changes** are the PRs listed below —
  #306/#307/#309/#310/#311/#314/#315/#318/#319/#323/#326/#328/#333 — plus the **comment-only** NatSpec scrub
  in #325 (it touches `contracts/pol/*.sol` incl. `LiquidityManagerCore.sol` but changes no non-comment line:
  it only strips internal references such as `#306.1` / `VL#15` / `internal20 R6`). The full
  `v1.4.3-post-external-audit…v1.5.0-pre-external-audit` range spans 40 merged PRs (#287–#338); the remainder
  are deployment, config, test, docs and audit-report changes, including the CI/doc follow-ups #329/#330, the
  vulnerabilities-list updates #334/#335/#336, and the Celo proposal-script correction #338 (a governance
  proposal generator, no contract code).

  > **Tag maintenance (decision):** `v1.5.0-pre-external-audit` is **moved** (force-updated) to the `main` HEAD
  > that carries this doc correction — the tag name is stable, its target advances — so the snapshot the
  > auditors receive has the corrected references above, not the pre-fix `870d46f` state. This assumes the tag
  > has not yet been externally distributed; if it has, cut a suffixed tag (e.g. `-v2`, per the repo's
  > `v1.4.2-post-external-audit-v3` precedent) instead of re-pointing a published ref.
  >
  > **Applied again for this refresh.** Confirmed not yet externally distributed, so the tag is re-pointed
  > rather than suffixed. Its previous target, `703e368`, was the last commit on #333's *branch*, so the tag
  > already carried #333's contract fix and the merge commit adds no content — moving it onto `main`'s
  > first-parent line is what changes. Between `703e368` and the new target only
  > `docs/Vulnerabilities_list_tokenomics.md` and one governance proposal script differ: **no `contracts/`
  > file changes**, so the audited contract set is byte-identical either way and the move only buys the
  > auditors a current known-issues list.

- **Governance** — `v1.2.5-post-external-audit` → `v1.3.0-pre-external-audit`:
  https://github.com/valory-xyz/autonolas-governance/compare/v1.2.5-post-external-audit...v1.3.0-pre-external-audit
  (the `VoteWeighting` per-contract diff is PR https://github.com/valory-xyz/autonolas-governance/pull/215).
  Across that range only two **production** contracts differ — `VoteWeighting.sol` and `GuardCM.sol`; the
  other changed files under `contracts/` are test harnesses (`test/EchidnaVoteWeightingAssert.sol`,
  `test/MockDispenser.sol`, `test/VoteWeightingFuzzing.sol`) and are not audit scope.

  > **Tag maintenance (decision):** the same policy as for tokenomics above applies to
  > `v1.3.0-pre-external-audit`, and it is **moved** to the `main` HEAD carrying this correction.
  > Confirmed not yet externally distributed. Between the tag's previous target (`1159e5d`) and that HEAD
  > the only file that differs is `docs/Vulnerabilities_list_governance.md` (+48/−0, known-issues items
  > added by #219 and corrected by #220) — **no `contracts/` file changes** — so the audited contract set
  > is byte-identical and the move only gives the auditors the current known-issues list.

Per-contract line deltas below are the raw `git diff` (added / removed) against
`v1.4.3-post-external-audit`; the SLoC figures are `cloc` code lines on the merged file.

## Governance

The following needs to be audited:

1. VoteWeighting.sol — 437 SLoC — delta: +63 / −39 (~102 lines changed)
2. GuardCM.sol — 253 SLoC — delta: +1 / −2 (3 lines changed; `setBridgeMediatorL1BridgeParams` now also
   rejects a zero `bridgeMediatorL2s[i]`, and the note stating that an L2 mediator may legitimately be zero
   "for example, for Arbitrum case" is removed)

**Contracts Number: 2**
**Total SLoC (full files): 690** — VoteWeighting 437, GuardCM 253. **Changed lines: ~105** — ~102 in
VoteWeighting, 3 in GuardCM.

> `GuardCM.sol` was previously omitted from this scope. Its delta is one line of logic, but it is a
> behavioural tightening rather than a comment change, so it belongs in the listed set. Reviewers should
> note the interaction it creates: the removed comment asserted that a zero L2 bridge mediator is valid for
> some chains, Arbitrum being the named example, and the new check rejects exactly that — so whether every
> supported chain still configures cleanly through `setBridgeMediatorL1BridgeParams` is worth confirming
> against the live per-chain parameters rather than assumed.

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
3. LiquidityManagerCore.sol — 677 SLoC — delta: +279 / −95 (~374 lines changed; price-guard fail-closed, the deviation-gate tightening, the source-side ratio cross-check that replaces the removeLiquidity TWAP oracle, and the `collectFees` token-ordering alignment from #333)

LiquidityManager refactor — the former `LiquidityManagerETH` / `LiquidityManagerOptimism` are removed and
their bodies decomposed into composable source / target / burn mixins over `LiquidityManagerCore`, plus one
new combination (`LiquidityManagerBalancerUniV3`). All are new files (whole-file scope), but the mixin bodies
are an extraction of the two removed leaves — diff-reviewable against them — so the genuinely new surface is
the composition seams and the new leaf:

4. LiquidityManagerSourceUniV2.sol — 46 SLoC — new file (extracted from LiquidityManagerETH; removeLiquidity now passes zero floors)
5. LiquidityManagerSourceBalancer.sol — 65 SLoC — new file (extracted from LiquidityManagerOptimism; exitPool now passes zero floors)
6. LiquidityManagerTargetUniV3.sol — 46 SLoC — new file (extracted from LiquidityManagerETH)
7. LiquidityManagerTargetSlipstream.sol — 58 SLoC — new file (extracted from LiquidityManagerOptimism)
8. LiquidityManagerBurnViaBridge.sol — 15 SLoC — new file (L2 bridge-burn, extracted)
9. LiquidityManagerUniV2UniV3.sol — 23 SLoC — new file (leaf; replaces LiquidityManagerETH)
10. LiquidityManagerBalancerSlipstream.sol — 24 SLoC — new file (leaf; replaces LiquidityManagerOptimism)
11. LiquidityManagerBalancerUniV3.sol — 24 SLoC — new file (leaf; new Balancer V2 → Uniswap V3 combination)
12. LiquidityManagerUniV2UniV3Bridge.sol — 24 SLoC — new file (leaf; Uniswap V2 → Uniswap V3 with L2 bridge burn, e.g. Ubeswap → Uniswap V3 on Celo)

(The former `LiquidityManagerSourceBase.sol` was removed once the oracle / fair-min was dropped — it held no
logic; its one remaining `WrongTokenAddresses` error moved into `LiquidityManagerCore` and the two source
mixins now extend `LiquidityManagerCore` directly.)

**Contracts Number: 12**
**Total SLoC (full files): 1753** — Dispenser 717, DispenserProxy 34, LiquidityManagerCore 677, and the
LiquidityManager refactor 325 (mixins 230 + leaves 95). Changed-lines scope: ~301 in Dispenser, 34 new in
DispenserProxy, ~374 in LiquidityManagerCore, and the 325-SLoC refactor (mostly extraction; ~95 SLoC of
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
- **Source-side manipulation gate replaces the withdrawal oracle.** The V2/Balancer removal previously derived
  a TWAP-anchored `minAmountsOut` from a per-chain price oracle (`oracleV2`); that oracle and its
  `_fairMinAmountsOut` helper are removed and the removal passes zero per-token floors. Instead `convertToV3`
  cross-checks the ratio of the removed tokens against the already gate-verified V3 `slot0`
  (`_checkRemovedRatioAgainstV3`) and reverts `RatioDeviation` when it diverges by more than `maxSlippage`
  (re-tasked from the old floor; default 5%). A proportional removal cannot lose value at the true price
  (constant-product convexity), so this gates the lopsided-conversion case without any oracle. Design +
  fork-measured tolerance in `docs/lm_source_crosscheck_design.md`; the check is placed after the
  `olasBurnRate` burn deliberately (a revert unwinds the burn atomically in the same tx).
- Storage layout is preserved (external signatures unchanged; two errors added — `RatioDeviation`, and
  `WrongTokenAddresses` relocated from the removed `SourceBase`), so the change ships to the live proxies via a
  `changeImplementation` upgrade. `LiquidityManagerCore` is the shared implementation base for the
  mixin-composed leaf managers (below); the guard, tightening, and cross-check changes are confined to the base.
  ~335-line delta on a 673-SLoC file; listed for a full-file audit.

Ref. PRs https://github.com/valory-xyz/autonolas-tokenomics/pull/306 (deployment routine + audit-diff in
https://github.com/valory-xyz/autonolas-tokenomics/pull/307),
https://github.com/valory-xyz/autonolas-tokenomics/pull/318 (R6 tightening), and
https://github.com/valory-xyz/autonolas-tokenomics/pull/326 (source-side oracle → V2↔V3 ratio cross-check).

### Scope of changes for the LiquidityManager refactor

- **Mixin decomposition.** The two leaf managers only ever varied along three orthogonal axes — the source
  DEX the POL is withdrawn from, the target concentrated-liquidity DEX it is minted into, and how OLAS is
  burned (L1 direct vs L2 bridge). These are factored into abstract mixins over `LiquidityManagerCore`:
  source (`SourceUniV2` | `SourceBalancer`), target (`TargetUniV3` | `TargetSlipstream`), and burn
  (`BurnViaBridge`; L1 direct burn inlined in the UniV2→UniV3 leaf). The three leaves are then pure composition.
- **Behavior-preserving extraction.** The mixin bodies are moved verbatim from the removed `LiquidityManagerETH`
  / `LiquidityManagerOptimism`, so each is diff-reviewable against those files. Verified by the existing fork
  suites (ETH UniV2→UniV3, Base Balancer→Slipstream) passing unchanged, plus the #306 dead-band / fail-open
  proofs. The genuinely new surface an auditor should focus on is the **composition seams** (constructor
  arg-threading, diamond linearization, which mixin overrides which `Core` hook) and the one **new leaf**,
  `LiquidityManagerBalancerUniV3` (Balancer source + UniV3 target + L2 burn), proven end-to-end on a Base
  fork.
- Storage lives entirely in `Core` (mixins add only immutables), so `changeImplementation` upgrades stay safe.

Ref. PR https://github.com/valory-xyz/autonolas-tokenomics/pull/319.

## Staking cross-chain contracts (redeployed this cycle — previously audited, no logic change)

The cross-chain staking DepositProcessor (L1) / TargetDispenser (L2) contracts are being redeployed as part of
this cycle, but they are **not new or changed code**. They were externally audited previously (Code4rena
2023-12 / 2024-05 / 2026-02) and across the internal-audit series, and the only source change here is
standardizing their `pragma` to `^0.8.30` — metadata-only: the repo's single 0.8.x compiler is 0.8.30, so they
already compiled with it, and there is no logic or instruction-level bytecode change. They are therefore in
scope for the redeployment's **on-chain bytecode + configuration re-verification** (the static audit script,
`scripts/audit_chains/audit_contracts_setup.js`), **not** a fresh code audit.

Listed for completeness (SLoC = `cloc` code lines):

- `DefaultDepositProcessorL1.sol` — 142 (shared L1 base) / `DefaultTargetDispenserL2.sol` — 306 (shared L2 base)
- `ArbitrumDepositProcessorL1.sol` — 109 / `ArbitrumTargetDispenserL2.sol` — 37
- `GnosisDepositProcessorL1.sol` — 36 / `GnosisTargetDispenserL2.sol` — 42
- `OptimismDepositProcessorL1.sol` — 65 / `OptimismTargetDispenserL2.sol` — 44
- `PolygonDepositProcessorL1.sol` — 60 / `PolygonTargetDispenserL2.sol` — 39
- `EthereumDepositProcessor.sol` — 87 (L1-only)
- `IBridgeErrors.sol` — 23 (shared errors interface, imported only by the staking bases)

**Redeployed set: 990 SLoC** across 11 contracts + the shared errors interface.

`WormholeDepositProcessorL1.sol` (89) / `WormholeTargetDispenserL2.sol` (95) are **not** being redeployed; their
`pragma` is bumped only to keep the repo uniform, and their live deployments are unchanged.

## Contracts and SLoC

Overall: **13 contracts and 2186 SLoC** — governance `VoteWeighting.sol` (437) and 12 tokenomics contracts
(1749): `Dispenser.sol` 717, `DispenserProxy.sol` 34, `LiquidityManagerCore.sol` 673, and the 9-file
LiquidityManager refactor 325 (source/target/burn mixins 230 + four leaves 95). Changed-lines scope:
~102 in VoteWeighting, ~301 in Dispenser, 34 new in DispenserProxy, ~335 in LiquidityManagerCore, and the
325-SLoC refactor (mostly behavior-preserving extraction from the two removed leaves; ~95 SLoC of genuinely
new leaf/composition code across the four leaves).
