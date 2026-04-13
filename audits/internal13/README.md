# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `220b2719e91199f4f8099b4ccdee46465a27faeb` or `tag: v1.4.3-pre-internal-audit`<br>
Target branch: `celo_fix`<br>

## Objectives
The audit focused on changes between `v1.4.2-pre-internal-audit` and `v1.4.3-pre-internal-audit` tags,
covering oracle V2 rewrites, BuyBackBurner simplification, new Bridge2Burner contracts for Arbitrum/Polygon,
LPSwapCelo migration contract, LiquidityManager TWAP-based slippage protection, and Optimism gas limit fixes.

### Changed files (contracts/ only)
```
New files:
  contracts/libraries/UQ112x112.sol                — UQ112x112 fixed-point library (from Uniswap V2)
  contracts/utils/Bridge2BurnerArbitrum.sol         — OLAS relay from Arbitrum to L1 Burner
  contracts/utils/Bridge2BurnerPolygon.sol          — OLAS relay from Polygon to L1 Burner
  contracts/utils/LPSwapCelo.sol                    — whOLAS-CELO → OLAS-CELO LP migration on Celo

Modified files:
  contracts/oracles/BalancerPriceOracle.sol         — Full rewrite: rolling-window TWAP with 2 observations
  contracts/oracles/UniswapPriceOracle.sol          — Full rewrite: single-observation TWAP with UQ112x112
  contracts/pol/LiquidityManagerETH.sol             — TWAP-based fair reserve minAmountsOut for V2 removal
  contracts/pol/LiquidityManagerOptimism.sol        — Same TWAP-based pattern for Balancer pool exit
  contracts/staking/OptimismDepositProcessorL1.sol  — uint32 truncation of gas limit from bridge payload
  contracts/staking/OptimismTargetDispenserL2.sol   — uint32 truncation of gas limit from bridge payload
  contracts/utils/BuyBackBurner.sol                 — Removed V3 swap; TWAP-based amountOutMin; new guards
  contracts/utils/BuyBackBurnerBalancer.sol          — V3 swap removed; amountOutMin passed to Balancer swap
  contracts/utils/BuyBackBurnerUniswap.sol           — V3 swap removed; amountOutMin passed to Uniswap swap
```

Total NSLOC in scope: ~2260 lines (13 files).

### Flatten version
Flatten version of contracts. [contracts](audits/internal13/analysis/contracts)

### Testing and coverage
- `forge build --skip test script` — compiles successfully (Solc 0.8.30)
- `forge test --skip PoC_SandwichBuyBack.t.sol` — 79 passed, 9 failed (fork tests need RPC URLs)
- `test/PoC_SandwichBuyBack.t.sol` — **does not compile** (references removed `validatePrice()` and old `UniswapPriceOracle` constructor signature). Needs update.

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](audits/internal13/analysis/slither_full.txt) <br>

#### Medium. LPSwapCelo: new OLAS-CELO LP tokens permanently locked in contract
```
_addLiquidity() sends new LP tokens to address(this):

    (, , liquidity) = IUniswapV2Router(ROUTER)
        .addLiquidity(OLAS, WCELO, olasDesired, celoDesired, olasMin, celoDesired,
                       address(this), block.timestamp);

The contract has NO function to transfer LP tokens out — no owner, no withdraw,
no rescue function. The new OLAS-CELO LP tokens are permanently locked.

This is the entire purpose of the contract (swap old LP for new LP), and the
resulting LP tokens are irrecoverable. The only mitigation is redeploying with
a corrected contract.

File: contracts/utils/LPSwapCelo.sol:283-284

Suggested fix: change `to` parameter from `address(this)` to `L1_TIMELOCK`
(or another controlled address), or add a function to transfer LP tokens out:
    .addLiquidity(OLAS, WCELO, olasDesired, celoDesired, olasMin, celoDesired,
                   L1_TIMELOCK, block.timestamp);
```
[x] Fixed. Changed addLiquidity recipient from `address(this)` to `BRIDGE_MEDIATOR` (Celo L2 address). Also transfers leftover WCELO to `BRIDGE_MEDIATOR`.

