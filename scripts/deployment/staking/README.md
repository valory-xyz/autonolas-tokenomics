# Deployment sequence

## Read-only checkpoints

Run commands from the repository root with dependencies/submodules installed and the reviewed Forge build
in `out/`. Build the scoped contracts with the same compiler, dependency pins and settings used for deployment:

```bash
forge build --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol
```

Root `scripts/deployment/globals_<network>.json` records `dispenserAddress` as the implementation and
`dispenserProxyAddress` as the callable Dispenser. L1 processors bind the latter. Do not copy the implementation
into the staking globals as a live Dispenser. The audits read the new addresses directly from deployment globals;
update `docs/configuration.json` with the deployed contracts, including the separate DispenserProxy entry, for the
existing whole-system audit. Keep its Dispenser implementation entry immediately before its proxy entry.

After `deploy_07a_dispenser.sh` and `deploy_07b_dispenser_proxy.sh`, manually edit the following fields.
Both repositories use `scripts/deployment/globals_mainnet.json`; the key names have different meanings:

| When | Copy from | Copy to |
| --- | --- | --- |
| Before VoteWeighting deployment | Tokenomics `dispenserProxyAddress` | Governance `dispenserAddress` (constructor argument) |
| Before VoteWeighting deployment | Tokenomics `dispenserAddress` | Governance `dispenserImplementationAddress` (validation only) |
| After VoteWeighting deployment | Governance `voteWeightingAddress` | Tokenomics `voteWeightingAddress` |

