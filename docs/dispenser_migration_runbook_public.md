# Dispenser migration runbook (redeploy + full staking-stack cutover)

> **Scope.** This runbook covers redeploying **both** `VoteWeighting` and the `Dispenser` and cutting the
> whole cross-chain staking stack over to them. Code references link to `main` of the source repo (line
> numbers drift if the contracts change — re-verify against a deploy tag before executing).

## 1. Why this redeploy

Both `VoteWeighting` (in [`autonolas-governance`](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/VoteWeighting.sol)) and the `Dispenser` (in [`autonolas-tokenomics`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Dispenser.sol)) are **non-upgradeable** contracts that carry recorded issues fixable only by deploying fresh contracts. The **headline driver** is a permanent checkpoint DoS in `VoteWeighting`: `removeNominee` retires a nominee's bias but leaves its slope and `changesSum` entries, and the unguarded subtraction in `_getSum` can then revert the weekly walk **permanently** — which also halts the Dispenser's `nomineeRelativeWeightWrite` path. The redeploy is additionally the moment to clear the Dispenser-layer issues and — see §3 — to stop future fixes from forcing this whole cascade again.

Issues addressed in this cut (links = public source registries):

**VoteWeighting** — [`Vulnerabilities_list_governance.md`](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Vulnerabilities_list_governance.md):
- **`removeNominee` (primary)** — the aggregate-accounting DoS above. Remedy on the new build: guard the `_getSum` subtraction with the contract's own `_maxAndSub`, reconcile the removed nominee's slope + `changesSum` inside `removeNominee`, and de-double-count `revokeRemovedNomineeVotingPower`.
- Plus the other recorded `VoteWeighting` items folded into the same redeploy (see the governance vulnerabilities list).

**Dispenser** — [`Vulnerabilities_list_tokenomics.md`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/Vulnerabilities_list_tokenomics.md):
- **`mapRemovedNomineeEpochs` not cleared on `addNominee`** — the two-contract brick (see §2); a fresh Dispenser sidesteps it, and the guard/reset is corrected in the new build.
- Plus the other recorded `Dispenser` items folded into the same redeploy (withheld tokens, `changeManagers`/voteWeighting pause gate, `claimStakingIncentives` netting, `migrate` event, zero-weight refund brick, etc. — see the tokenomics vulnerabilities list).

## 2. Why redeploying VoteWeighting alone isn't enough

`Dispenser.voteWeighting` is settable (`changeManagers`), so *repointing* a new VoteWeighting onto the **existing** Dispenser looks possible — but it is not sufficient, and it is unsafe:

- It leaves the Dispenser's per-nominee accounting (`mapLastClaimedStakingEpochs` / `mapRemovedNomineeEpochs`) orphaned from the new VoteWeighting's nominee set, and strands unclaimed past-epoch incentives.
- It hits a **permanent brick** if any nominee is `removeNominee`-then-re-added: the `firstClaimedEpoch >= epochRemoved` guard reverts (tokenomics known-issue on `mapRemovedNomineeEpochs`).

A **fresh Dispenser** avoids all of that — its accounting maps start empty (§4) — and lets us fix constructor-immutable parameters and the Dispenser-layer issues in the same cut.

But a fresh Dispenser is *itself* a cascade, because of the immutable cross-chain couplings detailed in §4: the L1 deposit processors bind to the Dispenser by address and the L2 dispensers bind to their L1 processor, all `immutable`. So redeploying VoteWeighting drags in a new Dispenser, which drags in every L1 processor and every L2 target dispenser. §3 ends this pattern for the Dispenser.

## 3. Design: the Dispenser is deployed behind a proxy

This migration is a whole-stack cascade only because `Dispenser` and `VoteWeighting` are **plain non-upgradeable contracts**, while the rest of the singleton stack is already proxied ([`TokenomicsProxy`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/proxies/TokenomicsProxy.sol), [`LiquidityManagerProxy`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/proxies/LiquidityManagerProxy.sol), [`BuyBackBurnerProxy`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/utils/BuyBackBurnerProxy.sol)). Since both are being redeployed anyway, this is the moment to put the Dispenser behind the same pattern so the **next** fix is a one-transaction implementation upgrade, not another cascade.

