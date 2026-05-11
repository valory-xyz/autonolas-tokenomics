# BBB Update Cycle — Deployment Options

Companion to the deployment-parameters flow for the PR #272 + #278 update cycle. Two options for how broadly to roll out the new BBB implementation + its V3 path. Scope assumptions:

- **Celo** excluded from BBB refresh (Ubeswap V2 only, and the whOLAS ↔ native-OLAS-CELO reconfiguration has to settle first). `Bridge2BurnerOptimism` is still deployed on Celo in every option because the contract itself is forward-looking and won't change.
- **Gnosis** gets a V2-only BBB because no viable V3 ecosystem exists on Gnosis for OLAS.
- `Bridge2Burner*` is deployed on **every** chain in every option — it's a prerequisite for any L2 → L1 OLAS bridging and is not coupled to V3.

## Chain / DEX matrix

| Chain | V2 source (OLAS LP) | V3 sink | OLAS disposal | LM variant |
|-------|---------------------|---------|----------------|------------|
| Ethereum | Uniswap V2 | Uniswap V3 | local `OLAS.burn` | `LiquidityManagerETH` ✓ exists |
| Optimism | Balancer V2 | Velodrome CL (Slipstream fork) | `Bridge2BurnerOptimism` | `LiquidityManagerOptimism` ✓ exists |
| Base | Balancer V2 | Aerodrome Slipstream | `Bridge2BurnerOptimism` | `LiquidityManagerOptimism` ✓ exists |
| Arbitrum | Balancer V2 | **Uniswap V3** | `Bridge2BurnerArbitrum` | ❌ **does not exist** (Balancer V2 + Uniswap V3 + bridge) |
| Polygon | Balancer V2 | **Uniswap V3** | `Bridge2BurnerPolygon` | ❌ **does not exist** (Balancer V2 + Uniswap V3 + bridge) |
| Gnosis | Balancer V2 | — | `Bridge2BurnerGnosis` | N/A — V2-only, no LM needed |
| Celo | Ubeswap V2 | — | `Bridge2BurnerOptimism` | N/A — excluded this cycle |

The current two LM implementations cover exactly two (V2-source, V3-sink) pairs: Uniswap V2 + Uniswap V3 (= `LiquidityManagerETH`) and Balancer V2 + Slipstream (= `LiquidityManagerOptimism`). Arbitrum and Polygon need a third combination that doesn't exist, but is an easy composition of the two without any new code logic.

Baseline for both options below: BBB is upgraded on **every non-Celo chain** because the Feb-2025 implementation carries bug fixes and features from PR #272/#278 (V2 oracle rewrite, deadline param on `buyBack`, per-token slippage, reentrancy-first ordering, etc.) that we can't leave out. The two options differ only in whether V3 is enabled on Arbitrum + Polygon.

## Option A — V3 enabled on ETH + Base + Optimism; V3 disabled on Arbitrum / Polygon / Gnosis

