# Internal audit of autonolas-tokenomics (v2.20 methodology)
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `6504f8b` (main) + branches `fix_oracle_v2`, `fix_oracle_v2_update2`, `address_findings`<br>
**Assumption**: All fix branches treated as merged into main.<br>

## Objectives
Full bounty-audit emulation before Immunefi deployment. Our risk = bounty payouts to external auditors for issues found after us.

Methodology: Playbook v2.20 (620+ checklist items across 12 domains), 14 audit streams, fork PoC verification for all Medium+ findings.

### Scope
All production contracts in `contracts/` — 10,800 LOC, ~30 Solidity files.

### Audit streams

| # | Stream | LOC | Result |
|---|--------|:---:|--------|
| 1 | Financial Core (Tokenomics, Dispenser, Treasury, Depository) | 4,000+ | 0 H/M |
| 2 | Cross-Chain Staking (6 bridge implementations) | 3,000+ | 0 H/M |
| 3 | POL + Oracle + BuyBackBurner (fix branch verification) | 4,000+ | 0 H/M, C4A fixes verified |
| 4 | New/Under-Audited (LPSwapCelo, Bridge2Burner, Scanner, BondCalc) | 1,500+ | 0 H/M |
| 5 | Fork PoC verification (ETH mainnet) | — | 3 theoretical findings DISPROVED |
| 6 | Cross-contract interaction chains (4 chains) | — | 1 Medium (C2-1, admin-only, fork PoC confirmed) |
| 7 | Specific attack scenarios (6 scenarios) | — | All blocked |
| 8 | Proxy upgrade path + storage layout (3 proxies) | — | 0 H/M |
| 9 | Competition contract | — | N/A (doesn't exist) |
| 10 | Timelock contract | — | N/A (external) |
| 11 | DonatorBlacklist | 85 | 0 |
| 12 | Key invariants (code review) | — | All hold |
| 13 | Test coverage gap analysis + targeted PoC | — | C2-1 confirmed |
| 14 | C2-1 deep investigation (on-chain state, combinations) | — | Medium, admin-only, conservative direction |

## C4A findings fix verification

### Oracle V2: 6/6 FIXED ✓
- UniswapPriceOracle TWAP=spot → proper two-point TWAP with stored observations ✓
- BalancerPriceOracle state mutation on reject → commit-on-success pattern ✓
- Balancer vault balance manipulation → rolling TWAP ✓
- Balancer permanent freeze on large movements → rolling window adapts ✓
- Uniswap sync() griefing → rate-limited by minUpdateInterval ✓
- Inconsistent encoding → UQ112x112 consistent ✓

### BuyBackBurner: 7/7 permissionless-path FIXED + 1 design-level NOT FIXED
Fixed (permissionless buyBack/transfer attack surface):
- Slippage protection → TWAP-based amountOutMin ✓
- Unauthorized transfer → token blacklist check ✓
- V3 ABI mismatch → V3 swap path removed entirely (fix by exclusion) ✓
- BPS/% mismatch → MAX_BPS end-to-end ✓
- Edge case slippage → old post-swap comparison removed ✓
- Forced ETH revert → receive() added ✓
- Transfer DoS → oracle token check ✓

NOT FIXED (design-level, Low):
- Uniform maxSlippage for all token pairs (C4A finding) → still global, not per-token

### LiquidityManager: 3/3 V2 fixed + 5/5 V3 addressed by scope exclusion = 8/8

V2 findings (permissionless V2 liquidity removal in ETH + Optimism) — ALL FIXED:
- amountMin=1 → TWAP-based fair reserve minAmountsOut ✓
- validatePrice(maxSlippage/100) → getTWAP() ✓ (removes BPS/% mismatch)
- SlippageLimitBreached error → removed (now enforced by router via minAmountsOut) ✓

V3 findings (LiquidityManagerCore.sol = ZERO changes) — ADDRESSED BY EXCLUSION:
- TWAP compares to itself in checkPoolAndGetCenterPrice() → V3 admin-only
- Observation index for TWAP history → V3 admin-only
- changeRanges price manipulation → V3 admin-only
- block.timestamp deadline in V3 operations → V3 admin-only
- Incorrect liquidity optimization → V3 admin-only

Developer strategy: V3 LP management is owner-only (convertToV3, changeRanges,
collectFees, decreaseLiquidity, increaseLiquidity all gated by `msg.sender == owner`).
The permissionless attack surface (BuyBackBurner) had V3 swap path entirely removed.
V3 findings are in admin-trust scope — not externally exploitable.

### LPSwapCelo: internal audit 13 findings FIXED ✓
- LP tokens locked in contract → fixed (sent to BRIDGE_MEDIATOR) ✓
- celoMin = celoDesired → fixed (maxSlippage applied) ✓
- Wormhole bridge fee → fixed (swapLiquidity payable, msg.value forwarded) ✓

### Staking base contracts (#21-25): OUT OF SCOPE
StakingBase.sol (cross-service reentrancy, slashing, reward timing) is not in autonolas-tokenomics.
These C4A findings belong to autonolas-registries repo and are not tracked here.

### Others
- #28 Double mint cap year≥11: **DISPROVED by fork PoC** — math is correct on deployed contract
- #29 calculateStakingIncentives griefing: **DISPROVED by fork PoC** — state not mutated in normal conditions
- #30 effectiveBond reset in updateInflationPerSecondAndFractions: **CONFIRMED by fork PoC** — same as our C2-1 finding. See Medium section below.

## Fork PoC results

| Finding | Method | Result |
|---------|--------|--------|
| Double-applied mint cap year≥11 | `cast call` on deployed Tokenomics proxy | **DISPROVED**: `getInflationForYear(10)` returns exactly 2% of year 10 cap |
| Wormhole DoS transferAmount==0 | `call transferTokensWithPayload(0)` on deployed Wormhole Token Bridge | **DISPROVED**: bridge accepts 0 amount gracefully |
| calculateStakingIncentives griefing | Call from attacker address with real nominee (Base chain) | **DISPROVED**: function returns data but `mapLastClaimedStakingEpochs` NOT mutated |
| effectiveBond reset (C2-1) | Call `updateInflationPerSecondAndFractions` as owner on fork | **CONFIRMED**: 5.18M OLAS (91%) bond capacity destroyed |

## Security issues

### Medium. effectiveBond reset in updateInflationPerSecondAndFractions (admin-only, CONFIRMED by fork PoC)
```
In updateInflationPerSecondAndFractions(), effectiveBond is reset to just curMaxBond:
  effectiveBond = uint96(curMaxBond);                    // line 1381

Compare with checkpoint() which ADDS to accumulated effectiveBond:
  curMaxBond += effectiveBond;
  effectiveBond = uint96(curMaxBond);                    // lines 1278-1280

If called when there are open bond products with reserved supply, the global
effectiveBond becomes less than the sum of outstanding product supplies.
This violates the invariant: sum(product.supply) <= effectiveBond.

File: contracts/Tokenomics.sol:1381 vs 1278-1280

Fork PoC result (test/PoC_CoverageGaps.t.sol::test_P0_updateInflation_fractionSum_exactly100):
  effectiveBond before:  5,665,044,384,680,745,809,993,124 (5.66M OLAS)
  effectiveBond after:     484,438,797,260,273,972,188,800 (484K OLAS)
  effectiveBond LOST:    5,180,605,587,420,471,837,804,324 (5.18M OLAS = 91% destroyed)

Exploitability analysis:
- External exploit: NOT POSSIBLE (owner-only, owner = Timelock = DAO governance)
- Fund loss: NONE (effectiveBond only limits NEW bond product creation, no OLAS stolen/burned)
- Direction: CONSERVATIVE (under-counts capacity, never over-counts)
- Recovery: effectiveBond rebuilds at ~242K OLAS per epoch via checkpoint()
- Time to recover: ~22 epochs (~308 days) to reach previous 5.66M

Current on-chain state:
- effectiveBond = 5,665,044 OLAS (accumulated over 37 epochs)
- maxBond = 242,219 OLAS (current epoch contribution)
- Accumulated leftover = 5,422,825 OLAS (91.4% of effectiveBond)
- Active bond products = 0 (no reserved supply)

Combination analysis (effectiveBond reset + bond program refund):
- Reset only UNDER-counts, never OVER-counts
- Refunding closed programs after reset: effectiveBond < correct value
- Protocol becomes MORE conservative, NOT less — fewer bonds possible, NOT more OLAS

Immunefi assessment: UNLIKELY bounty-eligible (admin-only, no fund loss).
Typical Immunefi exclusion: "issues requiring access to privileged addresses."

Suggested fix: use the same additive pattern as checkpoint():
  effectiveBond = uint96(curMaxBond + effectiveBond);
Or: document that effectiveBond reset is an intended side effect of this function.
Or: require all bond products to be closed before calling.
```
[x] No fix needed. The function is owner-only (Timelock = DAO governance). The DAO ensures all bonding products are closed before calling updateInflationPerSecondAndFractions(), so no outstanding product supply can exceed the reset effectiveBond. The reset direction is conservative (under-counts, never over-counts). Natspec to be updated to document this precondition.

### Low. BuyBackBurner: uniform maxSlippage for all token pairs (C4A finding, NOT FIXED)
```
C4A finding: "Uniform maxSlippage variable causes slippage misalignment across pools."
maxSlippage is a single global uint256 (line 103), applied uniformly to all V2 swaps.
Different token pairs have different liquidity depths and volatility profiles.

File: contracts/utils/BuyBackBurner.sol:103,160

Suggested fix: mapping(address => uint256) mapMaxSlippage per secondToken.
```
[x] Fixed. Global maxSlippage deprecated (proxy legacy). Added mapping(address => uint256) mapTokenMaxSlippages with owner-only setMaxSlippages() setter. _buyOLAS() now reads per-token slippage. _initialize() in Uniswap/Balancer children no longer sets maxSlippage.

### Notes. Unchecked ERC20 transfer return values in BuyBackBurner and LPSwapCelo
```
Multiple approve()/transfer() calls without checking bool return value.
Known tokens (OLAS) revert on failure, but arbitrary secondTokens might not.

Files: BuyBackBurner.sol:290,336,342  LPSwapCelo.sol:256,289,290,303,314,328
```
[x] Fixed. transfer() calls now check return values and revert with TransferFailed error. approve() calls are not wrapped — if approve fails, the downstream router call (removeLiquidity/addLiquidity/withdrawTo/transferTokens) will revert anyway.

### Notes. Uninitialized implementation contracts (all 3 proxies)
```
Implementation contracts have empty constructors — initializeTokenomics/initialize
can be called directly. No exploit path exists (no selfdestruct, isolated storage,
no funds), but best practice is _disableInitializers().

Files: Tokenomics.sol, BuyBackBurner.sol, LiquidityManagerCore.sol
```
[x] No fix needed. Initialize functions already guard against re-initialization with `if (owner != address(0)) revert AlreadyInitialized()`. No exploit path exists.

### Notes. DonatorBlacklist bypassable via proxy contract
```
Blacklist checks msg.sender. Blacklisted address can deploy intermediary contract
to call depositServiceDonationsETH. Known EVM limitation, not a contract bug.
```
[x] No fix needed. Known EVM limitation — not a contract bug.

---

## Review summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 1 |
| Notes | 3 |
| **Total** | **5** |

### Test coverage gaps

| Priority | Contract:Function | Tests | Risk |
|:--------:|-------------------|:-----:|------|
| P0 | `Tokenomics.updateInflationPerSecondAndFractions()` | 0 | Modifies 4 core state vars, calls retain() in loop. Our C2-1 finding is here |
| P1 | `Tokenomics.checkpoint()` year-change + MAX_EPOCH_LENGTH paths | Happy only | 217 LOC core function, edge cases untested |
| P1 | `Dispenser.calculateStakingIncentives()` fuzz | 0 fuzz | Complex multi-epoch accumulation |
| P2 | `Bridge2BurnerGnosis` | 0 | Bridging = high risk, 52 LOC |
| P2 | `BuyBackBurner.changeImplementation()` | 0 | Upgrade path |
| P2 | `DefaultTargetDispenserL2.processDataMaintenance()` | 2 refs | Emergency function |
| P3 | uint96 cast overflow in Tokenomics | 0 edge | effectiveBond/maxBond boundary |

Systemic: no fuzz tests for core tokenomics, zero overflow edge-case tests, 5 test files don't compile (old oracle interface).

See `audits/internal-v2.20/test/PoC_CoverageGaps.t.sol` for targeted tests on P0-P1 gaps.

### Conclusion
**Code is ready for Immunefi bounty deployment with one caveat:** one Medium finding (effectiveBond reset, admin-only) confirmed by fork PoC. No *externally* exploitable High/Medium findings across 14 audit streams covering all 10,800 LOC.

Key defenses verified:
- `lastDonationBlockNumber` prevents flash loan + checkpoint in same block
- Proportional reward distribution + veOLAS gating prevent component spam attacks
- Cross-chain replay protection via `processedHashes[batchHash]` on both L1 and L2
- Oracle TWAP properly implemented (fix branches) with rate-limited updates
- BuyBackBurner V3 attack surface removed; V2 path uses TWAP-based amountOutMin
- Epoch bounds (MIN_EPOCH_LENGTH, MAX_EPOCH_LENGTH) prevent timing manipulation
- Proxy storage layout uses keccak256 slots (no collision with sequential state)

### Methodology
- Playbook: v2.20 (620+ checklist items)
- Fork PoC: Ethereum mainnet via QuikNode
- Addresses verified: Tokenomics 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300, Dispenser 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0, VoteWeighting 0x95418b46d5566D3d1ea62C12Aea91227E566c5c1, Wormhole Token Bridge 0x3ee18B2214AFF97000D974cf647E7C347E8fa585
- 49 registered nominees verified via VoteWeighting.getNominee()
- 3 theoretical Medium+ findings disproved by on-chain evidence
- 1 Medium finding confirmed by on-chain fork PoC
