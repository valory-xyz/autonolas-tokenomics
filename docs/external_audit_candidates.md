# External audit candidates — not externally audited smart contracts

## Introduction

This document describes the parts of the protocol code that were not externally audited and for which
an external audit can be performed. Repositories in scope:

- https://github.com/valory-xyz/autonolas-governance/tree/v1.3.0-pre-external-audit
- https://github.com/valory-xyz/autonolas-tokenomics/tree/1.5.0-pre-external-audit

The changes below are a focused follow-up to the previously audited core protocol: a security
hardening of the governance `VoteWeighting` gauge controller, a rework of the tokenomics `Dispenser`
(moved behind a proxy, closed vulnerability-list items, and made the staking-incentive calculation a
pure `view`), and a fail-closed price-guard hardening of the protocol-owned-liquidity
`LiquidityManagerCore`. All other core contracts are unchanged from their last audited state.

For each contract both figures are given: the full SLoC of the file (whole-file audit scope) and the
delta against the previously audited version (lines added / removed), so the review can be scoped
either way.

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

1. Dispenser.sol — 705 SLoC — delta: +159 / −88 (~247 lines changed)
2. DispenserProxy.sol — 34 SLoC — new file (entire file new)
3. LiquidityManagerCore.sol — 641 SLoC — delta: +158 / −82 (~240 lines changed)

**Contracts Number: 3**
**Total SLoC (full files): 1380 — Changed lines: ~247 in Dispenser + 34 new in DispenserProxy + ~240 in LiquidityManagerCore**

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
  whole balance); `increaseLiquidity` anchors `amountMin` to the TWAP center instead of raw `slot0`;
  `oldestTimestamp` → `latestObsTimestamp` rename; removed the now-unused `_getObservationCardinality`.
- Storage layout is preserved (external signatures unchanged, one new `error` only), so the change ships
  to the live proxies via a `changeImplementation` upgrade. `LiquidityManagerCore` is the shared
  implementation base for `LiquidityManagerETH` / `LiquidityManagerOptimism`; the change is confined to
  the base. ~240-line delta on a 641-SLoC file; listed for a full-file audit.

Ref. PR https://github.com/valory-xyz/autonolas-tokenomics/pull/306 (deployment routine + audit-diff in
https://github.com/valory-xyz/autonolas-tokenomics/pull/307).

## Contracts and SLoC

Overall: **4 contracts and 1817 SLoC** (VoteWeighting.sol 437, Dispenser.sol 705, DispenserProxy.sol 34,
LiquidityManagerCore.sol 641). Changed-lines scope: ~102 in VoteWeighting, ~247 in Dispenser,
34 new in DispenserProxy, ~240 in LiquidityManagerCore.
