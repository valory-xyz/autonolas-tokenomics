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

## Deployment record — 2026-11-12

Deployed from a clean checkout of `main` at commit `1bd6256`, Forge **v1.7.1**
(`FOUNDRY_SOLC_VERSION=0.8.30`; `foundry.toml` optimizer 200, viaIR, Prague). The
init-code hash and CREATE2 address were identical under Forge 1.5.1 and 1.7.1.

Constructor values (identical on both chains):
- `polygonOlas` `0xFEF5d947472e72Efbb2E388c730B7428406F2F95`
- `l1Olas` `0x0001A500A6B18995B03f44bb040A5fFc28E45CB0`
- `olasBurner` `0x51eb65012ca5cEB07320c497F4151aC207FEa4E0`
- `polygonChainId` `137`, `l1ChainId` `1`

CREATE2: deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C`,
salt `keccak256("PolygonBurnForwarder")` = `0x0f124b2d17c6fcf27566e516b4055f2a6d21b6e8511864ce5272ef5ea7ba1326`,
**init-code hash `0x7677fff0cf0f38b7143d3f6ba03ce493e045a979051e6bb79fa2b681c6f6d2e7`**.

| Contract | Chain | Address | Creation tx |
|---|---|---|---|
| PolygonBurnForwarder | Polygon (137) | `0x11B1498da96129306EAABA68121B3dFc470166c1` | `0xd942d9f52c13e42cf8188dcb66a172afb561a8083e240999bb805404fbb1a2af` |
| PolygonBurnForwarder | Ethereum (1) | `0x11B1498da96129306EAABA68121B3dFc470166c1` | `0x75314cf8684f0e6e521f5af81d08bacbed4e4582127fcf9839325dcae2ef0c53` |
| Bridge2BurnerPolygon | Polygon (137) | `0x0090894802E496f0cA7D283BAA643278F5969F75` | `0xbddcccee4d5d9d820d2fb41d1774b7f66388d0ec394b2ff081270a8b6ead0094` |

Deployer EOA `0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E`. Both `deploy_00e` on-chain
immutable validations and the `audit_staking_routes.js forwarders`/`bridge` audits
passed (runtime hash matches the reviewed build; `l2TokenRelayer` = the forwarder;
`VERSION` 0.1.0; `MIN_OLAS_BALANCE` 100 OLAS). Source verified on Etherscan/Polygonscan
and Sourcify (Blockscout direct submission was Cloudflare-blocked; Sourcify covers it).
Burn routing is NOT yet enabled — `Bridge2BurnerPolygon` recipient is not yet routed to this contract; that routing
change is a separate later step.
