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

**The only cross-chain state — `mapChainIdWithheldAmounts`.** This tracks OLAS already bridged to an L2 that staking targets could not absorb, netted against the *next* distribution to that chain. The OLAS itself sits on the **L2 target dispenser**, not on L1 — but note the L2's own `withheldAmount` counter is **zeroed once that amount has been synced up to L1**, so an L2 dispenser can hold the OLAS while reporting `withheldAmount == 0`. The balance and the counter are not the same reading.

The map is mutated by netting, by `syncWithheldAmount` from an L1 processor, and by **`syncWithheldAmountMaintenance`** — an `owner`-gated L1 admin setter in [`Dispenser.sol`](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Dispenser.sol) that exists precisely to restore state an L2 failed to deliver. (An earlier revision of this runbook said there was no L1-side setter for this map; that was wrong, and it made a non-zero L1 state look unrecoverable.)
> **Read per chain before starting:** `mapChainIdWithheldAmounts(chainId)` on the live Dispenser, and on each L2 target dispenser **both** `withheldAmount` **and the OLAS balance**. Two cases:
> - **All zero on L1.** The new Dispenser starting at 0 is already consistent, there is no L1 reconciliation to do, and steps 13/14/22 behave as written.
> - **Any non-zero on L1.** That OLAS is sitting on the chain's L2 dispenser with the L2 counter already zeroed. It is **recoverable** — see the note on step 14 — but it is silently dropped if steps 13/14 are run as though the L1 value were 0. Do not skip the balance read.

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

### Phase 0 — Pre-flight (verify, don't change)

1. Read `mapChainIdWithheldAmounts(chainId)` on the **live** Dispenser for every chain, and on each **L2** target dispenser read **both** its `withheldAmount` and its **OLAS balance**; record them all. §4 covers both outcomes — a non-zero L1 value is recoverable (see the step 14 note), not a stop condition — but the two readings diverge once a chain has synced up to L1, and it is the **balance** that travels with the migration and that step 14 restores, so do not skip the balance read.
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
   **Confirm settled:** for every nominee, the retainer included, `mapLastClaimedStakingEpochs(nomineeHash)` on the old Dispenser equals `epochCounter()` on Tokenomics. Enumerate the nominees from VoteWeighting with `getNumNominees()` and `getNominee(i)` for `i` in `1..N`; on the live VoteWeighting the retainer is nominee `1`.
   ```bash
   # nomineeHash = keccak256(abi.encode(account, chainId)), with the account as bytes32
   h=$(cast keccak $(cast abi-encode "f(bytes32,uint256)" <account> <chainId>))
   cast call <oldDispenser> "mapLastClaimedStakingEpochs(bytes32)(uint256)" $h
   cast call <TokenomicsProxy> "epochCounter()(uint32)"
   # -> the two are equal for every nominee; for a removed nominee (mapRemovedNomineeEpochs(h) != 0)
   #    the cursor stops at its removal epoch instead
   ```
6. `Dispenser.setPauseState(StakingIncentivesPaused)` on the old Dispenser, executed **in the same epoch** as the last claims of step 5. Claims are permissionless and the pause is a DAO proposal, so time the proposal's execution against the claims: if a `Tokenomics.checkpoint()` lands between the last claim and the pause, settle the newly closed epoch before the pause executes. `retain()` is not pause-gated, so the retainer can also finish after the pause.
   **Confirm paused:** `paused()` on the old Dispenser reads `2` (`StakingIncentivesPaused`), and the step-5 check still holds for every nominee.
7. Process/drain any **outstanding queued requests** on each L2 target dispenser (the `migrate()` NatSpec requires this — outstanding queued requests are handled by the DAO on the L2 side before migration).

### Phase 2 — Deploy the new stack

Deploy order is load-bearing: the Dispenser proxy must exist before VoteWeighting (which binds the proxy as an immutable), and the Dispenser proxy is initialized with a **zero** `voteWeighting` because VoteWeighting does not exist yet. This breaks the otherwise-circular dependency.