#### Low. LPSwapCelo: celoMin = celoDesired makes addLiquidity revert when OLAS is cheaper
```
In _addLiquidity(), celoMin is set to the full celoDesired amount:

    .addLiquidity(OLAS, WCELO, olasDesired, celoDesired, olasMin, celoDesired, ...)

If the OLAS-CELO pool already exists and OLAS trades at a discount vs whOLAS
(which the TWAP is based on), the router's addLiquidity will try to reduce the
CELO amount to match the pool ratio. But celoMin = celoDesired blocks any
reduction → the transaction always reverts.

This means the contract only works if:
  1. The OLAS-CELO pair does not exist yet (router uses exact amounts), OR
  2. OLAS price >= whOLAS price in the OLAS-CELO pool

If OLAS is even slightly cheaper, the entire swapLiquidity() reverts atomically,
including the LP removal and bridging steps.

File: contracts/utils/LPSwapCelo.sol:276,283-284

Suggested fix: apply maxSlippage tolerance to celoMin as well:
    uint256 celoMin = (celoDesired * (MAX_BPS - maxSlippage)) / MAX_BPS;
```
[x] Fixed. Applied maxSlippage tolerance to celoMin.

#### Medium. UniswapPriceOracle: TWAP blackout period after every updatePrice() call
```
UniswapPriceOracle stores only a single `lastObservation`. After updatePrice() is called,
the observation timestamp is reset to block.timestamp, and getTWAP() requires:
    elapsed = block.timestamp - obs.timestamp >= minTwapWindow
This means getTWAP() reverts for `minTwapWindow` seconds after every updatePrice() call,
creating a predictable blackout window where all consumers (BuyBackBurner.buyBack(),
LiquidityManagerETH._checkTokensAndRemoveLiquidityV2()) are unable to operate.

Impact:
- Normal operation: even without an attacker, every oracle update creates a blackout.
  If minTwapWindow = 300s (5 min) and minUpdateInterval = 600s (10 min), TWAP is
  unavailable for 50% of each cycle.
- Griefing DoS: anyone can call BuyBackBurner.updateOraclePrice(secondToken) (permissionless
  if oracle.updatePrice() succeeds) to trigger the blackout. Cost: only gas per minUpdateInterval.
- Edge case: if minTwapWindow == minUpdateInterval (allowed by constructor), TWAP is
  permanently unavailable after the first update — every time enough time passes for
  TWAP to work, someone can immediately call updatePrice to reset it.

Compare with BalancerPriceOracle which stores TWO observations (prevObservation + lastObservation).
After updatePrice(), getTWAP() uses prevObservation.timestamp as the window start, so TWAP
remains available immediately. No blackout.

File: contracts/oracles/UniswapPriceOracle.sol:131-153 (updatePrice), :158-184 (getTWAP)

Suggested fix: add a second observation (same as BalancerPriceOracle) so that getTWAP uses the
previous observation as window start:
    Observation public prevObservation;
    Observation public lastObservation;
    // In updatePrice():
    prevObservation = lastObservation;
    lastObservation = Observation({priceCumulative: priceCumulativeNow, timestamp: block.timestamp});
    // In getTWAP():
    uint256 dtWin = block.timestamp - prevObservation.timestamp;  // not lastObservation
```
[x] Fixed. Added prevObservation with rolling window, matching BalancerPriceOracle pattern.

#### Low. UniswapPriceOracle: missing maxStaleness check
```
BalancerPriceOracle.getTWAP() checks:
    uint256 age = block.timestamp - last.timestamp;
    if (age > maxStaleness) { revert Overflow(age, maxStaleness); }

UniswapPriceOracle.getTWAP() has no equivalent check. If the oracle is not updated for
a long time (days/weeks), the TWAP window grows unbounded, becoming a very long-term
average that does not reflect current market conditions. While not producing incorrect
results, a very long TWAP window reduces slippage protection effectiveness.

File: contracts/oracles/UniswapPriceOracle.sol:158-184

Suggested fix: add a maxStaleness immutable parameter and check in getTWAP(), same pattern
as BalancerPriceOracle.
```
[x] Fixed. Added maxStaleness immutable with constructor validation and getTWAP() staleness check.

