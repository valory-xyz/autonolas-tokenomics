# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `v1.4.2-post-external-audit` or `tag: v1.4.2-post-external-audit`<br>
Fixing PR: https://github.com/valory-xyz/autonolas-tokenomics/pull/258/ <br>

## Objectives
The audit focused on verifying correctness of fixes in PR #258 (`fix_oracle_v2` branch) addressing C4A (Code4rena) findings from Group: Oracle V2.<br>
Source document: https://docs.google.com/document/d/1xUpnoVcD9jimdA9N-N67SC8bbmtYCyLSIQN1a19XXlk/edit?tab=t.0<br>
Original state: `v1.4.2-pre-external-audit`

### Changed files in PR#258 (contracts/ only)
```
contracts/libraries/UQ112x112.sol               — New: UQ112x112 fixed-point library
contracts/oracles/UniswapPriceOracle.sol         — Full rewrite: two-point TWAP, BPS, rate-limited
contracts/oracles/BalancerPriceOracle.sol        — Full rewrite: rolling-window TWAP, BPS, freshness
contracts/staking/OptimismDepositProcessorL1.sol — uint32 cast (unrelated to Oracle V2 findings)
contracts/staking/OptimismTargetDispenserL2.sol  — uint32 cast (unrelated to Oracle V2 findings)
```

### Security issues.
#### Checking the corrections made after C4A (Group: Oracle V2)

##### 1. H-1: UniswapPriceOracle::validatePrice() TWAP calculation is mathematically broken
```
Old code: twap = (cumulativeLast + price * dt - cumulativeLast) / dt = price (always equals spot).
Fix: contract fully rewritten with two-point TWAP via stored Observation(priceCumulative, timestamp).
validatePrice() now computes: twapUQ = (priceCumulativeNow - obs.priceCumulative) / elapsed.
Code: UniswapPriceOracle.sol:64-69 (Observation struct), :72 (lastObservation),
      :135-157 (updatePrice), :187-188 (TWAP = Δcum/Δt), :195-201 (BPS comparison),
      :204-226 (_currentCumulativePrice counterfactual extrapolation)
```
[x] Fixed

##### 2. Balancer oracle update can be used to mutate state even when it returns false
```
Old code: updatePrice() wrote to snapshot.cumulativePrice before rate-limit/deviation checks,
causing state drift on rejected updates.
Fix: commit-on-success pattern. All computation in memory, storage write only after all checks pass.
Code: BalancerPriceOracle.sol:164 (memory read), :169-171 (return false without storage write),
      :182-185 (memory computation), :188-189 (storage write only on success)
```
[x] Fixed

##### 3. Balancer oracle uses vault balances as price and can be steered by anyone
```
Old code: getPrice() reads raw Vault balances, manipulable intra-block.
Fix: getPrice() still reads Vault balances (only source for Balancer V2), but validatePrice()
now compares spot against rolling-window TWAP from two independent observations.
Intra-block manipulation is detectable via TWAP deviation.
Code: BalancerPriceOracle.sol:73-75 (prevObservation + lastObservation),
      :142-157 (getPrice from vault), :234-238 (TWAP = Δcum/Δt), :246-250 (BPS comparison)
```
[x] Fixed

##### 4. Incorrect calculation of timeWeightedAverage in UniswapPriceOracle leads to incorrect validation of price
```
Duplicate of finding #1. Same root cause: TWAP collapses to spot. Same fix.
```
[x] Fixed

##### 5. Inconsistent way of calculating current price and cumulativePriceLast
```
Old code: mixed 1e18-scaled spot with UQ112x112-based cumulative prices (dimensionally inconsistent).
Fix: all computations now in unified UQ112x112 system.
Code: UniswapPriceOracle.sol:4 (import UQ112x112), :44 (using UQ112x112 for uint224),
      :129 (getPrice returns UQ112x112), :210-224 (_currentCumulativePrice in UQ112x112*sec),
      :188 (TWAP cast to uint224/UQ112x112)
      contracts/libraries/UQ112x112.sol:1-21 (new library)
```
[x] Fixed

##### 6. Incorrect precision between cumulativePriceLast and tradePrice
```
Same root cause as finding #5. Same fix.
```
[x] Fixed

##### 7. BalancerPriceOracle Permanently Freezes After Large Market Movements
```
Old code: updatePrice() rejected updates when deviation > maxSlippage, never updating averagePrice.
A single large market move permanently froze the oracle.
Fix: updatePrice() no longer checks deviation — unconditionally records observation (subject to rate-limit).
Deviation is checked only in validatePrice() (read-only view function).
Rolling-window TWAP adapts to new price levels naturally.
Code: BalancerPriceOracle.sol:162-194 (updatePrice: no deviation gate, only rate-limit),
      :187-189 (unconditional shift: prevObservation = last, lastObservation = new),
      :200-251 (validatePrice: deviation check in view-only context)
```
[x] Fixed

##### 8. Uniswap oracle validatePrice can be griefed per block via sync()
```
Old code: if (block.timestamp == blockTimestampLast) return false — attacker front-runs with
permissionless sync() to set blockTimestampLast = block.timestamp, DoS-ing validatePrice per block.
Fix: validatePrice() no longer reads blockTimestampLast from pair for gating.
Validation window is based on lastObservation.timestamp (controlled by oracle via rate-limited updatePrice).
Code: UniswapPriceOracle.sol:163-202 (validatePrice: no blockTimestampLast),
      :170-174 (window from obs.timestamp), :182-185 (elapsed < minTwapWindow gate),
      :135-149 (updatePrice rate-limited via minUpdateInterval)
```
[x] Fixed