8. Deploy the **new Dispenser behind `DispenserProxy`**:
   - **Implementation** ctor takes only the bytecode immutables `(_olas, _tokenomics, _retainer)` (`deploy_07a_dispenser.sh`; `_tokenomics` is the Tokenomics **proxy** address, `_retainer` is `bytes32`). The script also locks the standalone implementation post-deploy.
   - **Proxy** ctor is `DispenserProxy(implementation, initData)` where `initData = initialize(_treasury, voteWeighting = 0, _maxNumClaimingEpochs, _maxNumStakingTargets)` (`deploy_07b_dispenser_proxy.sh`). The proxy delegatecall-initializes the impl, the deployer becomes proxy owner atomically, and staking incentives start `StakingIncentivesPaused`. `maxNumClaimingEpochs` / `maxNumStakingTargets` are set once here (no runtime setter) — pick them carefully.
9. Deploy the **new `VoteWeighting(ve, dispenserProxy)`** — `dispenser` is immutable, bound to the Dispenser proxy address from step 8.
10. Deploy the **new L1 deposit processors** (all on ETH mainnet L1), each with `l1Dispenser = dispenserProxy` (step 8). On mainnet the processor scripts read that address from `dispenserProxyAddress` in `scripts/deployment/globals_mainnet.json`, where step 8's `deploy_07b_dispenser_proxy.sh` records it, and stop if it is unset. The staking globals' `dispenserAddress` still holds the **old** Dispenser and is not used on mainnet: `l1Dispenser` is immutable, so a processor bound to the wrong address can only be redeployed.
    - Bridge-paired processors — Arbitrum `staking/deploy_02_arbitrum_deposit_processor.sh`, Gnosis `deploy_03`, Optimism `deploy_04`, Celo `deploy_05`, Polygon `deploy_06`, Base `deploy_07`, Mode `deploy_11`, Robinhood `deploy_13_robinhood_deposit_processor.sh` (chainId 4663, the second Arbitrum-Orbit chain — same processor type as Arbitrum). Each binds to its L2 bridge and gets its `l2TargetDispenser` wired in step 15.
    - **ETH mainnet is L1-only — a different contract and script.** `EthereumDepositProcessor` (`staking/deploy_08_eth_deposit_processor.sh`, ctor `(olas, dispenserProxy, stakingFactory, timelock)`) has **no** bridge relayer, **no** `l2TargetDispenser`, and **no** corresponding L2 target dispenser — mainnet staking settles on L1 directly. It has no step-11 L2 deploy and no step-15 link, and Phase 3 does not apply to it.
11. Deploy the **new L2 target dispensers** — one per L2, each with `l1DepositProcessor = <its new L1 processor from step 10>`, from that chain's subfolder: Arbitrum `staking/arbitrum/deploy_02_arbitrum_target_dispenser.sh`, Gnosis `gnosis/deploy_03`, Optimism `optimism/deploy_04`, Celo `celo/deploy_05`, Polygon `polygon/deploy_06`, Base `base/deploy_07`, Mode `mode/deploy_11`, Robinhood `robinhood/deploy_02_robinhood_target_dispenser.sh`. **No ETH entry** — ETH is L1-only (step 10).

### Phase 3 — Migrate each L2 target dispenser (per chain)

For every chain with an L2 dispenser (Arbitrum, Gnosis, Optimism, Base, Polygon, Celo, Mode, Robinhood):

Robinhood (chainId 4663, registered in the live Dispenser since proposal 16) holds no OLAS and carries no L1 credit, so as of the 2026-10-05 reading its `migrate` carries nothing and step 14 restores `0`. Treat that as a dated reading, not the procedure: step 14 restores Robinhood's **Phase-0 OLAS balance** like every other chain, so if OLAS arrives before the cutover, restore that balance rather than `0`. Either way it still redeploys and rewires with the rest, because `l1DepositProcessor` / `l1Dispenser` are `immutable` and a chain left unregistered at step 19 is unroutable.

