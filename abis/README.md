# Autonolas tokenomics ABIs
These ABIs were obtained with 4000 optimization passes.

## `deployed/`

`docs/configuration.json` describes **what is deployed**, and `scripts/audit_chains/audit_contracts_setup.js`
compares each entry's address against the artifact that entry names. So an artifact under a name that
several deployments share cannot be regenerated in place for whichever one was built most recently —
doing that silently breaks the comparison for all the others.

`abis/deployed/` holds one artifact per deployment for exactly those cases: the four L1 deposit
processors recorded as `OptimismDepositProcessorL1` (Optimism, Base and Mode share a build; Celo has
its own from its 2026-01 redeploy), and the L2 target dispensers that share the
`OptimismTargetDispenserL2` name. Every file here was recovered from this repo's history and matches
its deployment's on-chain code length exactly.

An artifact for code that is **not** deployed yet keeps its `abis/<solc>/` home. It should not be
pointed at from a `configuration.json` entry until the redeploy lands.
