# Autonolas tokenomics ABIs
These ABIs were obtained with 4000 optimization passes.

## `deployed/`

`docs/configuration.json` describes **what is deployed**, and `scripts/audit_chains/audit_contracts_setup.js`
compares each entry's address against the artifact that entry names. So an artifact under a name that
several deployments share cannot be regenerated in place for whichever one was built most recently —
doing that silently breaks the comparison for all the others.

`abis/deployed/` holds one artifact per deployment for exactly those cases: the four L1 deposit
processors recorded as `OptimismDepositProcessorL1` (Optimism, Base and Mode share a build; Celo has
its own from its 2026-01 redeploy), the L2 target dispensers that share the
`OptimismTargetDispenserL2` name, and — since the Robinhood (4663) rollout — the two Arbitrum Orbit
names `ArbitrumDepositProcessorL1` and `ArbitrumTargetDispenserL2`, each of which now covers two
deployments on two distinct builds: Arbitrum One on the original, Robinhood on the ^0.8.30 rebuild
(`RobinhoodDepositProcessorL1.json`, `RobinhoodTargetDispenserL2.json`), and the four buyback-stack
contracts Robinhood shares with earlier deployments — `UniswapPriceOracle`, `Bridge2BurnerArbitrum`,
`BuyBackBurnerUniswap` and `BuyBackBurnerProxy`, each recorded under a `Robinhood`-prefixed name for the
same reason. Most files here were
recovered from this repo's history; the two Robinhood ones are the build that was deployed, and each
matches its deployment's on-chain code length **and** metadata trailer exactly.

## Why the artifact must come from the pipeline that deployed it

The trailing 43 bytes of a contract's runtime are not a hash of the code. They are the solc version
plus the IPFS hash of the **metadata JSON**, and that document records the remappings, source paths
and settings of the compilation — not just the source and the optimizer. Two pipelines can therefore
produce byte-identical executable code and different trailers.

That is exactly what separates the two families of artifact here. Files under `abis/<solc>/` are
**hardhat** artifacts (`"_format": "hh-sol-artifact-1"`), produced by `npx hardhat compile`; hardhat
resolves `node_modules` imports natively and emits no remappings. The `scripts/deployment/**.sh`
route deploys with **`forge create`**, and foundry records its remappings in `settings`. Same solc,
same `optimizer` runs, same `evmVersion`, same `viaIR` — different metadata document, different hash.

So any contract deployed through the shell route will differ from its `abis/<solc>/` artifact in
those 32 bytes, however correct the source and settings are. `checkBytecode` compares the final 43
bytes, so pointing a `configuration.json` entry at the hardhat artifact produces a permanent Tier-2
`metadata-trailer drift` warning, and leaves a regeneration hazard: the next `chore: updating ABIs`
could move the length, set `bytecodeMismatchFound` and exit 1.

**Identical logic is not sufficient — the artifact has to be the build that was deployed.** For the
shell route that means committing the `out/` artifact here under a deployment-specific name. This is
a standing rule for every future shell-route deployment, not a Robinhood-specific step; the Robinhood
entries are simply the first set recorded under it.

An artifact for code that is **not** deployed yet keeps its `abis/<solc>/` home. It should not be
pointed at from a `configuration.json` entry until the redeploy lands.

`BuyBackBurnerProxy` has three entries because one unchanged source was compiled three ways:
`abis/0.8.30/` is viaIR at 200 runs (celo), `deployed/BuyBackBurnerProxy-legacy-lowruns.json` is legacy
codegen at low runs (mainnet, polygon, arbitrum, optimism), and
`deployed/BuyBackBurnerProxy-legacy-4000runs.json` is legacy at the 4000 passes this file used to
prescribe (gnosis). Base is deliberately absent: its proxy is 212 B, below what this source can
produce, and lacks `getImplementation()` entirely.

`BuyBackBurnerProxyV1` is the earlier proxy revision, deployed only on Base. It differs from
`BuyBackBurnerProxy` in one respect: it does not expose `getImplementation()`. The implementation is
held in the same `keccak256("BUY_BACK_BURNER_PROXY")` slot and remains readable with
`eth_getStorageAt`, but a call to `getImplementation()` falls through `fallback()` to the
implementation and reverts. Its source is in `contracts/utils/` so the artifact stays reproducible;
new deployments should use `BuyBackBurnerProxy`.