12. `pause()` the **old** L2 dispenser (`migrate` requires paused).

    **Gate before step 13 — nothing in flight to this chain.** `migrate()` sweeps the balance once, and the dispensers being migrated here have no way to pass on anything that arrives afterwards: a late token leg lands on the dead dispenser for good, and a late message leg reverts there. So confirm, per chain, that every claim made since the start of step 5 has fully landed:
    - **Message legs.** Every batch the old L1 processor sent has been processed on the old L2 dispenser. The L1 processor numbers its batches (`stakingBatchNonce()` is the next one), and the L2 dispenser records each as `processedHashes(keccak256(abi.encode(nonce, 1, <old L1 processor>)))`. Check every nonce sent since step 5 began:
      ```bash
      n=$(cast call <oldL1Processor> "stakingBatchNonce()(uint256)")
      h=$(cast keccak $(cast abi-encode "f(uint256,uint256,address)" $((n-1)) 1 <oldL1Processor>))
      cast call --rpc-url <L2 rpc> <oldL2Dispenser> "processedHashes(bytes32)(bool)" $h
      # -> true; repeat down to the first nonce sent in step 5 (verified live on Optimism 2026-10-07:
      #    the last two batches read true, the next unsent nonce reads false)
      ```
    - **Token legs.** For each of those claims that transferred OLAS, the bridge transfer has completed, not merely started:
      - **Arbitrum, Robinhood:** both retryable tickets, the token gateway's and the message's, are **redeemed**. An unredeemed ticket can still be redeemed by anyone for 7 days, then expires.
      - **Gnosis:** the Omnibridge `relayTokens` message is **executed** on the Gnosis AMB (`messageCallStatus(messageId)` is `true`).
      - **Polygon:** the `depositFor` is **state-synced**: the `StateSynced` id emitted on L1 is ≤ `lastStateId()` on Polygon's `StateReceiver` (`0x0000000000000000000000000000000000001001`).
      - **OP-stack (Optimism, Base, Celo, Mode):** the deposit is **relayed**: `successfulMessages(<message hash>)` is `true` on the L2 `CrossDomainMessenger` (`0x4200000000000000000000000000000000000007`).
    - **No queue since step 7.** No `StakingRequestQueued` on the old L2 dispenser after step 7. A message processed while the dispenser is paused (step 12) is queued rather than deposited. If one appears, its OLAS migrates with the balance: replay it on the new dispenser with `processDataMaintenance` after step 14.

    **Future migrations of the new builds.** The L2 dispensers deployed in this cutover add `forward()`: after `migrate()`, anyone can move OLAS that reaches the old address on to `migratedTo`. In a later migration, a late token leg is recovered by calling `forward()` on the old dispenser, **then** replaying its message with `processDataMaintenance` on the new one. Forwarding first means the replay deposits the OLAS that came with the claim; replayed first, it draws on the new dispenser's existing balance instead, or queues the deposit if that balance is short. The dispensers retired in this cutover predate `forward()`, which is why the gate above is load-bearing here.
13. `migrate(newL2TargetDispenser)` on the old L2 dispenser — transfers its **full OLAS balance** (withheld + any residual) to the new one, zeroes the old owner and locks it permanently (one-way; the old dispenser is dead after this). The `Migrated` event surfaces the migrated balance — which is the figure to restore at step 14 (see step 14 for why the emitted `withheldAmount`, where the event carries one at all, is not).
14. On the **new** L2 dispenser, `updateWithheldAmountMaintenance(<final OLAS balance of the new dispenser>)` to re-establish its `withheldAmount` (it deploys at 0). **Pass the migrated balance, not the emitted `withheldAmount`** — which is what the function's own NatSpec requires for this case: *"[2] Withheld amount update after balance migration to a new contract … The amount here must correspond to … [2] Final OLAS balance of this contract address."*

    The two values differ whenever the chain has already synced a withheld amount up to L1: the emitted `withheldAmount` is then `0` (the accounting moved to L1) while `migrate()` still carried a non-zero **balance**. Passing that `0` leaves the OLAS accounted for by neither side — the new L1 Dispenser also starts at `0`, so nothing nets against it and the new L2 dispenser accumulates unusable OLAS while L1 mints fresh. Where L1 read `0`, the balance and the emitted value coincide and the same rule gives the same answer.

    There is a second reason not to reach for the emitted value: **the deployed L2 dispensers emit the three-argument `Migrated(address,address,uint256)` and do not report `withheldAmount` at all.** The four-argument form is on the *new* build — the contract being migrated **to**, never the one `migrate()` runs on. So at step 13 the migrated balance is the only figure the event gives you — on every chain but Robinhood (4663), whose live dispenser is already the four-argument build and so also reports `withheldAmount`. Robinhood holds nothing as of 2026-10-05, so both figures read `0` there and step 14 restores `0` today; the rule — restore the Phase-0 balance — is unchanged, so restore the actual balance if OLAS has since arrived.

    Verified on a Base fork against the live dispenser `0x9Ec97Be9…b241` (holding 1,380,908.799963024002602865 OLAS at `withheldAmount == 0`): `migrate()` carries the full balance and emits only the amount; `syncWithheldAmount` reverts `ZeroValue` while `withheldAmount` is `0`; and restoring the balance then syncing sends the full amount and consumes one batch nonce.

    Once restored, the amount reaches the new L1 Dispenser through the **ordinary** `syncWithheldAmount` path, which is what re-enables netting (every chain but Gnosis, whose new dispenser requires the split call — see step 22). That cross-chain sync must wait until step 15 has bound the new L2↔L1 pair. If it is run between steps 14 and 15 the **L2 `syncWithheldAmount` call itself succeeds** — it decrements `withheldAmount` and emits the bridge message — but the message then **reverts `WrongMessageSender` on L1 receipt** (`DefaultDepositProcessorL1._receiveMessage`), leaving the L2 decrement with nothing delivered. So run it only after step 15, and confirm at step 22. There is no L1-side shortcut worth taking here: `Dispenser.syncWithheldAmountMaintenance` would require the DAO to supply a `batchHash` for a message that never failed, and `updateHashMaintenance` marks that hash `processed` on the new L1 processor — if it collides with one the new L2 dispenser will genuinely produce (its nonce restarts at 0), that real sync later reverts `AlreadyDelivered` and its amount is lost. Use the L2 maintenance call.