**Dispenser behind a proxy (shipped).** The cross-chain cascade exists because the L1 processors bind to the Dispenser address ([`DefaultDepositProcessorL1.sol`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/staking/DefaultDepositProcessorL1.sol), `immutable l1Dispenser`) and the L2 dispensers bind to their L1 processor ([`DefaultTargetDispenserL2.sol`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/staking/DefaultTargetDispenserL2.sol)). With the Dispenser as a **proxy with a stable address** ([`DispenserProxy.sol`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/proxies/DispenserProxy.sol)), those bindings never need to change again: a future Dispenser logic fix is an implementation swap behind the proxy, and the processors / L2 dispensers keep pointing at the same address. **This migration becomes the last full cascade.**

**VoteWeighting.** This redeploy ships `VoteWeighting` as a **plain (non-proxied) redeploy** with the security fixes, and with `dispenser` as an **immutable** bound to the Dispenser proxy at construction. Putting VoteWeighting behind a proxy too is a possible future improvement (it would make its next logic fix an implementation upgrade rather than a governance-cycle redeploy) but is out of scope for this cut.

**What changed in the Dispenser implementation:** the retainer identity stays a bytecode immutable, while the repointable managers (`treasury`, `voteWeighting`) and the init-time bounds (`maxNumClaimingEpochs`, `maxNumStakingTargets`) are proxy storage set via `initialize()`, so they survive an implementation upgrade. State starts clean at deploy (empty maps); upgrades thereafter preserve state.

## 4. What is cleared, carried, and re-pointed

**Cleared automatically (fresh contract → empty storage):** `mapLastClaimedStakingEpochs`, `mapRemovedNomineeEpochs`, `mapZeroWeightEpochRefunded` — all nominee / refund bookkeeping.

**No funds are stuck on the L1 Dispenser.** It is a pass-through: staking claims do `Treasury.withdrawToAccount(address(this), 0, amount)` → `IToken(olas).transfer(depositProcessor, amount)` in the same tx; dev incentives go Treasury→user directly. Returns to inflation are accounting calls (`Tokenomics.refundFromStaking`, dispenser-gated), not balances. Between txs the Dispenser holds ~zero OLAS.

**The only cross-chain state — `mapChainIdWithheldAmounts`.** This tracks OLAS already bridged to an L2 that staking targets could not absorb, netted against the *next* distribution to that chain. The OLAS itself sits on the **L2 target dispenser** (`withheldAmount`), not on L1. There is **no L1-side admin setter** for this map — it is only mutated by netting and by `syncWithheldAmount` from an L1 processor.
> **Precondition assumed for this migration:** no withheld amount was ever synced back to L1, i.e. `mapChainIdWithheldAmounts == 0` for every chain on the current Dispenser. Under that assumption the new Dispenser starting at 0 is already consistent — there is no L1 reconciliation to do. **Verify this on-chain per chain before starting** (read `mapChainIdWithheldAmounts(chainId)` on the live Dispenser). If any is non-zero, stop and reconcile it first — the steps below do not cover a non-zero L1 withheld state.

**Re-pointed / wired:**
- `Tokenomics.dispenser` via `Tokenomics.changeManagers` — gates `refundFromStaking` and staking accounting.
- `Treasury.dispenser` via `Treasury.changeManagers` — gates `withdrawToAccount`.
- `Dispenser.voteWeighting` via `Dispenser.changeManagers(0, newVoteWeighting)` — the Dispenser proxy is initialized with a **zero** `voteWeighting` (VoteWeighting does not exist yet — it binds the proxy address), then wired here once VoteWeighting is deployed. `VoteWeighting.dispenser` is **not** a re-point: it is an immutable set to the Dispenser proxy at VoteWeighting's construction.
- `Dispenser.setDepositProcessorChainIds(newProcessors, chainIds)`.