Follow the [VoteWeighting instructions](https://github.com/valory-xyz/autonolas-governance/blob/377bb456a119444ccc6c5c89e62e71b96ac7fd0a/scripts/deployment/README.md#deployment-of-voteweighting)
for its deployment and audit. These file edits do not configure contracts on-chain. Then run:

```bash
node scripts/audit_chains/audit_staking_routes.js dispenser mainnet
```

The audit checks the implementation's full runtime (including immutable values), the proxy runtime and implementation
slot, OLAS, Tokenomics, retainer/hash, Treasury, owner, limits, pause state, VoteWeighting in both directions,
Tokenomics/Treasury manager references and all nine processor routes. It always compares against the intended final
configuration. The implementation is initialized separately to lock it; its owner/Treasury storage is not the proxy's.

| Check | Expected (after governance/configuration) | What we will see before |
| --- | --- | --- |
| Dispenser proxy owner | Timelock | Deployer until ownership handover |
| Dispenser VoteWeighting | Configured new VoteWeighting | Zero until manager wiring |
| Dispenser processor routes | Configured nine processors | Zero until route wiring |
| Dispenser pause state | 0 (unpaused) | 2 (staking paused) after initialization |
| Tokenomics/Treasury Dispenser | New Dispenser proxy | Old Dispenser until cutover |

These are the only listed transitional differences. Code, immutable bindings, implementation slot, Treasury and
limits must already match. VoteWeighting's immutable Dispenser reference must match immediately after its deployment.
Rerun after configuration/governance: the expected differences must disappear. The existing whole-system audit remains
necessary for other ownership, bridge and staking-factory state checks.

For each processor use the combined wrapper, including Ethereum and Robinhood:

```bash
bash scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh gnosis_mainnet
```

Substitute `eth`, `arbitrum`, `gnosis`, `optimism`, `base`, `celo`, `mode`, `polygon` or `robinhood`.
The wrapper deploys the pair, audits both runtimes and constructor bindings, then links only if the audit passes.
Linking clears the L1 processor owner irreversibly. Polygon also sets the L2 `fxRootTunnel`. A second audit verifies
both completed links and the cleared L1 owner. Ethereum only deploys and audits its local processor.
To retry audits against already deployed addresses without redeploying:

```bash
node scripts/audit_chains/audit_staking_routes.js pair gnosis_mainnet before-link
node scripts/audit_chains/audit_staking_routes.js pair gnosis_mainnet after-link
```

Use the phase matching the transaction state; never rerun the combined deployment wrapper merely to retry an audit.
The older all-network linking script does not run these checkpoints. RPCs come from globals and their existing
Alchemy environment variables; `AUDIT_L1_RPC_URL` and `AUDIT_L2_RPC_URL` may override them. Each RPC chain ID must match.
No audit broadcasts transactions. Mismatches and unreadable checks print on separate lines; all available checks run
before a nonzero exit. Invalid inputs or a wrong-chain RPC stop early. Review each result: a nonzero Dispenser audit
before governance is expected only for the differences listed above; pair-linking audits must pass fully.

### Configure the fresh proxy before ownership handover

After the VoteWeighting handoff and all nine processor deployments/link audits, while the deploying EOA still
owns the **new Dispenser proxy**, run these separate configuration transactions from the tokenomics repository root:

```bash
bash scripts/deployment/script_dispenser_change_managers.sh mainnet
bash scripts/deployment/staking/deploy_10_set_deposit_processors.sh mainnet
node scripts/audit_chains/audit_staking_routes.js dispenser mainnet
```

The first script reads root `voteWeightingAddress` and wires it into the proxy. The second reads the deployed
processor addresses from staking globals and registers all nine routes. These calls are not performed by the
per-network combined wrapper. Confirm the VoteWeighting and route checks now match before calling
`changeOwner(timelockAddress)` on the new Dispenser proxy. The owner mismatch remains expected until that handover.
Keep the proxy staking-paused: the old Tokenomics/Treasury references and pause-state difference await the separate
DAO migration/cutover. If ownership was already handed over, the two configuration calls require Timelock governance
instead of these direct EOA scripts. Rerun the audit after handover and after the later cutover.

### L2 dispenser ownership handover — audit required first

**Do not transfer ownership until the deployment and completed-link audits have passed and their results
have been reviewed.** Confirm the reviewed code, constructor bindings, pair addresses and completed links
(including Polygon's `fxRootTunnel`), and verify that `bridgeMediatorAddress` is the intended governance
mediator on that chain. Resolve every unexpected mismatch or unreadable check before proceeding.
The deployer-versus-mediator owner difference is expected before handover.

For each of the eight L2s (`arbitrum`, `gnosis`, `optimism`, `base`, `celo`, `mode`, `polygon`, `robinhood`),
the deployer then runs the existing script; for example:

```bash
bash scripts/deployment/staking/script_04_target_dispenser_l2_change_owner.sh gnosis_mainnet
```

This is a separate required step: the combined deployment wrapper does not transfer L2 ownership.
After the transaction is confirmed, read `owner()` on the new L2 dispenser and require it to equal that
chain's configured `bridgeMediatorAddress`; record the transaction and verification before marking handover complete.

## Ten-target gas tests

`maxNumStakingTargets` limits targets **per destination chain** in a batch, not the total across all chains.

The opt-in `test/DispenserBatchGas.js` uses real Dispenser/Tokenomics, VoteWeighting/veOLAS/OLAS and
StakingFactory/StakingVerifier/StakingToken builds. Build the reviewed governance and registries checkouts with Forge,
then provide their `out` directories. The test uses synthetic programmes and a transport mock; it does not use live
contracts or measure production bridge overhead. Gnosis delivery is a separate transaction whose call to the real
receiver is capped at its configured 2,000,000 gas. Assertions check all ten funding/queue outcomes, not just success.
The 15,000,000 L1 test budget is a test allowance, not a statement of every chain's transaction cap.

```bash
npx hardhat test --no-compile test/StaticRouteAudit.js
REGISTRIES_OUT=../autonolas-registries/out GOVERNANCE_OUT=../autonolas-governance/out \
  npx hardhat test --no-compile test/DispenserBatchGas.js
```

Without both artifact directories the cross-repository gas suite is skipped. It covers first/subsequent funding,
paused queues, invalid targets and emissions caps. Programme-specific behaviour and production bridge execution
still need validation.


## Arbitrum / Robinhood
1. On L1: deploy ArbitrumDepositProcessorL1
2. On L2: Deploy ArbitrumTargetDispenserL2
3. On L1: In ArbitrumDepositProcessorL1 set ArbitrumTargetDispenserL2 to l2TargetDispenser.

## Gnosis
1. On L1: deploy GnosisDepositProcessorL1
2. On L2: deploy GnosisTargetDispenserL2
3. On L1: In GnosisDepositProcessorL1 set GnosisTargetDispenserL2 to l2TargetDispenser.

## Optimism / Base / Celo / Mode
1. On L1: deploy OptimismDepositProcessorL1
2. On L2: deploy OptimismTargetDispenserL2
3. On L1: In OptimismDepositProcessorL1 set OptimismTargetDispenserL2 to l2TargetDispenser.

## Polygon
1. On L1: deploy PolygonDepositProcessorL1
2. On L2: deploy PolygonTargetDispenserL2
3. On L1: In PolygonDepositProcessorL1 set PolygonTargetDispenserL2 to l2TargetDispenser.
4. On L2: In PolygonTargetDispenserL2 set PolygonDepositProcessorL1 to l1DepositProcessor.

## Wormhole
1. On L1: deploy WormholeDepositProcessorL1
2. On L2: deploy WormholeTargetDispenserL2
3. On L1: In WormholeDepositProcessorL1 set WormholeTargetDispenserL2 to l2TargetDispenser.