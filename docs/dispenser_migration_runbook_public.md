# Dispenser migration runbook (redeploy + full staking-stack cutover)

> **Scope.** This runbook covers redeploying **both** `VoteWeighting` and the `Dispenser` and cutting the
> whole cross-chain staking stack over to them. Code references link to `main` of the source repo (line
> numbers drift if the contracts change — re-verify against a deploy tag before executing).

Historical dated reads and fork examples below are reference material, not current
execution inputs. Re-read and reconcile the actual state at the chosen cutover
blocks; record execution values and evidence in the private ledger (§7.1).

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

**L1 balances and credits are separate.** In the normal claim path the Dispenser is a pass-through: staking claims do `Treasury.withdrawToAccount(address(this), 0, amount)` → `IToken(olas).transfer(depositProcessor, amount)` in the same tx; dev incentives go Treasury→user directly. Returns to inflation are accounting calls (`Tokenomics.refundFromStaking`, dispenser-gated), not balances. That flow does not prove every historical balance is zero; verify actual balances and account for any residual separately.

**The only cross-chain state — `mapChainIdWithheldAmounts`.** This tracks OLAS already bridged to an L2 that staking targets could not absorb, netted against the *next* distribution to that chain. The OLAS itself sits on the **L2 target dispenser**, not on L1 — but note the L2's own `withheldAmount` counter is **zeroed once that amount has been synced up to L1**, so an L2 dispenser can hold the OLAS while reporting `withheldAmount == 0`. The balance and the counter are not the same reading.

The map is mutated by netting, by `syncWithheldAmount` from an L1 processor, and by **`syncWithheldAmountMaintenance`** — an `owner`-gated L1 admin setter in [`Dispenser.sol`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Dispenser.sol) that exists precisely to restore state an L2 failed to deliver. (An earlier revision of this runbook said there was no L1-side setter for this map; that was wrong, and it made a non-zero L1 state look unrecoverable.)
> **Read per chain before starting:** `mapChainIdWithheldAmounts(chainId)` on the live Dispenser, and on each L2 target dispenser **both** `withheldAmount` **and the OLAS balance**. Two cases:
> - **All zero on L1.** Still reconcile balances, unpaid obligations and outstanding sync messages: a callback can be in flight despite a zero credit reading. The new Dispenser starting at 0 is not proof of completed reconciliation.
> - **Any non-zero on L1.** That OLAS is sitting on the chain's L2 dispenser with the L2 counter already zeroed. Where the tokens remain available, their accounting can be restored — see step 14 and §7 — but it is silently dropped if steps 13/14 are run as though the L1 value were 0. Do not skip the balance read.

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
- **L1 deposit processors (all redeployed):** `ArbitrumDepositProcessorL1` **deployed twice — once for Arbitrum (42161) and once for Robinhood (4663)**, `GnosisDepositProcessorL1`, `OptimismDepositProcessorL1` (used for Optimism, Base, Celo, Mode), `PolygonDepositProcessorL1`, and `EthereumDepositProcessor` (L1-only mainnet staking — no L2 side). Robinhood's `l1Dispenser` is `immutable`, so skipping its redeploy leaves step 19 registering the old processor against the old Dispenser.
- **L2 target dispensers (all migrated):** `ArbitrumTargetDispenserL2` **twice — Arbitrum (42161) and Robinhood (4663)**, `GnosisTargetDispenserL2`, `OptimismTargetDispenserL2` (Optimism, Base, Celo, Mode), `PolygonTargetDispenserL2`. Robinhood's `l1DepositProcessor` is `immutable`, so a Robinhood dispenser left un-migrated stays bound to the old L1 processor.

## 6. Migration procedure