**Hard immutable couplings (force the cascade):**
- `DefaultDepositProcessorL1.l1Dispenser` is `immutable` → every L1 deposit processor must be redeployed with `l1Dispenser = newDispenserProxy`.
- `DefaultTargetDispenserL2.l1DepositProcessor` is `immutable` → every L2 target dispenser must be redeployed against its new L1 processor and migrated over.
- `Dispenser.retainer` / `retainerHash` are `immutable` → chosen at deploy; the retainer (address, chainId) **must be a nominee in VoteWeighting** or `retain()` breaks.
- `VoteWeighting.dispenser` is `immutable` → set to the Dispenser **proxy** address at construction; this is what makes the deploy order below load-bearing.

## 5. Contracts in scope

- **L1 core:** `Dispenser` (new, behind `DispenserProxy`), new `VoteWeighting`, plus repoints on `Tokenomics`, `Treasury`.
- **L1 deposit processors (all redeployed):** `ArbitrumDepositProcessorL1`, `GnosisDepositProcessorL1`, `OptimismDepositProcessorL1` (used for Optimism, Base, Celo, Mode), `PolygonDepositProcessorL1`, and `EthereumDepositProcessor` (L1-only mainnet staking — no L2 side).
- **L2 target dispensers (all migrated):** `ArbitrumTargetDispenserL2`, `GnosisTargetDispenserL2`, `OptimismTargetDispenserL2` (Optimism, Base, Celo, Mode), `PolygonTargetDispenserL2`.

## 6. Migration procedure

