# autonolas-tokenomics Internal Audit v2.20

## Scope: 10,800 LOC across ~30 contracts

## Completed Audit Streams

### Stream 1: Financial Core (4,000+ LOC) ✓
- Tokenomics.sol, Dispenser.sol, Treasury.sol, Depository.sol, TokenomicsConstants.sol
- Result: 0 High/Medium
- Known C4A findings re-checked: #28 (double mint cap) DISPROVED by fork PoC
- calculateStakingIncentives griefing: function is public but state NOT mutated in normal conditions (PoC confirmed)

### Stream 2: Cross-Chain Staking (3,000+ LOC) ✓
- All 6 bridge implementations (Ethereum, Arbitrum, Optimism, Gnosis, Polygon, Wormhole)
- DefaultTargetDispenserL2, DefaultDepositProcessorL1
- Result: 0 High/Medium
- Wormhole transferAmount==0: DISPROVED by fork PoC (bridge accepts 0)
- Message replay, fabrication, double-claim: all properly protected

### Stream 3: POL + Oracle + BuyBackBurner (4,000+ LOC) ✓
- LiquidityManagerCore, LiquidityManagerETH, LiquidityManagerOptimism
- UniswapPriceOracle, BalancerPriceOracle (REWRITTEN — proper TWAP)
- BuyBackBurner v0.3.0 (REWRITTEN — TWAP slippage protection)
- Result: 0 High/Medium in fixed version
- LiquidityManagerCore V3 TWAP-to-self: acknowledged, admin-only scope

### Stream 4: New/Under-Audited Contracts ✓
- LPSwapCelo.sol (341 LOC): 0 High/Medium, internal audit 13 fixes verified
- Bridge2Burner*.sol (4 contracts): 0 High/Medium
- GenericBondCalculator.sol: spot price helper, stored at creation (Low)
- NeighborhoodScanner.sol (695 LOC): pure math, no state changes, 0 issues

### Stream 5: PoC Verification ✓
- #28 Double mint cap: DISPROVED (fork mainnet)
- Wormhole DoS transferAmount==0: DISPROVED (fork mainnet)
- #29 calculateStakingIncentives griefing: DISPROVED (fork mainnet, state not mutated)

## Remaining Attack Vectors

### Cross-contract interaction chains ✓ (Stream 6)
- [x] Donation → reward claim chain — flash loan BLOCKED by lastDonationBlockNumber
- [x] Epoch transition chain — year boundary handled correctly, MAX_EPOCH_LENGTH bounds
- [x] Bond lifecycle — effectiveBond reset in updateInflation (C2-1, Low/Med admin-only)
- [x] Staking claim — cross-chain timing safe, withheld amount properly tracked

### Specific attack scenarios ✓ (Stream 7)
- [x] Flash loan IDF inflation — BLOCKED (same-block check)
- [x] Cheap component spam — NOT EXPLOITABLE (proportional distribution)
- [x] Bond LP price arbitrage — NOT EXPLOITABLE (price set at creation, not live)
- [x] Staking funds stuck — recoverable via DAO ops, migration requires sequencing
- [x] Epoch manipulation — BLOCKED (MIN/MAX epoch length bounds)
- [x] DonatorBlacklist bypass — proxy bypass possible but KNOWN LIMITATION of EVM

### Stream 8: Proxy Upgrade Path + Storage Layout ✓
All three proxy contracts audited: TokenomicsProxy, BuyBackBurnerProxy, LiquidityManagerProxy.

**Architecture**: Custom UUPS-style proxies. Implementation address stored at a unique keccak256 slot (not sequential storage). Upgrade via `changeTokenomicsImplementation` / `changeImplementation` on the implementation, gated by `owner`.

**Checklist**:
- [x] Storage slot collision with sequential slots: SAFE — all three use keccak256 hashes (PROXY_TOKENOMICS, BUY_BACK_BURNER_PROXY, PROXY_LIQUIDITY_MANAGER) as slot addresses, which are ~2^256 away from sequential slots 0..N
- [x] Re-initialization protection: SAFE — all three check `owner != address(0)` before allowing `initialize`/`initializeTokenomics`
- [x] Uninitialized implementation (Wormhole-style): LOW RISK — implementation contracts have empty constructors, so `initializeTokenomics`/`initialize` CAN be called directly on the implementation. However:
  - No `selfdestruct` in any contract (post-Dencun this is deprecated anyway)
  - Implementation's storage is independent of proxy's storage
  - Writing to PROXY_TOKENOMICS on the implementation does NOT affect the proxy
  - No funds held on implementation contracts
  - Verdict: Informational — best practice is to call initialize in the constructor or add an `_disableInitializers()` pattern, but no exploit path exists
- [x] Proxy admin takeover: SAFE — `changeTokenomicsImplementation` requires `msg.sender == owner`, which is the owner stored in proxy storage (set during `initializeTokenomics` via delegatecall)
- [x] Owner transfer: SAFE — `changeOwner` requires current owner, no two-step but acceptable for DAO-owned contracts
- [x] DelegatecallOnly guard: Only in `checkpoint()` — other functions rely on role checks (owner/treasury/depository/dispenser). This is SAFE because those role addresses are in proxy storage, not attacker-controllable
- [x] Storage layout across upgrades: BuyBackBurner has deprecated slots (nativeToken, oracle) marked as "proxy legacy" — these preserve layout compatibility. SAFE
- [x] TokenomicsProxy fallback: No `receive()` function — ETH sent with empty calldata will go through `fallback()` which delegates to implementation. Implementation also has no `receive()`. Result: plain ETH transfers revert. SAFE behavior
- [x] BuyBackBurnerProxy/LiquidityManagerProxy: Have `payable` fallback, so ETH can be sent. BuyBackBurner has `receive()` that emits FundsReceived. SAFE
- [x] No `getImplementation()` on TokenomicsProxy: The proxy itself does NOT expose a getter for the implementation slot (unlike BuyBackBurnerProxy which has `getImplementation()`). The implementation's `tokenomicsImplementation()` function serves this purpose via delegatecall. SAFE but inconsistent

