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

## LM deployment parameter rationale

Values currently in `scripts/deployment/pol/globals_<chain>_mainnet.json`:

| Field | ETH | Base | Optimism |
|---|---|---|---|
| `observationCardinality` | 120 | 300 | 300 |
| `liquidityManagerMaxSlippage` | 1000 | 1000 | 1000 |

### `observationCardinality` (constructor arg → `LiquidityManagerCore.observationCardinality`, immutable)

Used once per fresh pool inside `convertToV3`:

```solidity
IUniswapV3(v3Pool).increaseObservationCardinalityNext(observationCardinality);
```
(`LiquidityManagerCore.sol:733`)

The Uniswap V3 buffer can hold at most one observation per block, so the nominal worst-case TWAP coverage from a freshly-initialized pool is `cardinality × block_time`:

- ETH (12s blocks): `120 × 12s = 1440s` nominal worst-case coverage (~80% of `SECONDS_AGO`).
- Base/Optimism (2s blocks): `300 × 2s = 600s` nominal worst-case coverage (~33% of `SECONDS_AGO`).

These nominal values do **not** match the contract's `SECONDS_AGO = 1800s` TWAP window; matching it directly (`cardinality ≈ 1024` on 2s-block L2s) is rejected because of gas — see the empirical table below.

**Anchoring** — values were chosen against mid-volume production V3 pool cardinality precedent on ETH mainnet ([Alex Roan gist](https://gist.github.com/alexroan/71b38d387ed2a86bf3abdf3acd0f8415)):

| Reference pool | Production `observationCardinality` |
|---|---|
| ETH/USDC 0.05% | 720 |
| ETH/USDC 0.3% | 1440 |
| DAI/ETH | 300 |
| UNI/ETH | 300 |
| LINK/ETH | 144 |
| OHM/USDC, stETH/ETH | 1 (default — never bumped) |

OLAS sits below LINK on ETH and below DAI/UNI on the L2 mid-volume side. So `120` (ETH) and `300` (L2) anchor to that band: ETH slightly below the LINK reference because OLAS volume is meaningfully lower than LINK; L2s at the DAI/UNI level because cheap L2 gas allows the wider envelope without budget pressure.

**Empirical gas** — measured in `test/LiquidityManagerObservationCardinalityGasETH.t.sol` (ETH fork):

| `observationCardinality` arg | `increaseObservationCardinalityNext` gas | Note |
|---|---|---|
| 120 | ~2.66M | Production ETH choice |
| 300 | ~6.66M | Production Base/Optimism choice |
| 1024 | **~22.76M** | Reference — exceeds realistic L1 tx budget once V3 mint (~500k–1M) and LM accounting are layered; also exceeds the operator-side 16M L2 ceiling |

Both production values are safe in practice because:

1. **One observation written per block, not per swap.** For sparsely-traded OLAS pools the buffer covers real-time windows far longer than the nominal worst-case — a 300-slot buffer covers `300 × 60s = 18000s = 5 hours` on Base under a "one swap per minute" surge, well past `SECONDS_AGO=1800s`.
2. **`checkPoolAndGetCenterPrice` falls back to slot0 for freshly-initialized pools** (`LiquidityManagerCore.sol:1145-1153`, audit `internal15` M-01 / `internal16` "TWAP observation cardinality" note) — `observe()` reverts on `cardinality <= 1`, and the contract degrades gracefully with the deviation guard still in force.
3. **`increaseObservationCardinalityNext` is permissionless on the pool.** If a specific pool needs more buffer than the constructor default, anyone can call it directly via `cast send <pool> "increaseObservationCardinalityNext(uint16)" <N>` after deployment — no LM redeploy needed. The constructor immutable is only the baseline for the first `convertToV3` against a fresh pool.

Optimism uses the same 300 as Base because both run 2s blocks; the Velodrome Slipstream pool is a Uniswap V3 fork with identical observation semantics.

**Operational runbook (cardinality wrap-around).** The buffer is sized for typical OLAS-pool activity, not for the worst case of one observation per block sustained across the full 1800s window. If the pool enters a sustained-activity regime that risks exhausting the buffer (e.g. post-launch interest surge, MEV bot routing, deep DEX-aggregator integration), `convertToV3` and the BBB V3 buyBack will start to revert with `ObservationFailed(pool)`. Detection signal: `(oldestObservationAge / SECONDS_AGO)` per active V3 pool drops below ~1.5×, queryable via `IUniswapV3.observations(observationIndex)`. Mitigation: anyone can bump the affected pool's cardinality via `cast send <pool> "increaseObservationCardinalityNext(uint16)" <new_value>` — operation is permissionless and idempotent (no effect if `new_value` ≤ current `cardinalityNext`). Recommended ramp: double the current value each step (`300 → 600 → 1200`) until the activity regime stabilizes. Failure mode is service degradation only — no fund loss path.

### `liquidityManagerMaxSlippage` (initialize arg → `LiquidityManagerCore.maxSlippage`, mutable)

Seeded via `LiquidityManagerCore.initialize(uint16 _maxSlippage)` from the proxy constructor (`deploy_03_liquidity_manager_proxy.sh`), used in three places to compute `amount{0,1}Min` for V3 position manager calls:

- `_optimizeTicksAndMintPosition` (`LiquidityManagerCore.sol:552-553`)
- `_increaseLiquidity` (`LiquidityManagerCore.sol:432-433`)
- `_decreaseLiquidity` (`LiquidityManagerCore.sol:374-375`)

Production value `1000` (= 10%) is chosen to align with the contract's `MAX_ALLOWED_DEVIATION` (10%, `LiquidityManagerCore.sol:122`).

**Why the two guards co-exist.** `MAX_ALLOWED_DEVIATION` and `liquidityManagerMaxSlippage` are not redundant despite operating at the same percentage:

- `MAX_ALLOWED_DEVIATION` (constant, contract-level) is a **pre-flight pool-sanity gate in price space**: rejects operation outright when `slot0` has been pushed more than 10% off TWAP, an anti-manipulation primitive. Tamper-evident — owners cannot loosen it without redeploying the implementation.
- `liquidityManagerMaxSlippage` (storage, mutable, per-deploy) is a **post-flight execution gate in amount space**: the V3 NPM's own `amount0Min`/`amount1Min` parameter, which the mint signature requires us to pass. Tunable via `changeMaxSlippage()`.

The two checks operate in different units (price vs amount) and at different points in the call lifecycle. Even with `slot0 == TWAP` exactly, the V3 mint's amount math is non-linear in the tick range — a 10% price-space tolerance does not produce exactly 10% amount-space drift, it can be more or less depending on tick width and where slot0 sits. Setting `liquidityManagerMaxSlippage` to the same percentage as `MAX_ALLOWED_DEVIATION` is a coherence heuristic: give the mint enough amount-space slack to land what the upstream deviation guard has already accepted as a sane pool state. Setting it lower (e.g. 500 bps = 5%) creates a 5–10% band where the LM is willing to operate but the V3 mint reverts on the amount-min check; setting it higher leaves the deviation guard doing all the work and the amount-min check effectively disabled.

Updatable post-deploy via `LiquidityManagerCore.changeMaxSlippage(uint16)` (`LiquidityManagerCore.sol:624`), so the initial value can be tightened or loosened later based on observed pool behavior without a redeploy.

### Obsolete fields

`v3PoolStatuses` was removed from `globals_<chain>_mainnet.json` and from `scripts/deployment/pol/README.md`. The on-chain setter is `BuyBackBurner.setV3Pools(address[] secondTokens, address[] pools)` (`contracts/utils/BuyBackBurner.sol:393`) — two arrays, no statuses — and `script_03_buy_back_burner_wire_v3.sh` already never read it.
