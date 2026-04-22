# Protocol-Owned Liquidity (POL) deployment

Forge-based shell scripts for deploying `NeighborhoodScanner` + `LiquidityManagerETH` /
`LiquidityManagerOptimism`, plus the post-deploy V3 wiring for the BuyBackBurner proxy.

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

Run in order, passing the network suffix (`eth_mainnet`, `optimism_mainnet`, `mode_mainnet`):

```bash
./scripts/deployment/pol/deploy_01_neighborhood_scanner.sh   eth_mainnet
./scripts/deployment/pol/deploy_02_liquidity_manager_eth.sh  eth_mainnet

# Populate v3Pools / v3PoolStatuses / v3SecondTokens / v3MaxSlippages in globals first,
# then:
./scripts/deployment/pol/script_03_buy_back_burner_wire_v3.sh eth_mainnet
```

For Optimism / Mode, replace `deploy_02_liquidity_manager_eth.sh` with
`deploy_02_liquidity_manager_optimism.sh`.

After `deploy_02` writes `liquidityManagerAddress` into the local `globals_*.json`, copy that
value into `scripts/deployment/utils/globals_*.json` so the BBB implementation step (utils/02)
picks it up. Alternatively, deploy order can be reorganised so the LM is deployed before the
BBB implementation.

## Globals fields

| Field | Consumed by | Notes |
|---|---|---|
| `olasAddress` | deploy_02 | OLAS token on target chain |
| `timelockAddress` (ETH) | deploy_02 | Treasury on L1 |
| `bridgeMediatorAddress` (L2s) | deploy_02 | Treasury on L2 |
| `positionManagerV3Address` | deploy_02 | Uniswap V3 NonfungiblePositionManager (ETH: `0xC36442b4a4522E871399CD717aBDD847Ab11FE88`). On Optimism / Mode this is Slipstream's equivalent — populate per chain |
| `neighborhoodScannerAddress` | deploy_02 | Written by deploy_01 |
| `observationCardinality` | deploy_02 | uint16, observation buffer for fresh V3 pools (default 60) |
| `uniswapPriceOracleAddress` (ETH) | deploy_02 | From oracles step |
| `balancerPriceOracleAddress` (L2s) | deploy_02 | From oracles step |
| `routerV2Address` (ETH) | deploy_02 | Uniswap V2 Router |
| `balancerVaultAddress` (L2s) | deploy_02 | Balancer V2 Vault |
| `bridge2BurnerAddress` (L2s) | deploy_02 | Bridge2BurnerOptimism/Mode (from `utils/deploy_00b_bridge2burner_*.sh`) |
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
