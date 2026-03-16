# Medium: UniswapPriceOracle — TWAP blackout after every updatePrice()

## 1. Problem

UniswapPriceOracle stores a single `lastObservation`. Both `updatePrice()` and `getTWAP()`
reference the same observation, creating a conflict: every update resets the TWAP window to zero.

Current `updatePrice()` (lines 131-153):
```solidity
function updatePrice() external returns (bool) {
    uint256 priceCumulativeNow = _currentCumulativePrice();
    Observation memory obs = lastObservation;
    if (obs.timestamp > 0) {
        uint256 dt = block.timestamp - obs.timestamp;
        if (dt < minUpdateInterval) { return false; }  // rate limit
    }
    // *** overwrites the only observation ***
    lastObservation = Observation({priceCumulative: priceCumulativeNow, timestamp: block.timestamp});
    return true;
}
```

Current `getTWAP()` (lines 158-184):
```solidity
function getTWAP() external view returns (uint256) {
    Observation memory obs = lastObservation;
    if (obs.timestamp == 0) { revert ZeroValue(); }

    uint256 priceCumulativeNow = _currentCumulativePrice();
    uint256 elapsed = block.timestamp - obs.timestamp;  // *** uses same observation ***

    if (elapsed < minTwapWindow || elapsed == 0) {       // *** reverts when elapsed < minTwapWindow ***
        revert ZeroValue();
    }

    uint224 twapUQ = uint224((priceCumulativeNow - obs.priceCumulative) / elapsed);
    if (twapUQ == 0) { revert ZeroValue(); }
    return (uint256(twapUQ) * 1e18) >> 112;
}
```

Immediately after `updatePrice()`, `obs.timestamp == block.timestamp`, so `elapsed == 0` → revert.
TWAP becomes available only after `minTwapWindow` seconds elapse without another update.

Timeline (minTwapWindow=300s, minUpdateInterval=600s):
```
t=0      updatePrice()  → lastObservation.timestamp = 0
t=600    updatePrice()  → lastObservation.timestamp = 600   (first observation)
t=601    getTWAP()      → elapsed = 1 < 300                 → REVERT (blackout)
t=899    getTWAP()      → elapsed = 299 < 300               → REVERT (blackout)
t=900    getTWAP()      → elapsed = 300 >= 300              → OK ✓
t=1200   updatePrice()  → lastObservation.timestamp = 1200  (window reset to 0)
t=1201   getTWAP()      → elapsed = 1 < 300                 → REVERT (blackout again)
```

Blackout duty cycle: 300 / 600 = **50% of the time TWAP is unavailable**.

## 2. Impact

**Normal operation**: every oracle update creates a predictable blackout window of
`minTwapWindow` seconds. All downstream consumers revert during this window:
- `BuyBackBurner.buyBack()` → `_buyOLAS()` → `IOracle(poolOracle).getTWAP()` → revert
- `LiquidityManagerETH._checkTokensAndRemoveLiquidityV2()` → `IOracle(oracle).getTWAP()` → revert
- `LPSwapCelo._removeLiquidity()` → `IOracle(oracle).getTWAP()` → revert

**Griefing DoS**: `updatePrice()` is permissionless. Anyone can call
`BuyBackBurner.updateOraclePrice(secondToken)` → `IOracle(poolOracle).updatePrice()` to
trigger the blackout. Cost: only gas per `minUpdateInterval`. The attacker calls updatePrice()
every `minUpdateInterval` seconds, maximizing the blackout window.

**Worst case**: if `minTwapWindow == minUpdateInterval` (allowed by the constructor check
`_minTwapWindowSeconds > _minUpdateIntervalSeconds` at line 90, which permits equality),
the blackout covers 100% of the cycle. TWAP becomes available at the exact moment when the
next updatePrice() is also allowed — an attacker (or even a legitimate keeper) calling
updatePrice() immediately resets the window. TWAP is effectively permanently unavailable.

## 3. Why BalancerPriceOracle does NOT have this bug

Both oracles face the same fundamental challenge: they are **off-chain-fed** TWAP oracles.
Neither Uniswap V2 nor Balancer V2 provides a ready-to-use TWAP value — both oracle contracts
manually track observations and compute TWAP as `(cumulative_now - cumulative_then) / dt`.

