# Internal Audit 17 — autonolas-tokenomics (re-audit)

**Audit date**: 2026-06-16
**Audited ref**: `v1.4.3` (`a9b26c1ea0b0fcd2b05c3fcd10480af1e519cc34`)
**Deployment status**: live on Ethereum mainnet (owner = Timelock `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE`)
**Auditor**: audit-claude

## Scope

Full re-audit of the in-scope `contracts/` set (4,293 LOC):

| Contract | LOC | Role |
|---|---|---|
| `Tokenomics.sol` | 1581 | epoch engine, IDF, incentive accounting, UUPS implementation |
| `Dispenser.sol` | 1330 | cross-chain staking-incentive dispensing (7 chains) |
| `Treasury.sol` | 551 | value custody (ETH / OLAS / LP), withdraw, pause |
| `Depository.sol` | 494 | bonding (create / close / redeem) |
| `GenericBondCalculator.sol` | 93 | UniswapV2 LP valuation for bond payout |
| `DonatorBlacklist.sol` | 85 | donor blacklist |
| `TokenomicsConstants.sol` | 159 | constants + inflation schedule |

**Approach**: independent adversarial code review of each contract against its security goals (custody, incentive accounting, epoch integrity, bonding, cross-chain dispensing, access control, parameter bounds), followed by on-chain state verification of live deployments and Foundry proof-of-concept tests for load-bearing claims.

## Summary

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |
| Informational | 4 |

No exploitable findings. Several candidate issues were investigated and shown not to be exploitable (see below); the residual items are hardening / defense-in-depth.

## Investigated and cleared (no issue)

- **Dispenser `retain()` vs the zero-total-weight refund path** — investigated a potential double-refund of staking inflation (an epoch refunded by `calculateStakingIncentives`' `totalWeightSum == 0` branch and again by `retain()`). **Not exploitable**: on the live `VoteWeighting`, `_nomineeRelativeWeight` assigns a non-zero relative weight only inside `if (totalSum > 0)`, so a zero-total-weight epoch yields relative weight `0` for **every** nominee, including the retainer. `retain()`'s `stakingIncentive * weight` term is therefore `0` for exactly the epochs the zero-weight branch handles — the two paths cannot both count the same epoch. Verified on a mainnet fork (see `test/`).
- **`Tokenomics.updateInflationPerSecondAndFractions` `effectiveBond` reset** — the `effectiveBond = curMaxBond` write is the intended "reset unused bonding/staking inflation" behaviour of the manual curve-recalculation path (it reverts if the year changes within the epoch; the smooth per-epoch rollover is handled separately in `checkpoint()`). The "outstanding bond reservation at reset time" precondition is excluded by the established deployment process (bond products are closed before fraction changes). Not an over-credit.
- **Bond payout vs pool manipulation** — `deposit()` uses the `priceLP` stored at `create()` time (an owner-supplied value), not a live pool read; `GenericBondCalculator.getCurrentPriceLP` is unused on-chain. Flash-loan reserve manipulation at deposit time is therefore out of reach.
- **`Treasury.withdrawToAccount` ETH-reward shortfall branch** — the `accountRewards > 0 && ETHFromServices >= accountRewards` guard means a shortfall silently skips the ETH payout while the OLAS branch can still latch `success = true`. This branch is **unreachable** under the conservation invariant (`balance == ETHFromServices + ETHOwned`) combined with fraction-based, round-down reward accounting (`Σ owed ETH rewards ≤ ETHFromServices`). Defensive only — see L-1.

## Findings

### Low

**L-1 — `Treasury.withdrawToAccount`: silent shortfall branch should revert.**
On the ETH-reward path, a shortfall (`ETHFromServices < accountRewards`) is skipped without reverting, and a non-zero `accountTopUps` then latches `success = true`. The condition is unreachable under current accounting (see above), but the silent-skip is fragile to any future accounting change. **Recommendation**: add an explicit `else revert` on the shortfall so a reward can never be marked claimed without being paid.

**L-2 — `Dispenser.calculateStakingIncentives` is `public` non-view and writes VoteWeighting state.**
The NatSpec instructs callers to use `staticcall`, but the function is `public` and unconditionally calls `IVoteWeighting(...).checkpointNominee(...)`. Any caller can advance the nominee checkpoint directly. **Recommendation**: mark the function `view`, or split the checkpoint write into a path only reachable from the actual claim functions.

### Informational

**I-1 — `Dispenser.claimStakingIncentives` / `claimStakingIncentivesBatch`: attached value stranded on zero-incentive claims.**
When the resolved staking incentive is `0`, the `{value: ...}` forwarder is gated out and there is no refund/sweep, so any attached `msg.value` is stranded. This is the caller's own value and is deterministically avoidable. **Recommendation**: `require(stakingIncentive > 0 || msg.value == 0)` (single path) and refund/validate per-target in the batch path.

**I-2 — `GenericBondCalculator.getCurrentPriceLP` is an unused single-reserve spot valuation.**
It is not referenced on-chain by the audited contracts (payout uses the stored `priceLP`). If it were ever used to source a bond price it would be manipulable. **Recommendation**: remove it, or document that `priceLP` must never be sourced from a spot read.

**I-3 — `Tokenomics` implementation lacks `_disableInitializers()`.**
The UUPS proxy is unaffected (re-initialization is blocked), but a bare logic instance can be initialized by anyone. **Recommendation**: call `_disableInitializers()` in the implementation constructor.

**I-4 — `Dispenser.retain()` has no pause gate.**
Unlike the claim entry points, `retain()` runs while paused. This is acceptable: it only returns staking incentive to inflation (it cannot move value out), and it is invoked by `updateInflationPerSecondAndFractions`, so it must remain callable during reconfiguration. Documented for awareness.

## Verification evidence

The load-bearing refutation (the `retain()` double-refund) was verified on a mainnet fork against the production `VoteWeighting`:

```
forge test --match-path 'audits/internal17/test/*' --fork-url <mainnet> -vv
[PASS] test_zeroTotalSum_implies_zeroWeight() (gas: 10631)
  totalSum (no-vote bucket): 0
  relativeWeight: 0
```

Test source: `audits/internal17/test/LivenessWeightInvariant.t.sol`.

## Governance recommendation — Community-Multisig guard allowlist (autonolas-governance)

The live CM guard allowlist was reviewed on-chain (active guard `0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B`). For incident response, **`Dispenser.setPauseState(uint8)` (`0x63096509`) is not allowlisted on any chain**, so the cross-chain staking dispenser cannot currently be paused by the CM without a full Governor vote. Recommendation: add it to the guard allowlist. Note that `setPauseState` is a single selector carrying the full `Pause` enum, so allowlisting it also lets the CM un-pause; if the intended stance is "CM may stop, only the DAO may resume" (as with Treasury, where `pause()` is allowlisted but `unpause()` is not), splitting the Dispenser into separate `pause()` / `unpause()` selectors would preserve that. `Treasury.unpause()` is intentionally not allowlisted and should stay that way.

## Conclusion

No Critical, High or Medium findings. The contracts (live for ~2 years, with prior internal audits and external review) hold up against an independent adversarial re-audit; the open items are Low / Informational hardening and one governance-operability recommendation.

— audit-claude, 2026-06-16