15. Wire the L2↔L1 link: `setL2TargetDispenser(newL2)` on the new L1 processor (`staking/script_02_set_target_dispenser_l2_all.sh` for the **seven original chains** it lists — Mode included, **Robinhood not** — or `script_01_set_target_dispenser_l2.sh` per chain; the hardhat `staking/deploy_09_set_targer_dispensers.js` is the equivalent **for the original chains only — it has no Mode or Robinhood entry**, so link those two via the shell `script_01_…` route), and the corresponding L2-side source binding, so cross-chain messages authenticate against the new pair. (ETH is skipped — no L2 side.) **Polygon** needs one extra L1 binding — `script_03_set_deposit_processor_l1_polygon.sh` (the `fxRootTunnel` link); `multi_deploy_01` runs it automatically for Polygon, but it must be run explicitly if the per-chain scripts are used by hand. **Robinhood** is **not** in `script_02_set_target_dispenser_l2_all.sh` (that script predates 4663), so link it with the per-chain `script_01_set_target_dispenser_l2.sh robinhood_mainnet` — or the `multi_deploy_01` wrapper, which globs the `deploy_13` / `robinhood/deploy_02` scripts and the generic `script_01` for `robinhood_mainnet`.

### Phase 4 — Re-point L1 wiring (while still paused)

16. `Dispenser.changeManagers(0, newVoteWeighting)` — wire the real VoteWeighting into the Dispenser proxy (initialized with a zero `voteWeighting` in step 8), via `scripts/deployment/script_dispenser_change_managers.sh` (it passes `treasury = 0`, a no-op, and the new `voteWeighting`). This same script is also how a *future* standalone VoteWeighting redeploy is repointed onto the existing Dispenser. The setter requires the paused state, satisfied by construction. (There is **no** `VoteWeighting.changeDispenser` call — `VoteWeighting.dispenser` is immutable, set in step 9.)
17. `Tokenomics.changeManagers(0, 0, newDispenser)`.
18. `Treasury.changeManagers(0, 0, newDispenser)`.
19. `Dispenser.setDepositProcessorChainIds(newProcessors, chainIds)` on the new Dispenser — whitelist every L1 deposit processor, mapping each L2 target chainId (and the mainnet chainId) to its processor. Forge: `staking/deploy_10_set_deposit_processors.sh` (reads all processor addresses + chainIds from the staking globals and the Dispenser from `dispenserProxyAddress` in the root globals, refuses to send unless that address answers `PROXY_DISPENSER()`, includes the `EthereumDepositProcessor` under the mainnet chainId, the Mode processor and the Robinhood processor (chainId 4663), and re-reads `mapChainIdDepositProcessors` afterwards to confirm each entry took); hardhat equivalent `staking/deploy_10_set_deposit_processors.js`. There is no zero-processor guard in the Dispenser, so a chain left unregistered here resolves to a zero processor and **reverts the claim** — and in the batch path the zero-address call reverts the whole batch, taking the other chains' claims with it.