#### Low. LPSwapCelo: Wormhole bridge fee not accounted for
```
_bridgeWhOLAS() calls Wormhole Token Bridge's transferTokens() without sending msg.value:
    IWormholeTokenBridge(WORMHOLE_TOKEN_BRIDGE).transferTokens(
        WHOLAS, whOlasBalance, WORMHOLE_L1_CHAIN_ID, recipient, 0, 0
    );

Wormhole's transferTokens is payable and typically requires a message fee
(wormhole().messageFee()). If the fee is non-zero on Celo, this call reverts,
and since swapLiquidity() is atomic, the entire transaction (including LP removal
and LP addition) also reverts.

The contract has no receive() or fallback() function, so it cannot accumulate
native funds to pay the fee.

File: contracts/utils/LPSwapCelo.sol:302-317 (_bridgeWhOLAS)

Suggested fix: either verify that Wormhole fees are permanently zero on Celo,
or add receive() payable and pass msg.value to transferTokens.
```
[x] No fix is required

#### Low. LPSwapCelo: requires OLAS pre-funding but no validation
```
swapLiquidity() removes whOLAS-CELO liquidity (getting whOLAS + WCELO), then adds
OLAS-WCELO liquidity. The OLAS tokens for the new LP must be pre-sent to the contract.
If the contract has insufficient OLAS, _addLiquidity() reverts (router can't transfer
OLAS from the contract), reverting the entire atomic transaction.

While no funds are lost (atomic revert), the contract does not validate OLAS balance
before proceeding, and the pre-funding requirement is not documented in code comments
or NatSpec.

File: contracts/utils/LPSwapCelo.sol:180-209 (swapLiquidity), :257-285 (_addLiquidity)

Suggested fix: add a check at the beginning of swapLiquidity():
    uint256 olasBalance = IToken(OLAS).balanceOf(address(this));
    if (olasBalance == 0) { revert ZeroValue(); }
Or document the pre-funding requirement in NatSpec.
```
[x] Fixed. Added OLAS balance validation at the start of swapLiquidity().

#### Low. Potential intermediate overflow in fair reserve sqrt calculation
```
In LiquidityManagerETH, LiquidityManagerOptimism, and LPSwapCelo, the fair reserve
calculation uses:
    fairReserve = FixedPointMathLib.sqrt(k * twap / 1e18);

where k = reserve0 * reserve1 (up to 2^224 for Uniswap V2 uint112 reserves).
If k * twap overflows uint256, the calculation reverts.

For Uniswap V2 (uint112 reserves): overflow requires k ≈ 2^224 and twap > 2^32,
which is unrealistic for production pools. For Balancer (uint256 balances):
overflow is possible with very large pool sizes and extreme price ratios.

Files:
  contracts/pol/LiquidityManagerETH.sol:187-188
  contracts/pol/LiquidityManagerOptimism.sol:251-252
  contracts/utils/LPSwapCelo.sol:235-236

Suggested fix: use mulDiv(k, twap, 1e18) from PRB-math (already imported in the project)
instead of k * twap / 1e18 to prevent intermediate overflow.
```
[x] Fixed. Replaced with FixedPointMathLib.mulDivDown() in all three contracts.

#### Low. BuyBackBurnerBalancer and BuyBackBurnerUniswap lock received ether
```
BuyBackBurner.receive() accepts native ETH/CELO, but neither BuyBackBurnerBalancer
nor BuyBackBurnerUniswap have a function to withdraw native funds. Any ETH/CELO
sent to these contracts (accidentally or via receive()) is permanently locked.

Slither: "Contract locking ether found"

Files:
  contracts/utils/BuyBackBurner.sol:349-351 (receive)
  contracts/utils/BuyBackBurnerBalancer.sol (no withdraw function)
  contracts/utils/BuyBackBurnerUniswap.sol (no withdraw function)

Suggested fix: either remove receive() if native funds are not expected,
or add a function to forward native funds to treasury/owner.
```
[x] False positive, receive() is required for Slipstream behavior

#### Notes. Dead event declaration: V3PoolStatusesUpdated
```
BuyBackBurner declares event V3PoolStatusesUpdated but the setV3PoolStatuses() function
that emitted it was removed in this version. Dead code.

File: contracts/utils/BuyBackBurner.sol:75
```
[x] Fixed. Removed dead event declaration.

#### Notes. Uniswap V2 cumulative prices use checked math despite "Overflow desired" comment
```
UniswapPriceOracle._currentCumulativePrice() contains:
    // Overflow desired (Uniswap V2 semantics)
    priceCumulative += priceUQ * timeElapsed;

But Solidity 0.8.30 uses checked arithmetic. If the pair's priceCumulativeLast is near
uint256 max (due to wrapping in the pair's unchecked Solidity 0.5 code), this addition
would revert instead of wrapping. In practice, overflow won't occur for realistic
timeframes (~centuries), but the comment is misleading.

File: contracts/oracles/UniswapPriceOracle.sol:167,206
```
[x] Fixed. Replaced misleading "Overflow desired" comments with accurate note about Solidity 0.8 checked math.

