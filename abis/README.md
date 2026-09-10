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

The Robinhood pair is worth one note, because it is the case this directory exists to catch arriving
in a new form. `abis/0.8.30/Arbitrum{DepositProcessorL1,TargetDispenserL2}.json` share the Robinhood
deployment's source, solc version and settings, but not its metadata hash — so pointing the
`configuration.json` entries at them produced a permanent Tier-2 `metadata-trailer drift` warning and
left a regeneration hazard: the next `chore: updating ABIs` could move the length, set
`bytecodeMismatchFound` and exit 1. Identical logic is not sufficient; the artifact has to be the
build that was deployed.

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
