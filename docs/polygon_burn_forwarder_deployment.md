# Polygon burn forwarder deployment

Deploy and validate `PolygonBurnForwarder` on both Ethereum and Polygon before any
burn routing points at it. Run `scripts/deployment/utils/deploy_00e_polygon_burn_forwarder.sh`
once with `eth_mainnet` and once with `polygon_mainnet`, from the same checkout and
build. Then deploy `Bridge2BurnerPolygon`, the Polygon LiquidityManager, and the
BuyBackBurner implementation built with those addresses, in that order.

## Build and deployment record

Before deploying, record the full build commit and the init-code hash printed by
`deploy_00e`. Retain both deployments' logs and transaction hashes. The init code
includes the creation bytecode and encoded constructor arguments; its exact bytes,
including compiler metadata, determine the CREATE2 address.

The script pins solc to `0.8.30`. The committed `foundry.toml` sets optimizer runs
to 200, enables the optimizer and viaIR, and targets Prague. `yarn.lock` records
Node dependency versions, and the Git tree records submodule commits. Restore
dependencies from those pins without updating them.

These files do not fully fix the local deployment environment: the script uses the
installed Forge version and effective Foundry configuration, including automatically
detected remappings and environment or profile overrides. The forwarder has no
imports, but remappings are compiler settings and can affect its metadata. Record:

- `git rev-parse HEAD`, using a clean checkout;
- `forge --version` (CI at this revision uses `v1.7.1`);
- `FOUNDRY_SOLC_VERSION=0.8.30 forge config --json` and `forge remappings`;
- the five constructor values printed by the script, along with the factory, salt,
  init-code hash, and predicted address.

The constructor values come from both `globals_eth_mainnet.json` and
`globals_polygon_mainnet.json`; keep those inputs identical for both deployments.
Use the same Forge version, dependency layout, profile and effective compiler
settings on both chains. If rebuilding, compare the resulting init-code hash with
the recorded hash and stop if it differs. A matching commit alone is insufficient.
Complete all source changes, including NatSpec edits, before recording the final
build commit and hash.

## Before enabling burn routing

Confirm that both deployment logs have the same init-code hash and predicted
address, and retain the successful on-chain validation of all five immutable
constructor values on each chain. `deploy_00e` performs this validation on the chain
it deploys to. `deploy_00c_bridge2burner_polygon.sh` checks the Polygon deployment
only; its success does not establish that the Ethereum copy exists.

Only after both deployments are validated should the burn route be enabled.
`BuyBackBurner.bridge2Burner` and `LiquidityManagerBurnViaBridge.bridge2Burner` are
immutable, so confirm their intended addresses before deploying those contracts.