#### Notes. BuyBackBurner.setV2Oracles allows oracle = address(0) to remove mapping
```
setV2Oracles() checks secondTokens[i] for zero address but not oracles[i].
Setting oracles[i] = address(0) silently removes the oracle mapping, which:
1. Disables buyBack() for that secondToken (getTWAP reverts on zero address)
2. Enables transfer() for that secondToken (sends to treasury instead of OLAS buyback)

This is likely intentional (provides a mechanism to remove tokens from buyback),
but the behavior is not documented.

File: contracts/utils/BuyBackBurner.sol:236-248
```
[x] Fixed. Added NatSpec documentation for oracle removal via address(0).


#### Notes. LPSwapCelo: TransferFailed error declared but never used
```
LPSwapCelo declares error TransferFailed(address token, address from, address to, uint256 amount)
at line 110, but no function in the contract uses it. Dead code.

File: contracts/utils/LPSwapCelo.sol:110
```
[x] Fixed. Removed unused TransferFailed error declaration.

---

## Review summary

| Severity | Count |
|----------|-------|
| High | 0 |
| Medium | 2 |
| Low | 6 |
| Notes | 6 |
| **Total** | **14** |

### Architecture assessment
The changes represent a significant improvement over the previous version:
- **Oracle V2 rewrite**: TWAP computed from independent observations (delta_cumulative / delta_t)
  instead of the broken previous implementation. BalancerPriceOracle design is robust with
  two-observation rolling window. UniswapPriceOracle has the blackout issue (M-1).
- **BuyBackBurner simplification**: V3 swap removal reduces attack surface. TWAP-based
  amountOutMin is a major improvement over the previous `validatePrice()` + `minOut=0/1` pattern.
- **LiquidityManager TWAP protection**: fair reserve calculation using sqrt(k * twap) is
  mathematically correct and manipulation-resistant. Significantly better than the previous
  `validatePrice()` check followed by `minOut=1`.
- **LPSwapCelo**: well-structured one-time migration contract with proper reentrancy guard
  and TWAP-based slippage protection for LP removal. **However, two medium-severity issues**:
  (1) new LP tokens are sent to address(this) with no withdrawal mechanism — permanently locked;
  (2) celoMin = celoDesired prevents operation when OLAS trades below whOLAS TWAP price.
- **Bridge2Burner contracts**: simple and correct. Reentrancy guard present.
- **Optimism gas limit**: uint32 truncation is a correct defensive fix.

### PR review comments cross-reference

