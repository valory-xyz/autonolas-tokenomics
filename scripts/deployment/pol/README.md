# Protocol-Owned Liquidity (POL) deployment

Forge-based shell scripts for deploying `NeighborhoodScanner`, `LiquidityManagerETH` /
`LiquidityManagerOptimism` (impl), `LiquidityManagerProxy` (proxy), plus the post-deploy V3
wiring for the BuyBackBurner proxy.

> **POL is per-chain optional.** As of the V3-optional `BuyBackBurner` change
> (Vulnerabilities_list item #21), chains that deploy `BuyBackBurner` with
> `liquidityManagerAddress = ""` and `swapRouterV3Address = ""` get a working V2-only
> deployment. The V3 path reverts `V3PathDisabled` until a new impl is deployed with both
> addresses populated and `changeImplementation` is called on the proxy. Skip the entire
> `pol/` directory for V2-only chains — no LM, no scanner, no V3 wire step.

## Prerequisites (run first, from other folders)

1. `scripts/deployment/oracles/` — deploys `UniswapPriceOracle` (ETH) or `BalancerPriceOracle` (L2s).
   The resulting `uniswapPriceOracleAddress` / `balancerPriceOracleAddress` is copied into `globals_*.json` here.
2. `scripts/deployment/utils/deploy_01|02_buy_back_burner_*.sh` — deploys the BBB **implementation**.
3. `scripts/deployment/utils/deploy_03|04_buy_back_burner_*_proxy.sh` — deploys the BBB **proxy**.
   The resulting `buyBackBurnerProxyAddress` is copied into `globals_*.json` here.

## Step sequence

Run in order, passing the network suffix (`eth_mainnet`, `optimism_mainnet`):

```bash
./scripts/deployment/pol/deploy_01_neighborhood_scanner.sh    eth_mainnet
./scripts/deployment/pol/deploy_02_liquidity_manager_eth.sh   eth_mainnet
./scripts/deployment/pol/deploy_03_liquidity_manager_proxy.sh eth_mainnet

# Populate v3Pools / v3PoolStatuses / v3SecondTokens / v3MaxSlippages in globals first,
# then:
./scripts/deployment/pol/script_03_buy_back_burner_wire_v3.sh eth_mainnet
```

For Optimism, replace `deploy_02_liquidity_manager_eth.sh` with
`deploy_02_liquidity_manager_optimism.sh`. The proxy step (`deploy_03_liquidity_manager_proxy.sh`)
is chain-agnostic — same script for ETH, Optimism, etc. — because the proxy constructor is
`(impl, initData)` where `initData = initialize(uint16 _maxSlippage)` is identical across
LiquidityManagerCore-derived impls.

After `deploy_03` writes `liquidityManagerProxyAddress` into the local `globals_*.json`, copy
that value into `scripts/deployment/utils/globals_*.json` (same field name) so the BBB
implementation step (utils/01 or utils/02) picks it up. **Always wire the proxy address into
the BBB, not the impl** — the BBB calls `liquidityManager.factoryV3()` at runtime, and the
proxy delegatecall-reads the impl's immutables. Wiring the impl directly would break a future
`changeImplementation()` upgrade.

## Globals fields

| Field | Consumed by | Notes |
|---|---|---|
| `olasAddress` | deploy_02 | OLAS token on target chain |
| `timelockAddress` (ETH) | deploy_02 | Treasury on L1 |
| `bridgeMediatorAddress` (L2s) | deploy_02 | Treasury on L2 |
| `positionManagerV3Address` | deploy_02 | Uniswap V3 NonfungiblePositionManager (ETH: `0xC36442b4a4522E871399CD717aBDD847Ab11FE88`). On Optimism this is Velodrome Slipstream's equivalent — populate per chain |
| `neighborhoodScannerAddress` | deploy_02 | Written by deploy_01 |
| `observationCardinality` | deploy_02 | uint16, observation buffer for fresh V3 pools (default 60) |
| `uniswapPriceOracleAddress` (ETH) | deploy_02 | From oracles step |
| `balancerPriceOracleAddress` (L2s) | deploy_02 | From oracles step |
| `routerV2Address` (ETH) | deploy_02 | Uniswap V2 Router |
| `balancerVaultAddress` (L2s) | deploy_02 | Balancer V2 Vault |
| `bridge2BurnerAddress` (L2s) | deploy_02 | Bridge2BurnerOptimism (from `utils/deploy_00b_bridge2burner_*.sh`) |
| `liquidityManagerAddress` | deploy_02→deploy_03 | Written by deploy_02 (impl); consumed by deploy_03 as proxy constructor target |
| `liquidityManagerMaxSlippage` | deploy_03 | uint16 BPS (MAX_BPS = 10_000); seeds `LiquidityManagerCore.initialize(uint16)`. Default `500` (5%) — tune per chain before running deploy_03 |
| `liquidityManagerProxyAddress` | deploy_03 (writes) | Proxy address — copy into `utils/globals_*.json` for BBB impl deploy |
| `buyBackBurnerProxyAddress` | script_03 | BBB proxy address (copied from `utils/globals_*.json`) |
| `v3Pools`, `v3PoolStatuses` | script_03 | Parallel arrays; `v3PoolStatuses` must be all `true` to whitelist |
| `v3SecondTokens`, `v3MaxSlippages` | script_03 | Parallel arrays; slippage in bps (e.g. `500` = 5%) |

## Why the wire step is mandatory

`contracts/utils/BuyBackBurner.sol` (lines 251 and 269–271) enforces two guards on the V3
buyBack path:

- **UnauthorizedPool** — V3 buyBack reverts unless the pool is present in `mapV3Pools`.
- **amountOutMin = TWAP quote with zero slippage** — if `mapTokenMaxSlippages[secondToken] == 0`,
  the DEX-side `amountOutMinimum` equals the TWAP quote, which is not realistically reachable
  after fees. Intentional fail-closed behavior (closes PR #275 / H-02).

Both must be configured before the first V3 buyBack on that (pool, token) pair.

## Upgrade-flow caveats (BBB impl swap via `changeImplementation`)

The current redeploy flow swaps the impl behind each chain's **existing** BBB proxy via
`utils/script_01_buy_back_burner_change_implementation.sh <chain>_mainnet` rather than
deploying a fresh proxy. Three things to know before running:

1. **Storage layout compatibility.** `changeImplementation` preserves proxy storage; the new
   `BuyBackBurner` introduces immutables (`liquidityManager`, `bridge2Burner`, `treasury`,
   `swapRouter`) but those are inlined into bytecode, not storage. Storage slots
   `owner / olas / nativeToken / oracle / maxSlippage / _locked / mapAccountActivities /
   mapV2Oracles / mapV3Pools / mapTokenMaxSlippages` must align with the old impl. If you're
   not 100% sure the old impl declared these in the same order with the same slot widths,
   spot-check one chain with `cast storage <proxy> <slot>` before mass-rolling.

2. **Post-changeImpl configuration is required** for buyback to function. After
   `script_01_*` lands, each BBB proxy still needs:
   - `setV2Oracles(secondTokens, oracles)` — maps each second token (WETH/WMATIC/WXDAI/…) to
     its `*PriceOracleAddress`.
   - `setMaxSlippages(secondTokens, slippages)` — per-token slippage in BPS. **This is no
     longer an initializer field** (`maxBuyBackSlippage` was dead config in the old proxy
     payload; the new flow drops it).
   - `setV3Pools(secondTokens, pools)` — V3-enabled chains only (Base, Optimism, ETH).
   Without these, `buyBack()` reverts: V2 path with `"Zero oracle address"`, V3 path with
   `UnauthorizedToken` or an unfillable `amountOutMin`. Done via separate cast calls or
   governance proposal — not part of the deploy scripts.

3. **Base BBB proxy owner is the legacy agents.fun deployer.** Owner of `0x3FD8…1426` is
   `0x6F7a4938AB3bbF69480E7C109Af778ee78099Be7` (derivationPath `m/44'/60'/9'/0/0`),
   inherited from the autonolas-marketplace lineage. All other chains' BBB proxy owner is
   the Autonolas deployer `0xEB2A…914E` (`m/44'/60'/2'/0/0`). Two valid reconciliation paths
   before running `script_01 base_mainnet`:
   - Call `proxy.changeOwner(0xEB2A…914E)` from the agents.fun derivation path first
     (one extra tx, Base only), then run `script_01` with the standard Autonolas path.
   - Or temporarily set `utils/globals_base_mainnet.json` `derivationPath` to
     `m/44'/60'/9'/0/0` for the single `script_01 base_mainnet` run, then revert the JSON.

   Without one of these, the call reverts `OwnerOnly`.