**Scope.** Deploy LM on ETH (`LiquidityManagerETH`), Base + Optimism (`LiquidityManagerOptimism`). Upgrade BBB on all non-Celo chains. On Arbitrum, Polygon, Gnosis the new BBB is deployed with V3 explicitly disabled (both `liquidityManagerProxyAddress` and `swapRouterV3Address` set to `0x0000000000000000000000000000000000000000` in those chains' `utils/globals_*.json`); V3 path is blocked at runtime by `V3PathDisabled`, V2 path continues to work. Deploy details in the [Appendix](#appendix--per-chain-deploy-steps).

**Pros.** Whole BBB fleet (except Celo) lands on a single new implementation. Non-V3 fixes propagate everywhere. Gnosis stays V2-only forever, which is correct for that chain. V3 on Arbitrum + Polygon stays off until a later cycle that solves the LM gap.

**Cons.** Requires explicit `0x0000…0000` zeroing of globals on Arbitrum + Polygon + Gnosis. Deploy operator has to remember that V3-enabling Arbitrum + Polygon later needs a fresh BBB re-deploy (because the new LM variant would need to be wired via constructor), not just a `changeImplementation` that flips flags.

## Option B — V3 enabled on all five mainstream chains (ETH + Optimism + Base + Arbitrum + Polygon)

**Scope.** Option A, plus also deploy LM + turn on V3 on Arbitrum and Polygon. Gnosis stays V2-only, Celo excluded. Requires a new `(Balancer V2, Uniswap V3)` LM variant — a combination of the two existing LMs — plus its fork tests. Deploy details in the [Appendix](#appendix--per-chain-deploy-steps).

**Pros.** Full V3 coverage across every chain where it's technically feasible. One rollout cycle; no "we'll come back to Arbitrum/Polygon later" tail. Matches the marketplace-fee activation plan's aspiration of having a canonical buyBack + LP path on every earning chain.

**Cons.** Adds a third LM contract to maintain in parallel with the existing two, unless we also take that opportunity to refactor the LMs into composable V2-source / V3-sink / disposal policies (larger refactor but scales with N chains). The composed LM still needs fork tests against real Arbitrum/Polygon pools before BBB can be flipped to V3-enabled there.

## Comparison

| | Option A | Option B |
|---|---|---|
| V3 enabled on | ETH, Base, Optimism | ETH, Base, Optimism, Arbitrum, Polygon |
| BBB upgraded on | All 6 chains (ETH + 5 L2s) | All 6 chains (ETH + 5 L2s) |
| New LM contract work | None | `LiquidityManagerBalancerUniswap` + fork tests |
| `Bridge2Burner*` deploy | All 6 chains + Celo | All 6 chains + Celo |
| Gnosis | V2-only (explicit V3 zeros) | V2-only (explicit V3 zeros) |
| Celo | Excluded | Excluded |

## Cross-cutting notes

1. **`changeImplementation` vs fresh re-deploy.** Every option above assumes `script_01_buy_back_burner_change_implementation.sh` is used on the existing proxies. `audits/internal15/README.md` H-01 + `FINAL_REVIEW.md` §2 argue for fresh re-deploy via `deploy_03/04_buy_back_burner_*_proxy.sh` instead — the concern being slot-7 reinterpretation on the original Feb-2025 proxy layout. Whichever option is chosen, worth confirming which upgrade path the ops team is committed to and updating the deployment parameters + audit disposition accordingly.
2. **BBB proxy ownership on Base.** Today owned by `0x6F7a4938AB3bbF69480E7C109Af778ee78099Be7` (derivationPath `m/44'/60'/9'/0/0`, agents.fun legacy). Every option needs a `changeOwner` to the Autonolas deployer as a first step before anything else on Base.
3. **`utils/globals_*_mainnet.json` V3 fields.** Under PR #278's fail-closed policy, any BBB impl deploy requires both `liquidityManagerProxyAddress` and `swapRouterV3Address` to be set explicitly — real addresses for V3-enabled or `0x0000…0000` for V3-disabled. Empty strings refuse to deploy. Option A adds explicit zero-fill for Arbitrum + Polygon (Gnosis is already zeroed). Option B instead populates real addresses on those two after the new LM proxy is deployed.
4. **Marketplace fee activation.** This BBB cycle is a prerequisite for the plan in `marketplace_protocol_fee_activation.md`. Option A unlocks fee activation on Base + Optimism (WETH fees route via Balancer OLAS/WETH) and on Ethereum (WETH via Uniswap V2), and covers Arbitrum + Polygon with USDC fees sweeping to treasury only (no V3 swap there). Option B lets Arbitrum + Polygon USDC/WETH fees also get buy-back-and-burned locally via their Uniswap V3 pools.

## Recommendation

Pick based on how much of the V3-coverage goal you want to land in this cycle:
- **Option A** — clean single-impl fleet across every non-Celo chain, defers the Balancer-V2 + Uniswap-V3 combo (for Arbitrum + Polygon V3) to a follow-up.
- **Option B** — complete V3 coverage, aligned with the marketplace-fee activation trajectory, no "we'll do Arbitrum/Polygon later" debt. Cost is the composed LM variant — an easy mix from both ETH and Base LM contracts without any new code logic — plus its fork tests.

## Appendix — per-chain deploy steps

### Option A

- **ETH**: `pol/deploy_01_neighborhood_scanner.sh` → `pol/deploy_02_liquidity_manager_eth.sh` → `pol/deploy_03_liquidity_manager_proxy.sh` → copy `liquidityManagerProxyAddress` into `utils/globals_eth_mainnet.json` → BBB impl + `changeImplementation`.
- **Base + Optimism**: `pol/deploy_01_neighborhood_scanner.sh` → `pol/deploy_02_liquidity_manager_optimism.sh` → `pol/deploy_03_liquidity_manager_proxy.sh` → copy proxy address → BBB impl + `changeImplementation`. Base needs `pol/globals_base_mainnet.json` added first (copy from `optimism_mainnet`, swap addresses).
- **Arbitrum + Polygon**: set both V3 fields in `utils/globals_<chain>_mainnet.json` to explicit zero addresses. Then `deploy_01_buy_back_burner_balancer.sh` + `script_01_buy_back_burner_change_implementation.sh`. No LM or pol-directory work on these chains.
- **Gnosis**: already has zeros in globals. `deploy_01_buy_back_burner_balancer.sh` + `script_01_buy_back_burner_change_implementation.sh`.

### Option B — deltas on top of Option A

- **Arbitrum + Polygon**: add `pol/globals_<chain>_mainnet.json`; deploy `NeighborhoodScanner` → new `LiquidityManagerBalancerUniswap` impl → `LiquidityManagerProxy` → copy proxy address into `utils/globals_<chain>_mainnet.json` → `deploy_01_buy_back_burner_balancer.sh` + `changeImplementation`.
- **Everything else**: same as Option A.