### Phase 5 — Re-nominate and resume

20. Nominate the staking targets **and the retainer** in VoteWeighting → fires `addNominee` on the new Dispenser, setting fresh cursors at the current epoch (clean because Phase 1 settled everything). Do **not** route any target through `removeNominee` first — removal is **terminal in VoteWeighting** (`_addNominee` reverts `NomineeRemoved`; `mapRemovedNominees[hash]` is set on removal and never cleared). Note the Dispenser-side `mapRemovedNomineeEpochs` brick described in §2 is **fixed** on the new Dispenser (#310, vuln-list item #25 — `addNominee` now clears it), so on the new stack the standing reason is the VoteWeighting side, which is not fixed.
21. `Dispenser.setPauseState(Unpaused)`. (The Dispenser rejects going live while `voteWeighting == address(0)`, so this only succeeds after step 16.)
22. **Withheld re-sync — no special step, but confirm it happens.** With step 14 done correctly the carried amount is on the new L2 dispenser's `withheldAmount`, and the ordinary `syncWithheldAmount` path carries it up to the new L1 Dispenser like any other sync; nothing migration-specific is required. What is worth checking is that it *has* happened before the first full epoch distribution, since until it does the new Dispenser reads `mapChainIdWithheldAmounts = 0` and bridges fresh OLAS instead of netting (funds are not lost, the L2 simply stays "ahead"). For a chain whose balance is genuinely `0` — Robinhood today — there is nothing to sync: **skip the `syncWithheldAmount` call**, which would otherwise revert `ZeroValue`. And a chain left at `0` by step 14 in error cannot be repaired here — the sync path rejects a zero amount either way — so any such shortfall points back to step 14, not to this step. **Gnosis is the exception to the one-call sync:** its new `GnosisTargetDispenserL2` reverts `syncWithheldAmount` with `UseSyncSplit`, so the carry-over is a two-step split — the owner calls `requestWithheldAmountSync(bridgePayload)`, then anyone calls the permissionless `relayWithheldAmountSync()` in a **separate** transaction once the AMB is idle. Have the new L1 pairing (step 15) and processor registration (step 19) in place before the relay, or it lands on the old pair. Step 14 (`updateWithheldAmountMaintenance(<final OLAS balance>)`) is unchanged for Gnosis.

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

- Any nominee that fails to claim in Phase 1 forfeits its old-stack unclaimed incentives (only the old Dispenser can pay them, and it is being retired). Chase settlements before the step-6 pause: once it executes, claims on the old Dispenser revert.
- A claim transfer still in flight when its chain's old L2 dispenser is migrated is lost: the dispensers retired here predate `forward()`. The step-13 gate is what prevents it.

## 9. Open items to confirm before executing

- **On-chain state (Phase 0.1):** read `mapChainIdWithheldAmounts` for every chain, plus each L2 dispenser's `withheldAmount` **and** its OLAS balance. A non-zero L1 value is covered — see the step 14 note. It does **not** change step 14's input, which is always the **final OLAS balance of the new dispenser**; the new Dispenser starts at `0`, so that old L1 credit is simply dropped unless step 14 restores the balance. Skipping the balance read, or restoring the emitted/withheld figure instead, is what strands the carried OLAS.
- **VoteWeighting semantics (external repo):** behaviour of `checkpointNominee` / `nomineeRelativeWeight` for a freshly-nominated target (`checkpointNominee` reverts `NomineeDoesNotExist` for a never-added nominee; the Dispenser guards this). Confirm against the deployed build in [`valory-xyz/autonolas-governance`](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/VoteWeighting.sol) at the pinned deploy tag.
- **Per-chain owner** of each L2 target dispenser (for the pause/migrate/maintenance proposals) and the L2 source-binding call used in step 15 (varies by bridge: **Arbitrum-Orbit (Arbitrum 42161 and Robinhood 4663)** / Gnosis AMB / OP-stack (Optimism, Base, Celo, Mode) / Polygon Fx). Robinhood is **not** OP-stack: its `pause` / `migrate` / `updateWithheldAmountMaintenance` go via the Arbitrum-Orbit path (live L2 owner is the bridge mediator `0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F`), and its step-15 link is `setL2TargetDispenser` on the Robinhood L1 processor.