The difference is **not** that Uniswap V2 has a "built-in TWAP" and Balancer doesn't.
Uniswap V2 pairs expose `priceCumulativeLast` (an on-chain accumulator updated on every
swap/mint/burn), but this is just a data source — the oracle still needs to store at least
two snapshots of it to compute a delta. The Balancer oracle accumulates manually
(`spot * dt`), but the math is identical: `delta_cumulative / delta_time`.

The critical difference is purely structural: **one observation vs two**.

### BalancerPriceOracle (2 observations — no blackout)

```solidity
// Storage (lines 67-69):
Observation public prevObservation;    // ← extra observation
Observation public lastObservation;

// updatePrice() (lines 173-175) — shifts window:
prevObservation = last;                    // old "last" becomes "prev"
lastObservation = Observation({...now...}); // new "last" = current

// getTWAP() (lines 202-214) — uses prev as window start:
uint256 dtWin = block.timestamp - prev.timestamp;   // *** prev, not last ***
if (dtWin < minTwapWindow) { revert ZeroValue(); }
uint256 priceCumulativeNow = last.priceCumulative + spot * age;
uint256 twap = (priceCumulativeNow - prev.priceCumulative) / dtWin;
```

After `updatePrice()` in Balancer:
```
prevObservation.timestamp = old_last.timestamp    (in the past, e.g. t=600)
lastObservation.timestamp = block.timestamp       (now, e.g. t=1200)

getTWAP():
  dtWin = now - prev.timestamp = 1200 - 600 = 600  → ≥ minTwapWindow → OK ✓
  age   = now - last.timestamp = 1200 - 1200 = 0
  priceCumulativeNow = last.priceCumulative + spot * 0 = last.priceCumulative
  twap = (last.priceCumulative - prev.priceCumulative) / 600  → valid TWAP
```

The TWAP window `[prev.timestamp, now]` always spans at least one `minUpdateInterval`
(because prev = previous last, and consecutive updates are at least `minUpdateInterval` apart).
TWAP is available immediately after every update — **zero blackout**.

### Side-by-side comparison

```
                        UniswapPriceOracle          BalancerPriceOracle
─────────────────────────────────────────────────────────────────────────
Observations stored     1 (lastObservation)         2 (prev + last)
TWAP window start       lastObservation.timestamp   prevObservation.timestamp
After updatePrice():
  window start          = block.timestamp (now)     = old lastObservation.timestamp
  elapsed               = 0 → REVERT               ≥ minUpdateInterval → OK
Blackout after update   minTwapWindow seconds       NONE
maxStaleness check      NO                          YES
Cumulative price src    Uniswap V2 on-chain         Manual: spot * dt accumulation
```

### Why both designs are symmetric in architecture

Both oracles follow the same pattern:
1. `updatePrice()` — snapshot current price data into an observation
2. `getTWAP()` — compute delta between a past observation and "now"

The only architectural difference is that Uniswap V2 provides `priceCumulativeLast` on-chain
(so the oracle reads it), while for Balancer the oracle computes `priceCumulative += spot * dt`
manually. This is a difference in **data source**, not in **observation count**. The Balancer
oracle wasn't forced to use two observations because of the manual accumulation — it was a
deliberate design choice to avoid blackouts. The Uniswap oracle should adopt the same choice.

## 4. Suggested fix — full code replacement

### Step A: Add `prevObservation` storage

Replace line 66:
```solidity
// Stored last observation used for TWAP
Observation public lastObservation;
```
with:
```solidity
// Previous observation for rolling TWAP window
Observation public prevObservation;
// Stored last observation used for TWAP
Observation public lastObservation;
```

### Step B: Replace `updatePrice()` (lines 131-153)