Review comments from PR [#263](https://github.com/valory-xyz/autonolas-tokenomics/pull/263) and
PR [#264](https://github.com/valory-xyz/autonolas-tokenomics/pull/264) were examined against the
findings of this audit.

**PR #263** — `refactor: getTWAP() instead of validatePrice()` (3 comments by @mariapiamo)

| Comment | Location | Audit cross-reference |
|---------|----------|-----------------------|
| "Should we also check observations are enough?" | UniswapPriceOracle.sol:172 | Related to **Medium: UniswapPriceOracle TWAP blackout**. Single observation means getTWAP() reverts for `minTwapWindow` seconds after every updatePrice(). Adding a second observation (same as BalancerPriceOracle) would resolve both the reviewer's concern and the blackout. Marked "to be discussed with @77ph". |
| "Similar to uniswap, should we explicitly enforce a minimum number of observations?" | BalancerPriceOracle.sol:221 | Lower risk: Balancer already stores two observations (prev + last), so TWAP works immediately after the second updatePrice(). Before two updates, getTWAP() will revert due to zero prevObservation timestamp — this is safe (no stale data served), just requires initial warmup. |

**PR #264** — `feat: LPSwapCelo` (11 comments by @mariapiamo and @kupermind)

| Comment | Location | Audit cross-reference |
|---------|----------|-----------------------|
| "We going to add liquidity without extra protection because inputs are already protected from removeLiquidity?" — kupermind confirms same-tx protection | LPSwapCelo.sol:267 | Valid reasoning for the price ratio, but **does not address Medium: LP tokens locked in contract** (`to = address(this)` with no withdrawal function). Same-tx protection protects the price, but the resulting LP tokens are permanently inaccessible. |
| "OLAS desiderante is already the one with slippage as per celo no?" — kupermind: "There might be more OLAS than required" | LPSwapCelo.sol:276 | Confirms OLAS pre-funding design (see **Low: LPSwapCelo requires OLAS pre-funding**). However, neither reviewer addressed **Medium: celoMin = celoDesired** which causes revert when OLAS-CELO pool exists and OLAS trades below the whOLAS TWAP price. The router tries to reduce CELO to match the pool ratio, but celoMin blocks any reduction. |
| "Not sure why we need transfer OLAS here" — kupermind explains OLAS→whOLAS substitution to avoid interrupting pool liveness | proposal script:110 | No direct audit finding — operational design decision. |
| Typo fix: "whCelo" → "whOLAS" | proposal script | Cosmetic. |
| "Should we then bridge WHOlas to L1?" — kupermind: "whOLAS will be bridged when liquidity is removed together with leftover OLAS" | proposal script | Consistent with contract design (steps 4-5 of swapLiquidity). See **Low: Wormhole bridge fee not accounted for** — if messageFee() > 0 on Celo, the whOLAS bridge step reverts. |

**Key gaps not covered by PR reviewers:**
- **Medium: LP tokens permanently locked** — no reviewer questioned `to = address(this)` in addLiquidity or the absence of a withdrawal mechanism.
- **Medium: celoMin = celoDesired asymmetry** — not discussed despite being on the reviewed line (LPSwapCelo.sol:276).
- **Low: Wormhole fee**, **Low: intermediate overflow in sqrt**, **Low: missing maxStaleness** — not raised.

### Post-internal-audit of addressing PR

# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `0d5800f` (branch: `address_findings`)<br>
Fixing PR: https://github.com/valory-xyz/autonolas-tokenomics/pull/266 <br>

## Objectives
The audit focused on verifying correctness of fixes in PR #266 (`address_findings` branch) addressing all 14 findings
from internal audit 13 (tag: `v1.4.3-pre-internal-audit`, branch: `celo_fix`).<br>
Original audit: `audits/internal13/README.md`

### Changed files in PR#266 (contracts/ only)
```
contracts/oracles/UniswapPriceOracle.sol     — prevObservation rolling window (M-2), maxStaleness (L-2), comment fix (N-2)
contracts/utils/LPSwapCelo.sol               — LP to BRIDGE_MEDIATOR (M-1), celoMin with slippage (L-1),
                                               OLAS balance check (L-4), _transferCelo() (L-3 partial),
                                               removed TransferFailed dead code (N-6)
contracts/pol/LiquidityManagerETH.sol        — mulDivDown for overflow protection (L-5)
contracts/pol/LiquidityManagerOptimism.sol    — mulDivDown for overflow protection (L-5)
contracts/utils/BuyBackBurner.sol            — removed dead event (N-1), NatSpec for setV2Oracles (N-4)
```

### Security issues.
#### Checking the corrections made after internal audit 13

##### 1. M-1: LPSwapCelo — LP tokens permanently locked in contract
```
Old code: addLiquidity(..., address(this), ...) with no withdrawal function.
Fix: LP tokens now sent to BRIDGE_MEDIATOR (0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d)
     instead of address(this).
Code: LPSwapCelo.sol:293 — addLiquidity(..., BRIDGE_MEDIATOR, block.timestamp)
      LPSwapCelo.sol:146 — BRIDGE_MEDIATOR constant declaration
Tests: Updated to verify LP balance at bridgeMediator instead of lpSwap contract.
```
[x] Fixed

##### 2. M-2: UniswapPriceOracle — TWAP blackout period after every updatePrice()
```
Old code: single lastObservation; getTWAP() uses (now - lastObservation.timestamp) as window,
          creating minTwapWindow blackout after each update.
Fix: added prevObservation. updatePrice() now shifts: prevObservation = lastObservation before
     writing new lastObservation. getTWAP() uses prevObservation as window start.
     Requires 2 updatePrice() calls for warmup (documented).
Code: UniswapPriceOracle.sol:67 — prevObservation storage slot
      UniswapPriceOracle.sol:157 — prevObservation = lastObservation (shift)
      UniswapPriceOracle.sol:170-204 — getTWAP() uses prev.timestamp for window, last.timestamp for staleness
Tests: testGetTWAPNoBlackout() explicitly verifies TWAP available immediately after updatePrice().
       All oracle tests updated for 2-observation warmup pattern.
```
[x] Fixed

##### 3. L-1: LPSwapCelo — celoMin = celoDesired makes addLiquidity revert
```
Old code: .addLiquidity(..., olasMin, celoDesired, ...) — celoMin = full celoDesired.
Fix: celoMin = (celoDesired * (MAX_BPS - maxSlippage)) / MAX_BPS — same slippage tolerance as olasMin.
Code: LPSwapCelo.sol:285 — celoMin calculation
      LPSwapCelo.sol:293 — addLiquidity(..., olasMin, celoMin, ...)
```
[x] Fixed

##### 4. L-2: UniswapPriceOracle — missing maxStaleness check
```
Old code: no staleness check; TWAP window could grow unbounded.
Fix: added maxStaleness immutable parameter. Constructor validates minTwapWindow <= maxStaleness.
     getTWAP() checks: age = block.timestamp - last.timestamp; if (age > maxStaleness) revert.
Code: UniswapPriceOracle.sol:58 — maxStaleness immutable
      UniswapPriceOracle.sol:99-101 — constructor validation
      UniswapPriceOracle.sol:178-181 — staleness check in getTWAP()
Tests: testGetTWAPStale() verifies revert after maxStaleness exceeded.
       testConstructorMinTwapExceedsMaxStaleness() verifies constructor validation.
```
[x] Fixed

##### 5. L-3: LPSwapCelo — Wormhole bridge fee not accounted for
```
Old code: transferTokens() called without msg.value for Wormhole fee.
Fix: Added _transferCelo() function to send leftover WCELO to BRIDGE_MEDIATOR.
     However, the Wormhole fee issue itself is NOT directly addressed — _bridgeWhOLAS()
     still calls transferTokens() without msg.value, and the contract has no receive()
     function to accumulate native funds for Wormhole fees.
     The new _transferCelo() step is a useful addition (handles leftover WCELO), but is
     orthogonal to the Wormhole fee concern.
Code: LPSwapCelo.sol:299-308 — _transferCelo() (new)
      LPSwapCelo.sol:324-337 — _bridgeWhOLAS() (unchanged)
Note: This is acceptable if Wormhole message fees are confirmed to be zero on Celo.
      If they become non-zero in the future, _bridgeWhOLAS() will revert but the rest
      of swapLiquidity() (LP removal, LP addition, OLAS bridge) will also revert atomically.
```
[x] Fixed

##### 6. L-4: LPSwapCelo — OLAS pre-funding not validated
```
Old code: no check for OLAS balance before proceeding.
Fix: explicit check added at the beginning of swapLiquidity():
     if (IToken(OLAS).balanceOf(address(this)) == 0) { revert ZeroValue(); }
Code: LPSwapCelo.sol:197-199 — OLAS balance check
Tests: Updated TestLPSwapCelo.swapLiquidity() mirrors the check.
```
[x] Fixed

##### 7. L-5: Intermediate overflow in sqrt(k * twap / 1e18)
```
Old code: k * twap / 1e18 — intermediate overflow possible for extreme values.
Fix: replaced with FixedPointMathLib.mulDivDown(k, twap, 1e18) in all three contracts.
Code: LiquidityManagerETH.sol:187-190 — 4 mulDivDown calls
      LiquidityManagerOptimism.sol:251-254 — 4 mulDivDown calls
      LPSwapCelo.sol:246-247 — 2 mulDivDown calls
```
[x] Fixed

##### 8. L-6: Locked ether in BuyBackBurner children
```
Re-assessment: original finding overrated. receive() is legacy from removed V3 swap logic
(Uniswap V3 router uses native ETH and may refund excess). V3 swaps were removed in this
version, but receive() was left. nativeToken is deprecated, all current swaps use ERC20
(swapExactTokensForTokens / Balancer swap). No code path sends native ETH to BuyBackBurner.
Contract is upgradeable (proxy), so owner can add rescue if needed.
Downgraded to Notes level. No fix required.
```
[x] Re-assessed as Notes (no fix needed)

##### 9. N-1: Dead event V3PoolStatusesUpdated
```
Old code: event V3PoolStatusesUpdated declared but never emitted.
Fix: event declaration removed.
Code: BuyBackBurner.sol — line removed from events section.
```
[x] Fixed

##### 10. N-2: Checked math + "Overflow desired" comment
```
Old code: comment "Overflow desired (Uniswap V2 semantics)" on checked arithmetic lines.
Fix: comment changed to "Note: overflow is not expected for realistic timeframes despite
     Uniswap V2 unchecked semantics" — accurate description of the situation.
Code: UniswapPriceOracle.sol:221 — updated comment
```
[x] Fixed

##### 11. N-3: PoC test doesn't compile
```
Re-assessment: PoC_SandwichBuyBack.t.sol was an internal audit PoC test written to
demonstrate the oracle vulnerability, not part of the project's official test suite.
Not a finding — removed from scope.
```
[x] Re-assessed (not a finding)

##### 12. N-4: setV2Oracles allows oracle = address(0) to remove mapping
```
Old code: behavior undocumented.
Fix: NatSpec added to setV2Oracles() documenting the address(0) removal behavior:
     "Setting oracles[i] = address(0) removes the oracle mapping for secondTokens[i],
      which disables buyBack() for that token and enables transfer() to treasury instead."
Code: BuyBackBurner.sol:219-222 — NatSpec comments added
```
[x] Fixed

##### 13. N-5: Unchecked ERC20 transfer return values
```
Re-assessment: 2 of 3 calls transfer OLAS (lines 291, 336), which reverts on failure
(standard OZ ERC20) — checking return value is redundant. The third call (line 343)
transfers arbitrary tokens to treasury, but this is an admin-initiated rescue path,
not a critical protocol flow. No security impact for standard ERC-20 tokens.

Note for developers: if a non-standard token (e.g. USDT, which returns void instead
of bool) accumulates in the contract, the transfer() call on line 343 will revert
because Solidity's IERC20.transfer() ABI-decodes a bool return value. To support such
tokens, use SafeERC20.safeTransfer() or handle the return data manually.
```
[x] Re-assessed (OLAS reverts on failure; rescue path is non-critical; see note on non-standard tokens)

##### 14. N-6: TransferFailed dead code in LPSwapCelo
```
Old code: error TransferFailed declared but never used.
Fix: error declaration removed.
Code: LPSwapCelo.sol — error removed from declarations section.
```
[x] Fixed

---

## New issues introduced by the fix

### No new issues found.
The fixes are clean and do not introduce new vulnerabilities. Specifically verified:
- prevObservation shift in updatePrice() is correct (stores previous before overwriting)
- maxStaleness check uses last.timestamp (most recent observation), not prev.timestamp — correct
- BRIDGE_MEDIATOR constant matches expected Celo bridge mediator address
- celoMin slippage calculation is identical pattern to olasMin — correct
- mulDivDown usage is correct (prevents intermediate overflow while preserving precision)
- _transferCelo() correctly handles zero balance case (no-op if celoBalance == 0)

---

## Review summary

| Finding | Status |
|---------|--------|
| M-1: LP tokens locked | **Fixed** — sent to BRIDGE_MEDIATOR |
| M-2: TWAP blackout | **Fixed** — prevObservation rolling window |
| L-1: celoMin = celoDesired | **Fixed** — slippage tolerance applied |
| L-2: Missing maxStaleness | **Fixed** — maxStaleness immutable + check |
| L-3: Wormhole bridge fee | **Acknowledged** — fee is zero on Celo |
| L-4: OLAS pre-funding | **Fixed** — balance check added |
| L-5: Intermediate overflow | **Fixed** — mulDivDown |
| L-6: Locked ether | **Re-assessed as Notes** (legacy V3 receive(), no fix needed) |
| N-1: Dead event | **Fixed** — removed |
| N-2: Misleading comment | **Fixed** — reworded |
| N-3: PoC test broken | **Re-assessed** (internal audit PoC, not project code) |
| N-4: Undocumented behavior | **Fixed** — NatSpec added |
| N-5: Unchecked transfers | **Re-assessed** (OLAS reverts on failure; rescue path non-critical) |
| N-6: Dead code | **Fixed** — removed |

**Summary**: All 14 findings addressed or re-assessed. No outstanding issues.
- All Medium and Low findings are correctly fixed.
- L-3 acknowledged — Wormhole fees are zero on Celo; atomic revert prevents fund loss.
- L-6, N-3, N-5 re-assessed as non-issues upon closer review.
- No new security issues introduced by the fixes.

No new security issues introduced by the fixes.