Governance note: L1 `changeManagers` / `setDepositProcessorChainIds` / `setPauseState` are `owner`-gated (DAO Timelock). L2 `pause` / `migrate` / `updateWithheldAmountMaintenance` are `owner`-gated on the L2 dispenser (governance reaches it via the chain's bridge mediator — see the OP-stack proposal pattern in `scripts/proposals/`). Confirm the owner per chain before drafting each proposal.

### Execution order and checkpoints

Replacement contracts may be deployed before settling and pausing the old stack. Keep the old stack operating during deployment. The remaining migration actions follow the dependencies below; some require separate governance executions and destination-chain confirmations. The detailed phases and step numbers below remain the transaction reference.

1. **Prepare deployment.** Confirm reviewed builds, deployment parameters, retainer and intended owners. Use a pinned commit's globals/configuration as the old-address reference, verified against live contracts.

2. **Deploy and verify replacements.** Follow the [deployment/checkpoint guide](../scripts/deployment/staking/README.md), including VoteWeighting address handoffs, audits before/after processor linking, configuration and ownership transfers. The new **L1 Dispenser starts staking-paused**; new L2 dispensers start unpaused. Resolve unexpected audit differences before proceeding.

3. **Prepare migration governance.** Collect fresh balances, claim cursors, unpaid requests and outstanding messages under Phase 0 and §7. Prepare the actual payloads and rehearse the remaining migration and distributions on pinned forks using the deployed replacements. Record evidence privately. Refresh relevant state before execution and revise stale payloads through governance.

4. **Settle, then pause the old stack.** Follow Phase 1. Before pausing old staking claims, confirm that every staking programme currently used in Pearl has enough available rewards to cover the planned funding interruption, including re-voting, vote activation, epoch settlement and bridge delivery. Arrange any required top-ups before the pause. Settle outstanding claims and retainer amounts, then pause old staking claims within the same epoch.

5. **Migrate and connect.** Follow Phases 3–4. Confirm historical deliveries before each irreversible L2 migration. After ownership handover, governance migrates the tokens, restores accounting from the execution-time balance and calls `processDataMaintenance(..., true)` for verified unpaid requests. Complete or verify the required connections and manager changes. Keep new L1 claims paused.

6. **Reconcile and restart.** Follow Phase 5. Sync available reserves and confirm receipt on the active L1 Dispenser. On Gnosis, the owner requests the sync after restoration and unpaid replay; anyone then relays it in a separate transaction with the AMB idle, without another governance vote. Other supported L2s use the standard owner sync. After reconciliation and simulation pass, unpause, nominate targets/retainer, re-vote and verify distributions when voting and epoch timing permit.

**Legacy Celo:** include the separate governance action to pause the legacy dispenser and migrate its legacy-token balance into DAO-controlled Celo custody. Refresh obligations and verify the recovery payload before execution. Keep this asset separate from current-token maintenance and sync amounts; any subsequent conversion or redemption requires a separate decision.

**Staking-instance migration.** For each staking programme currently used in Pearl, identify the existing instance and its intended v0.4.0 replacement. Create and verify the replacement, arrange nomination, voting and first funding, and coordinate the movement of Pearl services. Agree how long the existing instance must remain funded. Where an approved existing instance needs temporary funding through the new Dispenser, verify that path before relying on it. Retire the old instance only after services have moved and remaining reward and withdrawal obligations have been handled.

### Phase 0 — Pre-flight (verify, don't change)

1. Read `mapChainIdWithheldAmounts(chainId)` on the **live** Dispenser for every chain, and on each **L2** target dispenser read **both** its `withheldAmount` and its **OLAS balance**; record them all. §4 covers both outcomes; start a private ledger as specified in §7 and include earlier outstanding obligations and messages. A non-zero L1 value must be reconciled, not copied as additional credit. The L2 counter and balance can diverge after a sync, and it is the **balance** that travels with the migration and that step 14 restores, so do not skip the balance read.
2. Snapshot the current nominee set and each nominee's `mapLastClaimedStakingEpochs` / any pending (unclaimed) staking incentives.
3. Confirm the intended `retainer` (address, chainId) and that it will be nominated in VoteWeighting on the new stack.
4. **Assert non-zero staking params on the live Tokenomics before wiring the new Dispenser.** The new Dispenser dropped the default-staking-param fallback; a fresh nominee's cursor starts at the current epoch (greenfield-cursor property), so historical epochs are never traversed — but the current epoch's `StakingPoint` must carry non-zero `maxStakingIncentive` / `minStakingWeight` or the first claims silently distribute zero incentives (no over-payment, just nothing paid). Verify on the live Tokenomics proxy:
   ```bash
   cast call <TokenomicsProxy> "mapEpochStakingPoints(uint256)(uint96,uint96,uint16,uint8)" $(cast call <TokenomicsProxy> "epochCounter()(uint32)")
   # -> assert maxStakingIncentive (2nd) != 0 and minStakingWeight (3rd) != 0
   ```

### Phase 1 — Settle, then pause the OLD stack

The order is load-bearing. The old Dispenser reverts `Paused()` in `claimStakingIncentives` and `claimStakingIncentivesBatch` while it is `StakingIncentivesPaused` (or `AllPaused`), so a claim attempted after the pause cannot run. Settle first, then pause, **in the same epoch**: an epoch closed by `Tokenomics.checkpoint()` after the last claim becomes claimable, and it is not settled.

5. Have every nominee **claim outstanding staking incentives** up to the current epoch on the old Dispenser, and call `retain()` for the retainer. Anything unclaimed here is only ever claimable on the old Dispenser. Claims are permissionless, so the settlement does not depend on each nominee acting.
   The old Dispenser's `maxNumClaimingEpochs` is **`1`** (read 2026-10-07), so each claim, and each `retain()`, covers a single epoch: a nominee *N* epochs behind needs *N* claims. `claimStakingIncentivesBatch` settles many targets per call (up to `maxNumStakingTargets` per chain), but still one epoch per call, and a target already at the current epoch reverts the batch (`Overflow`), so drop targets from later batches as they catch up. As of 2026-10-07 (epoch 50, 14-day epochs) the 20 staking nominees are 1 to 6 epochs behind, so about six shrinking batch calls, and the retainer is 26 behind, so 26 `retain()` calls. Plan the calls before drafting the step-6 proposal.
   **Ineligible nominee exception:** if a claim reverts, have the recorded deployer restore eligibility where appropriate and settle before the pause. Otherwise record the nominee, affected epoch range, allocation evidence and revert reason as an unresolved exception, and obtain an explicit governance disposition before retiring the old claim path. Do not mark it settled or assume the replacement stack recovers it.
   **Confirm settled or explicitly dispositioned:** for every nominee outside those recorded exceptions, the retainer included, `mapLastClaimedStakingEpochs(nomineeHash)` on the old Dispenser equals `epochCounter()` on Tokenomics. Enumerate the nominees from VoteWeighting with `getNumNominees()` and `getNominee(i)` for `i` in `1..N`; on the live VoteWeighting the retainer is nominee `1`.
   ```bash
   # nomineeHash = keccak256(abi.encode(account, chainId)), with the account as bytes32
   h=$(cast keccak $(cast abi-encode "f(bytes32,uint256)" <account> <chainId>))
   cast call <oldDispenser> "mapLastClaimedStakingEpochs(bytes32)(uint256)" $h
   cast call <TokenomicsProxy> "epochCounter()(uint32)"
   # -> the two are equal for every settled nominee; recorded exceptions require a disposition
   #    for a removed nominee (mapRemovedNomineeEpochs(h) != 0)
   #    the cursor stops at its removal epoch instead
   ```
6. `Dispenser.setPauseState(StakingIncentivesPaused)` on the old Dispenser, executed **in the same epoch** as the last claims of step 5. Claims are permissionless and the pause is a DAO proposal, so time the proposal's execution against the claims: if a `Tokenomics.checkpoint()` lands between the last claim and the pause, settle the newly closed epoch before the pause executes. `retain()` is not pause-gated, so the retainer can also finish after the pause.
   **Confirm paused:** `paused()` on the old Dispenser reads `2` (`StakingIncentivesPaused`), and the step-5 settlement check or explicit exception disposition still holds for every nominee.
7. Process/drain any **outstanding queued requests** on each L2 target dispenser (the `migrate()` NatSpec requires this — outstanding queued requests are handled by the DAO on the L2 side before migration).

### Phase 2 — Deploy the new stack

Deploy order is load-bearing: the Dispenser proxy must exist before VoteWeighting (which binds the proxy as an immutable), and the Dispenser proxy is initialized with a **zero** `voteWeighting` because VoteWeighting does not exist yet. This breaks the otherwise-circular dependency.

8. Deploy the **new Dispenser behind `DispenserProxy`**:
   - **Implementation** ctor takes only the bytecode immutables `(_olas, _tokenomics, _retainer)` (`deploy_07a_dispenser.sh`; `_tokenomics` is the Tokenomics **proxy** address, `_retainer` is `bytes32`). The script also locks the standalone implementation post-deploy.
   - **Proxy** ctor is `DispenserProxy(implementation, initData)` where `initData = initialize(_treasury, voteWeighting = 0, _maxNumClaimingEpochs, _maxNumStakingTargets)` (`deploy_07b_dispenser_proxy.sh`). The proxy delegatecall-initializes the impl, the deployer becomes proxy owner atomically, and staking incentives start `StakingIncentivesPaused`. `maxNumClaimingEpochs` / `maxNumStakingTargets` are set once here (no runtime setter) — pick them carefully.
9. Deploy the **new `VoteWeighting(ve, dispenserProxy)`** — `dispenser` is immutable, bound to the Dispenser proxy address from step 8.
10. Deploy the **new L1 deposit processors** (all on ETH mainnet L1), each with `l1Dispenser = dispenserProxy` (step 8). On mainnet the processor scripts read that address from `dispenserProxyAddress` in `scripts/deployment/globals_mainnet.json`, where step 8's `deploy_07b_dispenser_proxy.sh` records it, and stop if it is unset. The staking globals' `dispenserAddress` still holds the **old** Dispenser and is not used on mainnet: `l1Dispenser` is immutable, so a processor bound to the wrong address can only be redeployed. Use the `.sh` scripts: the Hardhat `deploy_*_deposit_processor.js` scripts read that `dispenserAddress` and run only when connected to Sepolia with Sepolia globals.
    - Bridge-paired processors — Arbitrum `staking/deploy_02_arbitrum_deposit_processor.sh`, Gnosis `deploy_03`, Optimism `deploy_04`, Celo `deploy_05`, Polygon `deploy_06`, Base `deploy_07`, Mode `deploy_11`, Robinhood `deploy_13_robinhood_deposit_processor.sh` (chainId 4663, the second Arbitrum-Orbit chain — same processor type as Arbitrum). Each binds to its L2 bridge and gets its `l2TargetDispenser` wired in step 15.
    - **ETH mainnet is L1-only — a different contract and script.** `EthereumDepositProcessor` (`staking/deploy_08_eth_deposit_processor.sh`, ctor `(olas, dispenserProxy, stakingFactory, timelock)`) has **no** bridge relayer, **no** `l2TargetDispenser`, and **no** corresponding L2 target dispenser — mainnet staking settles on L1 directly. It has no step-11 L2 deploy and no step-15 link, and Phase 3 does not apply to it.
11. Deploy the **new L2 target dispensers** — one per L2, each with `l1DepositProcessor = <its new L1 processor from step 10>`, from that chain's subfolder: Arbitrum `staking/arbitrum/deploy_02_arbitrum_target_dispenser.sh`, Gnosis `gnosis/deploy_03`, Optimism `optimism/deploy_04`, Celo `celo/deploy_05`, Polygon `polygon/deploy_06`, Base `base/deploy_07`, Mode `mode/deploy_11`, Robinhood `robinhood/deploy_02_robinhood_target_dispenser.sh`. **No ETH entry** — ETH is L1-only (step 10).

### Phase 3 — Migrate each L2 target dispenser (per chain)

For every chain with an L2 dispenser (Arbitrum, Gnosis, Optimism, Base, Polygon, Celo, Mode, Robinhood):

Robinhood (chainId 4663, registered in the live Dispenser since proposal 16) holds no OLAS and carries no L1 credit, so as of the 2026-10-05 reading its `migrate` carries nothing and step 14 restores `0`. Treat that as a dated reading, not the procedure: step 14 restores the **new Robinhood dispenser's actual OLAS balance at maintenance execution** like every other chain, so if OLAS arrives before the cutover, restore that balance rather than `0`. Either way it still redeploys and rewires with the rest, because `l1DepositProcessor` / `l1Dispenser` are `immutable` and a chain left unregistered at step 19 is unroutable.

12. `pause()` the **old** L2 dispenser (`migrate` requires paused).

    **Gate before step 13 — nothing in flight to this chain, ever.** `migrate()` sweeps the balance once, and the dispensers being migrated here have no way to pass on anything that arrives afterwards: a late token leg lands on the dead dispenser for good, and a late message leg reverts there. Bridges can deliver long after the send — an OP-stack relay or a Polygon state sync that failed can be replayed later by anyone — so the check covers **every batch the old L1 processor has ever sent**, not only the step-5 settlement. The L1 processor numbers its batches: `stakingBatchNonce()` is the next one, so the batches are nonces `0` to `stakingBatchNonce() - 1`, each sent with its token leg (when it transferred OLAS) in the same transaction. For each of them:
    - **Message leg processed.** The old L2 dispenser records each batch as `processedHashes(keccak256(abi.encode(nonce, 1, <old L1 processor>)))`:
      ```bash
      n=$(cast call <oldL1Processor> "stakingBatchNonce()(uint256)")
      for i in $(seq 0 $((n-1))); do
        h=$(cast keccak $(cast abi-encode "f(uint256,uint256,address)" $i 1 <oldL1Processor>))
        echo "$i $(cast call --rpc-url <L2 rpc> <oldL2Dispenser> "processedHashes(bytes32)(bool)" $h)"
      done
      # -> true for every nonce (verified live on Optimism 2026-10-07: nonces 8 and 9 read true, the next unsent
      #    nonce reads false)
      ```
    - **Token leg delivered, with the OLAS on the old dispenser.** For every batch that transferred OLAS, the bridge delivery **succeeded**, and its delivery transaction carries an OLAS `Transfer` (or mint) of that amount **to the old L2 dispenser**. A delivery that failed and is still replayable is in flight, whatever its age:
      - **Arbitrum, Robinhood:** both retryable tickets, the token gateway's and the message's, are **redeemed**. None created by the old processor is still unredeemed and unexpired.
      - **Gnosis:** the Omnibridge `relayTokens` message is **executed successfully** on the Gnosis AMB (`messageCallStatus(messageId)` is `true`).
      - **Polygon:** the `depositFor` state sync **succeeded**: `StateCommitted(stateId, true)` on Polygon's `StateReceiver` (`0x0000000000000000000000000000000000001001`), or, where it was `false`, a later successful `StateSyncReplay(stateId)` (and `failedStateSyncs(stateId)` now empty). `lastStateId()` is **not** evidence: it advances before delivery is attempted, and failed syncs are recorded separately for replay.
      - **OP-stack (Optimism, Base, Celo, Mode):** the deposit is **relayed**: `successfulMessages(<message hash>)` is `true` on the L2 `CrossDomainMessenger` (`0x4200000000000000000000000000000000000007`). A relay that failed stays replayable until it succeeds.
    - **Queued requests recorded.** List every request still queued on the old L2 dispenser (`StakingRequestQueued` with `queuedHashes(<queueHash>)` still `true`). A message processed while the dispenser is paused (step 12) is queued rather than deposited, as can be one processed earlier against a short balance. Their OLAS migrates with the balance at step 13; they are replayed on the new dispenser at step 14 below.

    **Future migrations of the new builds.** The L2 dispensers deployed in this cutover add `forward()`: after `migrate()`, anyone can move OLAS that reaches the old address on to `migratedTo`. In a later migration, a late claim is recovered on the new dispenser, **before any withheld sync**, in three steps: `forward()` the late token leg from the old dispenser; apply the step-14 rule again — `updateWithheldAmountMaintenance(<new dispenser's OLAS balance>)`; then replay the claim's message with `processDataMaintenance(data, true)`. The arrival time of the forwarded OLAS cannot pick the flag on its own: L1 nets a claim against OLAS already withheld on L2, so a 100-OLAS claim can bridge only 60 and rely on 40 that migrated with the balance and sits in the restored `withheldAmount`. Replaying it with `false` would leave that 40 counted as withheld with nothing behind it, and `true` without the re-restore reverts `Overflow` (100 against 40). Re-restoring to the balance and replaying with `true` ends with `withheldAmount` equal to the balance in every case: `0` / `0` for that netted claim, and an untouched genuine withheld credit when the late claim was fully bridged. **Replay unprocessed batches whole; for already-processed batches, recover only requests still queued, following the separate queued-request procedure.** The old dispenser's `processedHashes` stays readable after `migrate()`. The new dispenser does not inherit it, so it cannot prevent paying a request the old dispenser already paid: the operator must select only unpaid requests. For an already-processed batch, still `forward()` the late token leg and re-restore, then put all its requests still queued (`queuedHashes` still `true` on the old dispenser) in one call with the original `batchHash`: that call marks the hash processed on the new dispenser, and a second call with it reverts `AlreadyDelivered`. If the withheld sync has already run, this procedure does not apply: the restored credit is on L1 by then. The dispensers retired in this cutover predate `forward()`, which is why the gate above is load-bearing here.
    **A further late `forward()` requires another accounting update.** If another `forward()` executes after `updateWithheldAmountMaintenance`, it increases the new dispenser's OLAS balance without updating `withheldAmount`. Before replaying further requests or syncing withheld amounts, repeat the maintenance update using the new dispenser's actual balance at that update's execution. This full-balance recovery procedure applies only **before any withheld sync**; after a sync, reconcile the credit already recorded on L1 rather than restoring the full L2 balance as new withheld credit.

13. `migrate(newL2TargetDispenser)` on the old L2 dispenser — transfers its **full OLAS balance** (withheld + any residual) to the new one, zeroes the old owner and locks it permanently (one-way; the old dispenser is dead after this). The `Migrated` event surfaces the migrated balance; step 14 restores the new dispenser's actual balance at maintenance execution, including any subsequent arrivals (see step 14 for why the emitted `withheldAmount`, where the event carries one at all, is not the input).
14. On the **new** L2 dispenser, `updateWithheldAmountMaintenance(<final OLAS balance of the new dispenser>)` to re-establish its `withheldAmount` (it deploys at 0). **Pass the new dispenser's actual OLAS balance at maintenance execution, not the emitted `withheldAmount`** — which is what the function's own NatSpec requires for this case: *"[2] Withheld amount update after balance migration to a new contract … The amount here must correspond to … [2] Final OLAS balance of this contract address."*

    **Revalidate the balance for execution.** Include any OLAS forwarded or otherwise received since migration. Do not reuse the Phase-0 snapshot or the migrated amount if the balance has changed. Re-read the new dispenser's OLAS balance as close to maintenance execution as possible and confirm it still matches the encoded amount. A read made while preparing the governance proposal does not fix the execution-time value: `updateWithheldAmountMaintenance(amount)` stores the supplied amount without reading the token balance. If the amount is stale before execution, correct the maintenance payload and follow the required governance process before executing it. After execution, verify the restored accounting against the balance before replaying requests or syncing; if another forward has intervened, repeat the update as described above.

    The two values differ whenever the chain has already synced a withheld amount up to L1: the emitted `withheldAmount` is then `0` (the accounting moved to L1) while `migrate()` still carried a non-zero **balance**. Passing that `0` leaves the OLAS accounted for by neither side — the new L1 Dispenser also starts at `0`, so nothing nets against it and the new L2 dispenser accumulates unusable OLAS while L1 mints fresh. A zero L1 reading does not by itself prove that the balance and emitted counter coincide; outstanding callbacks and unpaid obligations must also be reconciled (§7).

    There is a second reason not to reach for the emitted value: **the deployed L2 dispensers emit the three-argument `Migrated(address,address,uint256)` and do not report `withheldAmount` at all.** The four-argument form is on the *new* build — the contract being migrated **to**, never the one `migrate()` runs on. So at step 13 the migrated balance is the only figure the event gives you — on every chain but Robinhood (4663), whose live dispenser is already the four-argument build and so also reports `withheldAmount`. Robinhood holds nothing as of 2026-10-05, so both figures read `0` there and step 14 restores `0` today; the rule — restore the new dispenser's actual balance at maintenance execution — is unchanged, so restore the actual balance if OLAS has since arrived.

    Verified on a Base fork against the live dispenser `0x9Ec97Be9…b241` (holding 1,380,908.799963024002602865 OLAS at `withheldAmount == 0`): `migrate()` carries the full balance and emits only the amount; `syncWithheldAmount` reverts `ZeroValue` while `withheldAmount` is `0`; and restoring the balance then syncing sends the full amount and consumes one batch nonce.

    Once restored, the amount reaches the new L1 Dispenser through the **ordinary** `syncWithheldAmount` path, which is what re-enables netting (every chain but Gnosis, whose new dispenser requires the split call — see step 20). That cross-chain sync must wait until step 15 has bound the new L2↔L1 pair. If it is run between steps 14 and 15 the **L2 `syncWithheldAmount` call itself succeeds** — it decrements `withheldAmount` and emits the bridge message — but the message then **reverts `WrongMessageSender` on L1 receipt** (`DefaultDepositProcessorL1._receiveMessage`), leaving the L2 decrement with nothing delivered. So run it only after step 15, and confirm at step 20. There is no L1-side shortcut worth taking here: `Dispenser.syncWithheldAmountMaintenance` would require the DAO to supply a `batchHash` for a message that never failed, and `updateHashMaintenance` marks that hash `processed` on the new L1 processor — if it collides with one the new L2 dispenser will genuinely produce (its nonce restarts at 0), that real sync later reverts `AlreadyDelivered`, leaving the L2 reduction without the expected new L1 credit. Use the L2 maintenance call.
    **Replay the queued requests recorded at the gate, right after the restore and before any withheld sync.** Their OLAS migrated with the balance and is now counted in the restored `withheldAmount`, so replay them on the new dispenser with `processDataMaintenance(data, true)`: with `true`, the amount deposited is taken off `withheldAmount`; with `false`, it stays counted as withheld credit while the OLAS has gone to staking. Restoring 100 OLAS and replaying 60 leaves a balance of 40 either way, but `withheldAmount` 40 with `true` and 100 with `false`. Include only requests still unpaid (`queuedHashes` still `true` on the old dispenser), with `data = abi.encode(targets, amounts, batchHash)` using each request's original `batchHash` — the new dispenser's `processedHashes` starts empty — and put all unpaid requests of one batch in a single call, since a second call with the same `batchHash` reverts `AlreadyDelivered`. Do this **before** the step-20 sync: the sync zeroes the L2 `withheldAmount`, after which a `true` replay reverts `Overflow`.
    **Precheck replay eligibility.** Before encoding or executing a replay, verify each included target against the replacement dispenser's factory and reconcile its current emissions limit with the unpaid amount. If eligibility or a cap has changed, resolve the affected obligation before consuming the batch hash. A zero result makes `processDataMaintenance(data, true)` skip that target without payment or a new queue entry, while still consuming `processedHashes(batchHash)`; the amount stays in `withheldAmount`, and the same hash cannot be retried even after re-enabling. A successful call or processed hash is not proof of payment. Keep that unpaid backing separate from free reserve until the recovery or explicit disposition is evidenced in the private ledger.

15. Wire the L2↔L1 link: `setL2TargetDispenser(newL2)` on the new L1 processor (`staking/script_02_set_target_dispenser_l2_all.sh` for the **seven original chains** it lists — Mode included, **Robinhood not** — or `script_01_set_target_dispenser_l2.sh` per chain; the hardhat `staking/deploy_09_set_targer_dispensers.js` is the equivalent **for the original chains only — it has no Mode or Robinhood entry**, so link those two via the shell `script_01_…` route), and the corresponding L2-side source binding, so cross-chain messages authenticate against the new pair. (ETH is skipped — no L2 side.) **Polygon** needs one extra L1 binding — `script_03_set_deposit_processor_l1_polygon.sh` (the `fxRootTunnel` link); `multi_deploy_01` runs it automatically for Polygon, but it must be run explicitly if the per-chain scripts are used by hand. **Robinhood** is **not** in `script_02_set_target_dispenser_l2_all.sh` (that script predates 4663), so link it with the per-chain `script_01_set_target_dispenser_l2.sh robinhood_mainnet` — or the `multi_deploy_01` wrapper, which globs the `deploy_13` / `robinhood/deploy_02` scripts and the generic `script_01` for `robinhood_mainnet`.

### Phase 4 — Re-point L1 wiring (while still paused)

16. `Dispenser.changeManagers(0, newVoteWeighting)` — wire the real VoteWeighting into the Dispenser proxy (initialized with a zero `voteWeighting` in step 8), via `scripts/deployment/script_dispenser_change_managers.sh` (it passes `treasury = 0`, a no-op, and the new `voteWeighting`). This same script is also how a *future* standalone VoteWeighting redeploy is repointed onto the existing Dispenser. The setter requires the paused state, satisfied by construction. (There is **no** `VoteWeighting.changeDispenser` call — `VoteWeighting.dispenser` is immutable, set in step 9.)
17. `Tokenomics.changeManagers(0, 0, newDispenser)`.
18. `Treasury.changeManagers(0, 0, newDispenser)`.
19. `Dispenser.setDepositProcessorChainIds(newProcessors, chainIds)` on the new Dispenser — whitelist every L1 deposit processor, mapping each L2 target chainId (and the mainnet chainId) to its processor. Forge: `staking/deploy_10_set_deposit_processors.sh` (reads all processor addresses + chainIds from the staking globals and the Dispenser from `dispenserProxyAddress` in the root globals, refuses to send unless the proxy's `PROXY_DISPENSER` storage slot holds the implementation `deploy_07a_dispenser.sh` recorded as `dispenserAddress` in the root globals, and that implementation has code, includes the `EthereumDepositProcessor` under the mainnet chainId, the Mode processor and the Robinhood processor (chainId 4663), and re-reads `mapChainIdDepositProcessors` afterwards to confirm each entry took). The Hardhat `staking/deploy_10_set_deposit_processors.js` is not an equivalent on mainnet: it reads the pre-proxy `dispenserAddress` and runs only when connected to Sepolia with Sepolia globals. There is no zero-processor guard in the Dispenser, so a chain left unregistered here resolves to a zero processor and **reverts the claim** — and in the batch path the zero-address call reverts the whole batch, taking the other chains' claims with it.

    **Retired historical generator:** [`scripts/proposals/proposal_10_dispenser_set_deposit_processor_chain_ids.js`](../scripts/proposals/proposal_10_dispenser_set_deposit_processor_chain_ids.js) is preserved only as historical proposal material. It is **not a supported migration workflow**; do not use its output for the current cutover. Use the step-19 registration workflow above, including the ownership/governance requirements for the intended Dispenser.

### Phase 5 — Reconcile while paused, then resume

20. **Restore and replay first, then sync and confirm receipt.** Complete step 14, all unpaid-request replay and the §7 reconciliation for every chain. Keep staking claims on the new L1 Dispenser **paused** throughout. With steps 15 and 19 wired, send each required `syncWithheldAmount` from the new L2, wait for successful destination execution and verify the expected credit on the **new active L1 proxy**. These sync callbacks do not require unpausing L1 claims. Sending the message or observing a lower L2 counter is insufficient. For a reconciled zero reserve, record expected credit `0` and **skip** the sync (`ZeroValue`); also account separately for any unsyncable normalization remainder. Zero readings do not excuse checking outstanding historical messages.
    **Gnosis uses the split path:** the owner calls `requestWithheldAmountSync(bridgePayload)` only after maintenance and replay are complete, then anyone calls `relayWithheldAmountSync()` in a **separate transaction**, with the AMB idle. The amount is read at relay time. Confirm the actual relayed amount, new pairing and L1 receipt; `syncWithheldAmount` itself reverts `UseSyncSplit`.
21. **Restart gate.** Unpause only when reserve restoration and unpaid replay are complete, all required reserve-sync messages have successfully reached the correct active L1 Dispenser, and observed credit equals the reconciled expectation (§7). Before this step, validate the proposed distribution/credit consumption on a pinned **fork or simulation**: unpause its copy, nominate, advance the simulated voting/epoch state as needed, then claim and inspect minting, returns and destination payment. Live claims cannot run while paused. If any reconciliation or simulation fails, keep claims paused and normal distribution jobs disabled; record and resolve the discrepancy before retrying. Once the gate passes, call `Dispenser.setPauseState(Unpaused)`; the nonzero VoteWeighting check also requires step 16.
22. **Re-nominate, then controlled live validation.** After unpausing, nominate the staking targets **and the retainer** in VoteWeighting, setting fresh Dispenser cursors at the current epoch. `addNominee` is itself pause-gated, so this cannot precede step 21. Do **not** route a target through `removeNominee` first: removal is terminal in VoteWeighting. Once voting and a closed epoch make a claim possible, perform a controlled single-target, single-epoch claim (`numClaimedEpochs = 1`) per chain and verify credit consumption and actual deposits (§7) **before normal distribution jobs resume**. This bounds the number of targets and epochs, not the OLAS amount: a claim pays its full calculated allocation. Claims are permissionless after unpausing; this is an operational check, not an on-chain restriction to a test caller. If it fails, pause staking claims again and reconcile before resuming.

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
./scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh robinhood_mainnet

# 4. Whitelist all L1 deposit processors on the DispenserProxy — maps each L2 chainId + the mainnet chainId
#    to its processor (8 L2 chains + the L1-only Ethereum processor), then verifies each on-chain entry:
./scripts/deployment/staking/deploy_10_set_deposit_processors.sh mainnet
```

The old-stack settle/pause (Phase 1), each L2 `migrate` (Phase 3), the `Tokenomics` / `Treasury` re-point and
the final `setPauseState(Unpaused)` (Phase 4/5) are DAO proposals, not scripts — follow the phases above.

## 7. Reconciliation evidence and restart acceptance

Use finalized L1/L2 block snapshots and transaction receipts from the **exact deployed builds**. Keep actual addresses, balances, message histories and execution evidence in an access-controlled private ledger (§7.1); do not put completed records in this public repository. A snapshot of counters alone is not a reconciled starting point. Trace each balance and credit back to a verified earlier snapshot and include **every outstanding token leg, unpaid request and reserve-sync message originating before it**. Extend that investigation backwards until the opening figures and obligations reconcile; do not bound it by the migration date alone.

### Reads and evidence

Set the RPCs, snapshot blocks and old/new addresses from the privately verified deployment inventory. For example, these reads are executable once those variables are set; repeat for each old/new endpoint and each snapshot:

```bash
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$OLAS_L2" 'balanceOf(address)(uint256)' "$NEW_L2_DISPENSER"
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$NEW_L2_DISPENSER" 'withheldAmount()(uint256)'
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$NEW_L2_DISPENSER" 'stakingBatchNonce()(uint256)'
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$NEW_L2_DISPENSER" 'getBridgingDecimals()(uint256)'
cast call --rpc-url "$L1_RPC" --block "$L1_BLOCK" "$NEW_L1_DISPENSER" 'mapChainIdWithheldAmounts(uint256)(uint256)' "$CHAIN_ID"
cast call --rpc-url "$L1_RPC" --block "$L1_BLOCK" "$NEW_L1_DISPENSER" 'mapChainIdDepositProcessors(uint256)(address)' "$CHAIN_ID"
cast call --rpc-url "$L1_RPC" --block "$L1_BLOCK" "$NEW_L1_PROCESSOR" 'processedHashes(bytes32)(bool)' "$BATCH_HASH"
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$OLD_L2_DISPENSER" 'queuedHashes(bytes32)(bool)' "$OLD_QUEUE_HASH"
cast call --rpc-url "$L2_RPC" --block "$L2_BLOCK" "$NEW_L2_DISPENSER" 'processedHashes(bytes32)(bool)' "$BATCH_HASH"
cast receipt --rpc-url "$L2_RPC" "$SOURCE_TX"
cast receipt --rpc-url "$L1_RPC" "$RECEIPT_TX"
```

Read `paused`, `owner`, `l1Dispenser` / `l1DepositProcessor`, `l2TargetDispenser`, and the Tokenomics/Treasury manager getters to verify the intended pair and active proxy. Read `syncPending` / `pendingBridgePayload` on Gnosis. Use the ABI of each deployed version to decode events and queue hashes; old builds may differ. Preserve complete, paginated event histories and receipt status, block hash, transaction index and log index, not just transaction hashes.

| Stage | Acceptance evidence |
| --- | --- |
| Opening snapshot | OLAS balances, both L2 withheld counters and both L1 credits; every earlier outstanding message and obligation has an identified amount, source, destination and status. A zero L1 credit or zero L2 counter alone does not close this inventory. |
| Migration | Successful `migrate` receipt, the deployed version's `Migrated` event and OLAS `Transfer` logs, with before/after old and new balances. Reconcile actual token movement, including any additional arrivals; the pre-flight balance is not the transferred amount by definition. |
| Maintenance | Encoded `updateWithheldAmountMaintenance` amount equals the new L2 balance **at execution**, confirmed by transaction ordering/state replay if needed; `WithheldAmountUpdated` and the post-state agree. Repeat the step-14 checks for any intervening arrival, before the first sync. |
| Unpaid replay | Manifest contains only unpaid requests selected from old `StakingRequestQueued`, payment events and queue state. Group all unpaid requests of one original batch into one `processDataMaintenance(data, true)` call. Record `StakingMaintenanceDataProcessed`, `StakingTargetDeposited`, token transfers and new `processedHashes`. Count each payment once; a processed hash alone does not prove the original amount was paid. Reconcile any reduction under current factory/cap checks as an unresolved obligation until its disposition is reviewed, rather than immediately syncing it as free reserve. Old queued flags stay historical after replacement payment; do not treat them alone as permission to replay again. |
| Remaining obligations | For any newly queued request, record its new queue hash, amount, token backing and redemption receipt/status. Before sync, prove that backing is excluded from the free withheld reserve; if an obligation still overlaps the raw withheld counter, stop and review its recovery before syncing or rewriting counters. Do not sync funds required for unpaid requests, or resume with an unexplained or unfunded obligation. |
| Sync sent | Record `withheldAmount` before/after, decimals, `MessagePosted` amount/batch hash/sequence and the bridge message ID and destination. For `d < 18`, `q = 10^(18-d)`, sync amount `S = floor(W/q)*q`, remainder `r = W-S`; otherwise `q = 1`. Verify the exact reduction and retain `r` on L2. A zero syncable amount needs no message (`ZeroValue`); distinguish a genuine zero reserve from sub-quantum dust. |
| Sync received | Successful bridge **destination execution**, `MessageReceived` and `processedHashes(batchHash)` on the registered new processor, plus `WithheldAmountSynced` emitted by the **active L1 proxy** and its post-state credit. Match the amount/hash/source/destination across both receipts. An L2 send or counter decrease does not prove receipt. An old pair's callback can still credit the retired L1 after cutover; record it separately, never as active credit. |
| Gate and consumption | Reconcile expected versus observed active credit before unpause. In the fork/simulation and later controlled live claim, record `StakingIncentivesClaimed` / `StakingIncentivesBatchClaimed`, credit before/after, Treasury/OLAS mint and transfer logs, destination deposits and Tokenomics returns. If payout allocation is `I` and available credit is `C`, reuse `U = min(I,C)` once, fresh mint is `I-U`, and remaining credit is `C-U`. Inflation return includes ordinary returns **plus U**; do not count U again as fresh issuance. |

Maintain two linked accounts: **tokens** (opening balance + actual receipts − actual payments/transfers = closing balance) and **reserve/obligations** (free L2 withheld, active L1 credit, undelivered active-pair syncs and backed unpaid requests). Credit is a claim on the same L2 tokens, not another token balance to add. During the isolated cutover after full-balance restoration, with no fresh distributions or unidentified receipts, require:

`new L2 token balance = L2 unsynced withheld + active L1 credit + active-pair syncs in flight + backed unpaid requests`.

This equation assumes those categories are disjoint and the opening history has reconciled. Retired L1 credit and old-pair messages represent the retired accounting of that reserve and are tracked separately, not added again. Before restart, required active-pair syncs in flight must be zero; after queued payments finish, the unpaid component is zero as well. Reconcile any documented residual or historical exception explicitly rather than forcing the equality by a counter write.

If any amount or delivery is unexplained, keep the new L1 staking claims paused and normal distribution jobs disabled. Preserve the discrepancy, execution traces, last consistent snapshot and proposed recovery in the private ledger. Resolve the relevant token leg, funded unpaid replay or failed sync through the deployed bridge/governance recovery path, then repeat reconciliation. L1 `syncWithheldAmountMaintenance` is **additive**, not an absolute setter: use it only for an evidenced failed delivery with its correct amount and batch hash, checking prior receipt/maintenance and replay protection before a retry. Do not invent credit or hashes to make a balance match. After a successful sync, a blind full-balance L2 restore can duplicate the credit; reconcile outstanding credit and messages first.

Token recovery and accounting restoration are separate. Neither this procedure nor a maintenance counter write recovers tokens already irretrievably lost. Record any confirmed loss, its evidence, affected obligation and separately authorized disposition as an explicit exception; do not describe it as recovered reserve or create unsupported credit for it.

### 7.1 Private ledger schema

Choose an explicitly private, access-controlled destination before recording operational data. If its visibility is uncertain, resolve that first. Use one per-chain ledger with ordered entries and linked raw receipts; a spreadsheet or JSON/CSV is sufficient, without a new tooling framework.

- **Identity/opening:** chain IDs, deployed code versions, old/new L1 Dispensers, processors, L2 dispensers and token addresses; L1/L2 block numbers and hashes; starting balances, withheld counters and credits; verified earlier snapshot and all outstanding token legs, unpaid requests, armed sync requests and sent sync messages.
- **Each transition:** action (migration, arrival/forward, maintenance, replay/redeem, sync, callback, claim or correction), source/destination, amount in raw token units, normalized amount/remainder, batch/queue hashes, bridge message IDs, transaction hashes, block/transaction/log ordering, expected and observed state deltas, delivery outcome, failure, retry and manual intervention. Link retries to the original operation so neither credit nor payment is counted twice.
- **Closing/restart:** expected versus observed token and accounting totals, retired versus active credit, remaining backed obligations and dust, all message outcomes, discrepancies/loss exceptions and authorized recovery, fork/simulation results, gate decision and controlled live-validation results. Continue through subsequent credit consumption, not just receipt.

### 7.2 Separate future case: retaining the L1 Dispenser

The steps above replace L1 and both bridge endpoints. They are **not** instructions for a migration retaining the existing L1 Dispenser. In that case, existing `mapChainIdWithheldAmounts` credit and outstanding sync messages survive. Before restoring L2 withheld accounting, reconcile which tokens already back that credit, which are committed to unpaid requests, and which syncs can still arrive or have been consumed by intervening claims. Restoring the full L2 balance as fresh withheld and syncing it can duplicate credit already held on L1. There is no safe blind `balance - credit` formula: pending callbacks, unpaid obligations, normalization and transaction ordering must all be accounted for. Derive and verify the maintenance amount from that ledger under a separately reviewed procedure.

### 7.3 Post-migration verification

- New Dispenser: `tokenomics`, `treasury`, `voteWeighting`, `mapChainIdDepositProcessors[chainId]` all point at the new contracts; `retainerHash` matches the intended retainer.
- `Tokenomics.dispenser == Treasury.dispenser == newDispenser`, and `VoteWeighting.dispenser == newDispenser` (immutable, set at deploy).
- Each new L1 processor: `l1Dispenser == newDispenser`, `l2TargetDispenser == newL2`.
- Each new L2 dispenser: `l1DepositProcessor == newL1Processor`, balance and `withheldAmount` match the reconciled **post-replay/post-sync** state (including any remainder); each **old** L2 dispenser: `owner == address(0)` (retired).
- Pre-unpause fork/simulation passed; post-unpause controlled single-target, single-epoch claim (`numClaimedEpochs = 1`) passed per chain, with receipt and credit-consumption evidence (§7).
- The retainer is an active VoteWeighting nominee; `retain()` succeeds.

### Focused regression validation

```bash
forge test --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol --mc DispenserInflationConservationTest --mt test_migration -vv
forge test --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol --mc TargetDispenserL2ForwardTest -vv
npx hardhat test test/StakingBridging.js
```

The migration scenarios reuse real Tokenomics, Treasury, Dispenser and Gnosis
processor/receiver accounting with synthetic voting/staking and explicitly
queued bridge callbacks. They cover both old/new callback orderings, replacement
credit exactly once, unpaid replay (including a now-ineligible target whose hash is consumed without payment), credit consumption, zero reserve and a
synthetic eight-decimal precision boundary (production Gnosis uses 18).
The forward suite also covers selecting unpaid requests from a partly paid
batch. These are offline contract tests, not bridge finality evidence or actual
deployment validation. They do not replace the per-chain pinned fork/simulation
of the proposed transactions, the private historical ledger or live receipt
checks required by steps 20–22.

### Release artifacts to regenerate (part of the release checklist, not optional)

The Dispenser rework changed several ABIs. Regenerate at redeploy so downstream consumers (deploy scripts, frontends, indexers) do not read stale definitions:
- **`abis/<ver>/Dispenser.json`** — the 3-arg constructor `(olas, tokenomics, retainer)`, the new `initialize` / `changeManagers(address,address)` / `changeImplementation`, and the `calculateStakingIncentives` return tuple that now includes the sparse `zeroWeightEpochs[]`.
- **`abis/<ver>/DefaultTargetDispenserL2.json`** (and every chain variant) — the 4-arg `Migrated(address,address,uint256,uint256)`. Any indexer/subgraph keyed on the old 3-arg topic0 must handle both during the cutover.
- **`docs/configuration.json`** — the new `dispenserProxyAddress` and every repointed address, updated **only after** the on-chain rewiring is complete.
- **`scripts/audit_chains/audit_contracts_setup.js` — delete the standing-red exemption.** `checkBytecode`'s Tier-1 length mismatch is blocking (issue #322), and the script carries a dated `DELIBERATE STANDING-RED DECISION (2026-08)` comment saying the audit is *expected* to `exit(1)` while several deployed implementations still predate the in-repo code (the mainnet / Optimism / Base LiquidityManager impls and the proxied Dispenser). Once an implementation is redeployed and `configuration.json` is repointed above, that contract should go green — **remove the comment in the same PR**, once the last of them clears. A stale "expected red" note is worse than none: it keeps excusing failures after the reason for them has gone.

## 8. Rollback / risk notes

- Any nominee that fails to claim in Phase 1 forfeits its old-stack unclaimed incentives (only the old Dispenser can pay them, and it is being retired). Chase settlements before the step-6 pause: once it executes, claims on the old Dispenser revert.
- A token leg arriving at a retired L2 dispenser without a usable recovery path may be irretrievable. The step-13 gate must establish delivery before migration; investigate the exact deployed build and bridge recovery options for any exception, record confirmed losses privately, and do not claim a maintenance write recovers those tokens.

## 9. Open items to confirm before executing

- **On-chain state (Phase 0.1):** read `mapChainIdWithheldAmounts` for every chain, plus each L2 dispenser's `withheldAmount` **and** its OLAS balance. Reconcile non-zero credits and outstanding messages as in §7; callbacks may arrive after cutover and credit the retired L1. It does **not** change step 14's input, which is always the **final OLAS balance of the new dispenser**; the new Dispenser starts at `0`, so that old L1 credit is simply dropped unless step 14 restores the balance. Skipping balance, obligation or receipt reconciliation can leave carried OLAS unaccounted for; the restart gate requires all three.
- **VoteWeighting semantics (external repo):** behaviour of `checkpointNominee` / `nomineeRelativeWeight` for a freshly-nominated target (`checkpointNominee` reverts `NomineeDoesNotExist` for a never-added nominee; the Dispenser guards this). Confirm against the deployed build in [`valory-xyz/autonolas-governance`](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/VoteWeighting.sol) at the pinned deploy tag.
- **Per-chain owner** of each L2 target dispenser (for the pause/migrate/maintenance proposals) and the L2 source-binding call used in step 15 (varies by bridge: **Arbitrum-Orbit (Arbitrum 42161 and Robinhood 4663)** / Gnosis AMB / OP-stack (Optimism, Base, Celo, Mode) / Polygon Fx). Robinhood is **not** OP-stack: its `pause` / `migrate` / `updateWithheldAmountMaintenance` go via the Arbitrum-Orbit path (live L2 owner is the bridge mediator `0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F`), and its step-15 link is `setL2TargetDispenser` on the Robinhood L1 processor.