```solidity
/// @dev Records a fresh TWAP observation from the Uniswap V2 pair.
/// @notice Permissionless but rate-limited to prevent griefing resets.
/// @return True if price update is successful.
function updatePrice() external returns (bool) {
    // Get current cumulative price
    uint256 priceCumulativeNow = _currentCumulativePrice();

    // Get last observation
    Observation memory obs = lastObservation;
    if (obs.timestamp > 0) {
        // Get observation dt
        uint256 dt = block.timestamp - obs.timestamp;

        // Check if dt is lower than min update interval
        if (dt < minUpdateInterval) {
            return false;
        }
    }

    // Shift window: previous becomes last, current becomes new last
    prevObservation = lastObservation;
    lastObservation = Observation({priceCumulative: priceCumulativeNow, timestamp: block.timestamp});

    emit ObservationUpdated(msg.sender, priceCumulativeNow, block.timestamp);

    return true;
}
```

Changes from current code:
- Added `prevObservation = lastObservation;` before overwriting `lastObservation` (one line).

### Step C: Replace `getTWAP()` (lines 158-184)

```solidity
/// @dev Gets the current TWAP price in 1e18 format.
///      Reverts if the oracle is not initialized, or the TWAP window is insufficient.
///      Requires at least 2 updatePrice() calls for warmup.
/// @return TWAP price in 1e18 format (OLAS per secondToken).
function getTWAP() external view returns (uint256) {
    // Get both observations
    Observation memory prev = prevObservation;
    Observation memory last = lastObservation;

    // Check if initialized (need at least 2 updatePrice() calls)
    if (prev.timestamp == 0 || last.timestamp == 0) {
        revert ZeroValue();
    }

    // Get current cumulative price
    uint256 priceCumulativeNow = _currentCumulativePrice();

    // TWAP window: from prev observation to now
    uint256 dtWin = block.timestamp - prev.timestamp;

    // TWAP history check
    if (dtWin < minTwapWindow || dtWin == 0) {
        revert ZeroValue();
    }

    // TWAP in UQ112x112
    uint224 twapUQ = uint224((priceCumulativeNow - prev.priceCumulative) / dtWin);

    // Check for zero value
    if (twapUQ == 0) {
        revert ZeroValue();
    }

    // Convert from UQ112x112 to 1e18 format
    return (uint256(twapUQ) * 1e18) >> 112;
}
```

Changes from current code:
- Reads `prevObservation` in addition to `lastObservation`.
- Uses `prev.timestamp` (not `obs.timestamp`) as window start.
- Uses `prev.priceCumulative` (not `obs.priceCumulative`) in delta calculation.
- Initialization check requires both observations to be non-zero (needs 2 updatePrice() calls).

### After fix — timeline (same parameters)

```
t=0      updatePrice()  → prev=(0,0), last=(cum0, 0)         (1st call, prev still zero)
t=600    updatePrice()  → prev=(cum0, 0), last=(cum600, 600)  (2nd call, warmup done)
t=601    getTWAP()      → dtWin = 601-0 = 601 ≥ 300          → OK ✓  (no blackout!)
t=900    getTWAP()      → dtWin = 900-0 = 900 ≥ 300          → OK ✓
t=1200   updatePrice()  → prev=(cum600, 600), last=(cum1200, 1200)
t=1201   getTWAP()      → dtWin = 1201-600 = 601 ≥ 300       → OK ✓  (no blackout!)
t=1800   updatePrice()  → prev=(cum1200, 1200), last=(cum1800, 1800)
t=1801   getTWAP()      → dtWin = 1801-1200 = 601 ≥ 300      → OK ✓  (no blackout!)
```

**Zero blackout** at any point after the initial 2-call warmup.

## 5. Off-chain keeper: update frequency requirements

The oracle relies on an external keeper (off-chain bot or manual call) to call `updatePrice()`
periodically. The update frequency determines both TWAP availability and TWAP quality.

### Current design (1 observation) — keeper constraints

```
                      minUpdateInterval
                    ◄───────────────────────►
    updatePrice()                               updatePrice()
         │                                           │
    t=0  ▼                                     t=600 ▼
         ├────── BLACKOUT ──────┤── AVAILABLE ──┤
         │   minTwapWindow=300  │    300s        │
         │   getTWAP() reverts  │  getTWAP() OK  │
```

- TWAP unavailable for `minTwapWindow` seconds after each update
- Available window per cycle: `minUpdateInterval - minTwapWindow`
- Duty cycle: `(minUpdateInterval - minTwapWindow) / minUpdateInterval`
- Keeper must call exactly once per `minUpdateInterval` for maximum availability
- If keeper calls more often than `minUpdateInterval`, `updatePrice()` returns false (no harm)
- If keeper calls less often, TWAP window grows (less responsive, but available)