Governance note: L1 `changeManagers` / `setDepositProcessorChainIds` / `setPauseState` are `owner`-gated (DAO Timelock). L2 `pause` / `migrate` / `updateWithheldAmountMaintenance` are `owner`-gated on the L2 dispenser (governance reaches it via the chain's bridge mediator — see the OP-stack proposal pattern in `scripts/proposals/`). Confirm the owner per chain before drafting each proposal.

### Phase 0 — Pre-flight (verify, don't change)

1. Read `mapChainIdWithheldAmounts(chainId)` on the **live** Dispenser for every chain → confirm all `0` (§4 precondition). Record `withheldAmount` on each **L2** target dispenser (this OLAS travels with the migration).
2. Snapshot the current nominee set and each nominee's `mapLastClaimedStakingEpochs` / any pending (unclaimed) staking incentives.
3. Confirm the intended `retainer` (address, chainId) and that it will be nominated in VoteWeighting on the new stack.
4. **Assert non-zero staking params on the live Tokenomics before wiring the new Dispenser.** The new Dispenser dropped the default-staking-param fallback; a fresh nominee's cursor starts at the current epoch (greenfield-cursor property), so historical epochs are never traversed — but the current epoch's `StakingPoint` must carry non-zero `maxStakingIncentive` / `minStakingWeight` or the first claims silently distribute zero incentives (no over-payment, just nothing paid). Verify on the live Tokenomics proxy:
   ```bash
   cast call <TokenomicsProxy> "mapEpochStakingPoints(uint256)(uint96,uint96,uint16,uint8)" $(cast call <TokenomicsProxy> "epochCounter()(uint32)")
   # -> assert maxStakingIncentive (2nd) != 0 and minStakingWeight (3rd) != 0
   ```

### Phase 1 — Pause and settle the OLD stack

5. `Dispenser.setPauseState(StakingIncentivesPaused)` on the old Dispenser.
6. Have all active nominees **claim outstanding staking incentives** up to the current epoch on the old stack. Anything unclaimed here is only ever claimable on the old Dispenser — settle now.
7. Process/drain any **outstanding queued requests** on each L2 target dispenser (the `migrate()` NatSpec requires this — outstanding queued requests are handled by the DAO on the L2 side before migration).

### Phase 2 — Deploy the new stack

Deploy order is load-bearing: the Dispenser proxy must exist before VoteWeighting (which binds the proxy as an immutable), and the Dispenser proxy is initialized with a **zero** `voteWeighting` because VoteWeighting does not exist yet. This breaks the otherwise-circular dependency.

8. Deploy the **new Dispenser behind `DispenserProxy`**:
   - **Implementation** ctor takes only the bytecode immutables `(_olas, _tokenomics, _retainer)` (`deploy_07a_dispenser.sh`; `_tokenomics` is the Tokenomics **proxy** address, `_retainer` is `bytes32`). The script also locks the standalone implementation post-deploy.
   - **Proxy** ctor is `DispenserProxy(implementation, initData)` where `initData = initialize(_treasury, voteWeighting = 0, _maxNumClaimingEpochs, _maxNumStakingTargets)` (`deploy_07b_dispenser_proxy.sh`). The proxy delegatecall-initializes the impl, the deployer becomes proxy owner atomically, and staking incentives start `StakingIncentivesPaused`. `maxNumClaimingEpochs` / `maxNumStakingTargets` are set once here (no runtime setter) — pick them carefully.
9. Deploy the **new `VoteWeighting(ve, dispenserProxy)`** — `dispenser` is immutable, bound to the Dispenser proxy address from step 8.
10. Deploy the **new L1 deposit processors** (all on ETH mainnet L1), each with `l1Dispenser = dispenserProxy` (step 8):
    - Bridge-paired processors — Arbitrum `staking/deploy_02_arbitrum_deposit_processor.sh`, Gnosis `deploy_03`, Optimism `deploy_04`, Celo `deploy_05`, Polygon `deploy_06`, Base `deploy_07`, Mode `deploy_11`. Each binds to its L2 bridge and gets its `l2TargetDispenser` wired in step 15.
    - **ETH mainnet is L1-only — a different contract and script.** `EthereumDepositProcessor` (`staking/deploy_08_eth_deposit_processor.sh`, ctor `(olas, dispenserProxy, stakingFactory, timelock)`) has **no** bridge relayer, **no** `l2TargetDispenser`, and **no** corresponding L2 target dispenser — mainnet staking settles on L1 directly. It has no step-11 L2 deploy and no step-15 link, and Phase 3 does not apply to it.
11. Deploy the **new L2 target dispensers** — one per L2, each with `l1DepositProcessor = <its new L1 processor from step 10>`, from that chain's subfolder: Arbitrum `staking/arbitrum/deploy_02_arbitrum_target_dispenser.sh`, Gnosis `gnosis/deploy_03`, Optimism `optimism/deploy_04`, Celo `celo/deploy_05`, Polygon `polygon/deploy_06`, Base `base/deploy_07`, Mode `mode/deploy_11`. **No ETH entry** — ETH is L1-only (step 10).

### Phase 3 — Migrate each L2 target dispenser (per chain)

For every chain with an L2 dispenser (Arbitrum, Gnosis, Optimism, Base, Polygon, Celo, Mode):

12. `pause()` the **old** L2 dispenser (`migrate` requires paused).
13. `migrate(newL2TargetDispenser)` on the old L2 dispenser — transfers its **full OLAS balance** (withheld + any residual) to the new one, zeroes the old owner and locks it permanently (one-way; the old dispenser is dead after this). The `Migrated` event surfaces both the migrated balance and the `withheldAmount` to restore.
14. On the **new** L2 dispenser, `updateWithheldAmountMaintenance(withheldAmount)` to re-establish its `withheldAmount` = the **emitted** withheld value (not necessarily the migrated balance; it deploys at 0).
15. Wire the L2↔L1 link: `setL2TargetDispenser(newL2)` on the new L1 processor (`staking/script_02_set_target_dispenser_l2_all.sh` for all chains, or `script_01_set_target_dispenser_l2.sh` per chain; hardhat `staking/deploy_09_set_targer_dispensers.js` is the equivalent), and the corresponding L2-side source binding, so cross-chain messages authenticate against the new pair. (ETH is skipped — no L2 side.) **Polygon** needs one extra L1 binding — `script_03_set_deposit_processor_l1_polygon.sh` (the `fxRootTunnel` link); `multi_deploy_01` runs it automatically for Polygon, but it must be run explicitly if the per-chain scripts are used by hand.

### Phase 4 — Re-point L1 wiring (while still paused)

16. `Dispenser.changeManagers(0, newVoteWeighting)` — wire the real VoteWeighting into the Dispenser proxy (initialized with a zero `voteWeighting` in step 8), via `scripts/deployment/script_dispenser_change_managers.sh` (it passes `treasury = 0`, a no-op, and the new `voteWeighting`). This same script is also how a *future* standalone VoteWeighting redeploy is repointed onto the existing Dispenser. The setter requires the paused state, satisfied by construction. (There is **no** `VoteWeighting.changeDispenser` call — `VoteWeighting.dispenser` is immutable, set in step 9.)
17. `Tokenomics.changeManagers(0, 0, newDispenser)`.
18. `Treasury.changeManagers(0, 0, newDispenser)`.
19. `Dispenser.setDepositProcessorChainIds(newProcessors, chainIds)` on the new Dispenser (`staking/deploy_10_set_deposit_processors.js`) — include the `EthereumDepositProcessor` under the mainnet chainId alongside the L2 processors.

### Phase 5 — Re-nominate and resume

20. Nominate the staking targets **and the retainer** in VoteWeighting → fires `addNominee` on the new Dispenser, setting fresh cursors at the current epoch (clean because Phase 1 settled everything). Do **not** route any target through `removeNominee` first — removal is **terminal in VoteWeighting** (`_addNominee` reverts `NomineeRemoved`; `mapRemovedNominees[hash]` is set on removal and never cleared). Note the Dispenser-side `mapRemovedNomineeEpochs` brick described in §2 is **fixed** on the new Dispenser (#310, vuln-list item #25 — `addNominee` now clears it), so on the new stack the standing reason is the VoteWeighting side, which is not fixed.
21. `Dispenser.setPauseState(Unpaused)`. (The Dispenser rejects going live while `voteWeighting == address(0)`, so this only succeeds after step 16.)
22. **Withheld re-sync (only if a carried L2 balance is material):** the new L1 Dispenser starts with `mapChainIdWithheldAmounts = 0` and does not know about the balance carried in step 14, so it will not *net* the next distribution against it (it bridges fresh OLAS; funds are not lost, the L2 stays "ahead"). To restore netting, trigger a withheld sync from the new L2 dispenser up to the new L1 Dispenser after wiring. If the carried balance is ~0/dust, skip.

### Deploy command reference (the scriptable Phase 2 / 4 steps)

Prereqs sourced: `ETHERSCAN_API_KEY` (verification), `ALCHEMY_API_KEY_MAINNET` (ETH mainnet RPC — every L1
deploy) and `ALCHEMY_API_KEY_MATIC` (Polygon RPC). Fill `scripts/deployment/globals_mainnet.json` and each
chain's staking globals first. Order is load-bearing (see the `deploy_07b_dispenser_proxy.sh` header).

```bash
# 1. Dispenser implementation + proxy on ETH mainnet (the proxy initializes with voteWeighting = 0)
./scripts/deployment/deploy_07a_dispenser.sh mainnet
./scripts/deployment/deploy_07b_dispenser_proxy.sh mainnet

# 2. Deploy VoteWeighting(ve, dispenserProxy) in autonolas-governance (binds this proxy as an immutable),
#    then wire the real VoteWeighting into the still-paused Dispenser proxy:
./scripts/deployment/script_dispenser_change_managers.sh mainnet

# 3a. ETH mainnet is L1-only — one contract, deployed directly for explicitness (no L2 dispenser, no link):
./scripts/deployment/staking/deploy_08_eth_deposit_processor.sh mainnet
#     (multi_deploy_01 eth_mainnet would also work — it globs to exactly this deploy_08 … mainnet call and
#      hits its own `exit 0` ETH guard before any L2 step — but the direct call keeps the single-contract
#      nature explicit and skips the wrapper's L2 machinery entirely.)

# 3b. L2 chains — L1 deposit processor + L2 target dispenser + link, one call each (same order as steps 10/11).
#     For Polygon the wrapper also runs script_03_set_deposit_processor_l1_polygon.sh (the fxRootTunnel binding)
#     automatically; that extra step is easy to miss if the per-chain scripts are run by hand instead.
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh arbitrum_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh gnosis_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh optimism_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh celo_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh polygon_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh base_mainnet
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh mode_mainnet

# 4. Register the deposit processors on the Dispenser (reads ./globals.json — point it at the mainnet globals):
node scripts/deployment/staking/deploy_10_set_deposit_processors.js
```

The old-stack pause/settle (Phase 1), each L2 `migrate` (Phase 3), the `Tokenomics` / `Treasury` re-point and
the final `setPauseState(Unpaused)` (Phase 4/5) are DAO proposals, not scripts — follow the phases above.

## 7. Post-migration verification

- New Dispenser: `tokenomics`, `treasury`, `voteWeighting`, `mapChainIdDepositProcessors[chainId]` all point at the new contracts; `retainerHash` matches the intended retainer.
- `Tokenomics.dispenser == Treasury.dispenser == newDispenser`, and `VoteWeighting.dispenser == newDispenser` (immutable, set at deploy).
- Each new L1 processor: `l1Dispenser == newDispenser`, `l2TargetDispenser == newL2`.
- Each new L2 dispenser: `l1DepositProcessor == newL1Processor`, `withheldAmount` matches the restored value; each **old** L2 dispenser: `owner == address(0)` (bricked).
- Dry-run one small staking distribution + claim per chain before the first full epoch distribution.
- The retainer is an active VoteWeighting nominee; `retain()` succeeds.

### Release artifacts to regenerate (part of the release checklist, not optional)

The Dispenser rework changed several ABIs. Regenerate at redeploy so downstream consumers (deploy scripts, frontends, indexers) do not read stale definitions:
- **`abis/<ver>/Dispenser.json`** — the 3-arg constructor `(olas, tokenomics, retainer)`, the new `initialize` / `changeManagers(address,address)` / `changeImplementation`, and the `calculateStakingIncentives` return tuple that now includes the sparse `zeroWeightEpochs[]`.
- **`abis/<ver>/DefaultTargetDispenserL2.json`** (and every chain variant) — the 4-arg `Migrated(address,address,uint256,uint256)`. Any indexer/subgraph keyed on the old 3-arg topic0 must handle both during the cutover.
- **`docs/configuration.json`** — the new `dispenserProxyAddress` and every repointed address, updated **only after** the on-chain rewiring is complete.
- **`scripts/audit_chains/audit_contracts_setup.js` — delete the standing-red exemption.** `checkBytecode`'s Tier-1 length mismatch is blocking (issue #322), and the script carries a dated `DELIBERATE STANDING-RED DECISION (2026-08)` comment saying the audit is *expected* to `exit(1)` while several deployed implementations still predate the in-repo code (the mainnet / Optimism / Base LiquidityManager impls and the proxied Dispenser). Once an implementation is redeployed and `configuration.json` is repointed above, that contract should go green — **remove the comment in the same PR**, once the last of them clears. A stale "expected red" note is worse than none: it keeps excusing failures after the reason for them has gone.

## 8. Rollback / risk notes

- Any nominee that fails to claim in Phase 1 forfeits its old-stack unclaimed incentives (only the old Dispenser can pay them, and it is being retired). Chase settlements before Phase 3.

## 9. Open items to confirm before executing

- **On-chain precondition:** `mapChainIdWithheldAmounts == 0` on all chains (Phase 0.1). The procedure assumes this; a non-zero L1 withheld state is out of scope here.
- **VoteWeighting semantics (external repo):** behaviour of `checkpointNominee` / `nomineeRelativeWeight` for a freshly-nominated target (`checkpointNominee` reverts `NomineeDoesNotExist` for a never-added nominee; the Dispenser guards this). Confirm against the deployed build in [`valory-xyz/autonolas-governance`](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/VoteWeighting.sol) at the pinned deploy tag.
- **Per-chain owner** of each L2 target dispenser (for the pause/migrate/maintenance proposals) and the L2 source-binding call used in step 15 (varies by bridge: Arbitrum / Gnosis AMB / OP-stack (Optimism, Base, Celo, Mode) / Polygon Fx).