##### 10. Incorrect slippage validation causes swaps to go beyond the maxslippage for uniV2 swap in BuyBackBurner due to an edge case
```
This finding relates to contracts/utils/BuyBackBurner.sol:_buyOLAS().
It does not belong to Group: Oracle V2 and was erroneously included in the scope document.
```
[x] Out of scope for this PR

##### 11. An Adversary can utilize a suicide contract to create Forced ETH Refund in Aerodrome Router Interaction Leading to Reverts
```
This finding relates to contracts/utils/BuyBackBurner*.sol (missing receive() function).
It does not belong to Group: Oracle V2 and was erroneously included in the scope document.
```
[x] Out of scope for this PR

##### 12. Buyback DoS by Transferring Second Token to Treasury Due to Missing Access Control
```
This finding relates to contracts/utils/BuyBackBurner.sol:transfer().
It does not belong to Group: Oracle V2 and was erroneously included in the scope document.
```
[x] Out of scope for this PR

##### 14. Uniswap oracle validatePrice can be griefed per block via sync()
```
Duplicate of finding #8. Same fix.
```
[x] Fixed

### New Issue

#### High. BalancerPriceOracle bootstrap allows validation bypass
```
BalancerPriceOracle.sol:134-137
Constructor initializes both observations with {priceCumulative: 0, timestamp: block.timestamp}
(a // TODO marker is present on line 134).
After minTwapWindow seconds without calling updatePrice():
  priceCumulativeNow = 0 + spot * age
  twap = (spot * age - 0) / age = spot
  |spot - twap| = 0 → validation always passes
Between deployment and first updatePrice() slippage protection is absent (TWAP = spot).
Compare: UniswapPriceOracle does not initialize lastObservation → validatePrice() correctly
returns false before first updatePrice() (line 171-173).
Recommendation: remove bootstrap prevObservation from constructor (leave timestamp=0),
so validatePrice() reverts via ZeroValue() (line 211) until first updatePrice().

Details:
As currently implemented, both `prevObs` and `lastObs` are initialized with identical values in the constructor (same cumulative = 0 and same timestamp = `block.timestamp`).

If no `updatePrice()` call occurs, and `minTwapWindow` elapses, the TWAP calculation effectively degenerates into spot price, resulting in:

* `twap == spot`
* zero deviation
* `validatePrice()` always returning `true`

This creates a bootstrap bypass condition where the oracle appears valid without ever having recorded a meaningful observation window.

**Required fix:**

* Do not initialize a valid observation pair in the constructor.
* Require at least one (preferably two) successful `updatePrice()` calls before allowing `validatePrice()` to succeed.
* `validatePrice()` should revert or return `false` while the oracle is uninitialized.

**Required test:**

* Deploy oracle.
* Advance time beyond `minTwapWindow`.
* Ensure `validatePrice()` fails until at least one proper update cycle is completed.
```
[x] Fixed

#### Medium. UniswapPriceOracle missing zero-value checks in constructor
```
UniswapPriceOracle.sol:80-100
No checks for _minTwapWindowSeconds > 0 and _minUpdateIntervalSeconds > 0.
In BalancerPriceOracle these checks exist (line 105-107).
With minUpdateInterval=0 an attacker can call updatePrice() every block, resetting observation window.
With minTwapWindow=0 validation is possible after just 1 second.
Recommendation: add checks analogous to BalancerPriceOracle:
  if (_minTwapWindowSeconds == 0 || _minUpdateIntervalSeconds == 0) { revert ZeroValue(); }

Details:

The constructor does not validate that:

* `minTwapWindowSeconds > 0`
* `minUpdateIntervalSeconds > 0`

If either is zero:

* `minUpdateInterval = 0` allows continuous update spam.
* `minTwapWindow = 0` makes TWAP validation effectively meaningless.

**Required fix:**
Add explicit validation:
require(_minTwapWindowSeconds > 0, "InvalidTwapWindow");
require(_minUpdateIntervalSeconds > 0, "InvalidUpdateInterval");


**Required test:**

* Deploy oracle with zero values and assert that deployment reverts.

```
[x] Fixed

#### Medium. UniswapPriceOracle single observation griefing
```
UniswapPriceOracle.sol (design level)
UniswapPriceOracle stores one observation (line 72), BalancerPriceOracle stores two (lines 73-75).
After each updatePrice() the window resets to 0. If minUpdateInterval < minTwapWindow,
an attacker can call updatePrice() every minUpdateInterval seconds, keeping elapsed < minTwapWindow
and making validatePrice() always return false.
Recommendation: either add a second observation (as in Balancer),
or enforce in constructor that minUpdateInterval >= minTwapWindow.

Details:

The current design stores only a single observation.
If `minUpdateInterval < minTwapWindow`, an attacker can repeatedly call `updatePrice()` at each allowed interval, continuously resetting the observation timestamp so that:
elapsed < minTwapWindow

This causes `validatePrice()` to always return `false`, creating a liveness degradation or soft DoS.

**Required fix (choose one):**

Option A (strict invariant):

* Enforce `minUpdateInterval >= minTwapWindow` in constructor.

Option B (preferred, more robust):

* Store two rolling observations (`prevObs` and `lastObs`) and compute TWAP over the full window independent of recent update spam.

**Required test:**

* Simulate repeated `updatePrice()` calls at `minUpdateInterval`.
* Verify that attacker cannot permanently force `validatePrice()` to return `false`.
```
[x] Fixed, chose route A