### After fix (2 observations) — keeper constraints

```
    updatePrice()        updatePrice()        updatePrice()
         │                    │                    │
    t=0  ▼              t=600 ▼             t=1200 ▼
         ├── warmup ──►  ├── TWAP OK ──────► ├── TWAP OK ──────►
         │ (need 2nd     │ dtWin=601 ✓       │ dtWin=601 ✓
         │  call first)  │ no blackout       │ no blackout
```

- TWAP available immediately after 2nd updatePrice() call (warmup)
- No blackout regardless of update frequency
- Keeper should update regularly to keep TWAP responsive

### maxStaleness — the missing upper bound

Currently UniswapPriceOracle has **no maxStaleness check** (unlike BalancerPriceOracle).
If the keeper stops updating, the TWAP window grows without bound:

```
Last update at t=1000. No further updates.

t=2000:   dtWin = 1000s    TWAP over ~17 min  — OK
t=10000:  dtWin = 9000s    TWAP over ~2.5 hrs — degraded
t=100000: dtWin = 99000s   TWAP over ~27 hrs  — very stale, poor slippage protection
t=604800: dtWin = 603800s  TWAP over ~1 week  — essentially a long-term average
```

A stale TWAP averages over too long a window, masking recent price movements and
weakening slippage protection for BuyBackBurner and LiquidityManager.

**Recommendation**: add `maxStaleness` immutable (same as BalancerPriceOracle), checked
in `getTWAP()`:
```solidity
uint256 age = block.timestamp - last.timestamp;
if (age > maxStaleness) {
    revert Overflow(age, maxStaleness);
}
```

This forces the keeper to update at least once per `maxStaleness` seconds. See separate
Low finding "UniswapPriceOracle: missing maxStaleness check".

### Practical parameter guidance

```
Parameter              Suggested range         Rationale
───────────────────────────────────────────────────────────────────────
minTwapWindow          300-900s (5-15 min)     Minimum TWAP window to resist
                                               single-block manipulation.
                                               Shorter = more responsive but
                                               easier to manipulate.

minUpdateInterval      600-1800s (10-30 min)   Rate-limit against griefing.
                                               Must be ≥ minTwapWindow (enforced
                                               by constructor). Determines minimum
                                               gap between keeper calls.

maxStaleness           3600-86400s (1h-1d)     Maximum acceptable age of last
                                               observation. If exceeded, getTWAP()
                                               reverts to prevent stale pricing.
                                               Shorter = more protection, but
                                               keeper must be more reliable.

Keeper update cadence:
  - Minimum: once per maxStaleness (or getTWAP reverts)
  - Optimal: once per minUpdateInterval (most responsive TWAP)
  - The TWAP window after fix spans [prev.timestamp, now]:
    - If updated every minUpdateInterval: window ≈ minUpdateInterval (responsive)
    - If updated less often: window grows up to maxStaleness (smoothing)
```

### Relationship between parameters

```
minTwapWindow ≤ minUpdateInterval ≤ maxStaleness

     ◄─── minTwapWindow ───►
     │                      │
     │  minUpdateInterval   │
     ◄──────────────────────────────►
     │                              │
     │          maxStaleness        │
     ◄──────────────────────────────────────────────────────►

After fix, TWAP window = block.timestamp - prevObservation.timestamp
  - Minimum window: ≈ minUpdateInterval (if keeper updates on schedule)
  - Maximum window: ≈ 2 * maxStaleness (if prev is from 2 intervals ago,
    last barely within staleness, and current time = last + maxStaleness)
  - In practice: window stays between minUpdateInterval and
    minUpdateInterval + maxStaleness
```

## Files

- `contracts/oracles/UniswapPriceOracle.sol:58-66` (storage)
- `contracts/oracles/UniswapPriceOracle.sol:131-153` (updatePrice)
- `contracts/oracles/UniswapPriceOracle.sol:158-184` (getTWAP)
- For comparison: `contracts/oracles/BalancerPriceOracle.sol:67-69, 148-179, 185-222`