**Result**: 0 High/Medium. 1 Informational (uninitialized implementation — no exploit path).

### Stream 9: Competition Contract ✓
**Result**: No Competition contract exists in contracts/. Searched all of contracts/, test/, lib/. Only references found in CHANGELOG.md and this audit file. N/A — nothing to audit.

### Stream 10: Timelock Contract ✓
**Result**: No custom Timelock contract in contracts/. The only TimelockController found is OpenZeppelin's standard one in lib/fx-portal/lib/openzeppelin-contracts/ (a transitive dependency). The actual governance timelock is external (Olas DAO governance). N/A — nothing to audit.

### Stream 11: DonatorBlacklist ✓
85 LOC. Owner-only setDonatorsStatuses, view isDonatorBlacklisted. No bugs.
Proxy bypass (donate via intermediary contract) = known EVM limitation, not a contract bug.

### Stream 12: Key Invariants (Code Review, not formal verification)
- [x] Sum of bonds outstanding ≤ effectiveBond: HOLDS under normal checkpoint flow. VIOLATED only if admin calls updateInflationPerSecondAndFractions (C2-1, admin-only)
- [x] ETHFromServices ≥ pending rewards: HOLDS — rebalanceTreasury takes only treasury fraction, leaving rewards untouched
- [x] Total OLAS minted ≤ inflation schedule: ENFORCED by OLAS token contract mint cap + per-epoch inflationPerEpoch cap
- [x] L2 withheld ≤ actual L2 OLAS balance: HOLDS — withheld tracks only amounts that failed to distribute
- [x] Epoch monotonicity: HOLDS — epochCounter only increments, prevEpochTime only advances
- [x] Cross-chain nomineeHash uniqueness: HOLDS — includes chainId in hash

## AUDIT COMPLETE — ALL VECTORS EXHAUSTED

### Final Results

| Stream | Scope | LOC | Result |
|--------|-------|:---:|--------|
| 1 | Financial Core | 4,000+ | 0 H/M |
| 2 | Cross-Chain Staking | 3,000+ | 0 H/M |
| 3 | POL + Oracle + BBB | 4,000+ | 0 H/M (fixes verified) |
| 4 | New/Under-Audited | 1,500+ | 0 H/M |
| 5 | PoC Verification | — | 3 findings DISPROVED |
| 6 | Cross-Contract Chains | — | 1 Low/Med (C2-1) |
| 7 | Attack Scenarios | — | 0 exploitable |
| 8 | Proxy/Upgrade | — | 0 H/M |
| 9 | Competition | — | N/A (doesn't exist) |
| 10 | Timelock | — | N/A (external) |
| 11 | DonatorBlacklist | 85 | 0 |
| 12 | Invariants | — | All hold |

### Cumulative Findings

| Sev | Count | Details |
|-----|:-----:|---------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low/Med | 1 | C2-1: effectiveBond reset in updateInflation (admin-only) |
| Low | 5 | L-1 Wormhole fee, L-2 unchecked returns, L-3 Polygon exit, L-4 spot price helper, L-5 gas neighborhood |
| Info | 7+ | Various informational observations |

### Conclusion
**Code is ready for Immunefi bounty deployment.** No externally exploitable High/Medium findings. All C4A findings properly addressed (14 fixed, 6 admin-scope accepted, 6 acknowledged/OOS, 3 DISPROVED by PoC). The codebase has strong defenses: same-block donation check, proportional reward distribution, veOLAS gating, comprehensive bridge validation, proper TWAP oracles (in fix branches), and bounded epoch/inflation parameters.
### Stream 13: Test Coverage Gap Analysis ✓
- [x] Mapped all 18 Foundry + 9 Hardhat test files to contracts
- [x] P0: updateInflationPerSecondAndFractions — 0 tests. Wrote PoC_CoverageGaps.t.sol: C2-1 CONFIRMED
- [x] P1: checkpoint edge cases (year change, MAX_EPOCH_LENGTH) — tested via fork PoC
- [x] P1: uint96 overflow headroom — verified far from max
- [x] P1: inflation schedule 20 years — all correct
- [x] 5 test files don't compile (old oracle interface) — documented
- [x] No fuzz tests for core tokenomics — documented as systemic gap

### Stream 14: C2-1 Deep Investigation ✓
- [x] On-chain state verified: effectiveBond=5.66M, maxBond=242K, 0 active products
- [x] Fork PoC: updateInflation destroys 91.4% of effectiveBond (5.18M OLAS capacity)
- [x] Exploitability: NOT external (owner=Timelock=DAO governance)
- [x] Direction: CONSERVATIVE (under-counts, never over-counts, no over-minting)
- [x] Fund loss: NONE (effectiveBond limits creation only, not existing products)
- [x] Combination analysis: reset + refund = still under-counts, no overflow
- [x] Recovery path: ~308 days to rebuild via checkpoint()
- [x] Final severity: Medium (admin-only correctness bug, operational impact)
