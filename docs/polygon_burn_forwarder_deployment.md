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
it deploys to. `deploy_00c_bridge2burner_polygon.sh` now runs a read-only audit of **both chains** before broadcasting the bridge
creation. It compares the recorded addresses with the CREATE2 address derived from the reviewed build, checks full
runtime and all five immutable values on both chains, then audits the new bridge's code, recipient, version and
100-OLAS threshold after deployment. Either audit failure stops the script.

Run the audits separately, from the repository root, to inspect or retry without redeploying:

```bash
node scripts/audit_chains/audit_staking_routes.js forwarders
node scripts/audit_chains/audit_staking_routes.js bridge
```

Use the same reviewed Forge `out/` artifacts as the deployment. RPCs come from the two utils globals; environment
variables `AUDIT_L1_RPC_URL` and `AUDIT_L2_RPC_URL` can override them, with chain-ID validation. Checks report all
mismatches/unreadable calls and return nonzero. Before a later BBB implementation upgrade, its old `bridge2Burner`
binding may differ from the newly recorded bridge address; that expected whole-system audit mismatch does not
invalidate the new bridge. The forwarder and bridge deployment audits themselves must pass.

Only after both deployments are validated should the burn route be enabled.
`BuyBackBurner.bridge2Burner` and `LiquidityManagerBurnViaBridge.bridge2Burner` are
immutable, so confirm their intended addresses before deploying those contracts.
