# Rejection rationale — C4A 2026-01 submission **S-893**

**Finding as reported:** `TokenomicsConstants.getInflationForYear` double-applies the mint cap fraction for `numYears >= 11`, yielding an effective rate of `f + f²` (2.04%) instead of `f` (2.00%).

**Proposed "fix" in the submission:**
```diff
- uint256 supplyCap = _calculateSupplyCapAfterYear10(1, numYears);
+ uint256 supplyCap = _calculateSupplyCapAfterYear10(1, numYears - 1);
```

**Repository disposition (after review on branch `fix-low-audit15`, 2026-04-21):**
**REJECTED — not a real issue.** The finding rests on a misreading of the `numYears` convention. Applying the proposed "fix" would introduce an actual bug (under-counted inflation for year 12 and beyond). This document records the numerical derivation so it can be sent back to the auditors.

**Cross-check against the final C4A report (2026-04-21):**
S-893 does **not** appear in the final Code4rena 2026-01 Olas report ([gist `kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38`](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38), file `Olas-draft-report.md`, 2308 lines). The final report contains 11 High (H-01..H-11), 12 Medium (M-01..M-12), and 15 Low (L-01..L-15) findings — none of them reference `getInflationForYear`, `_calculateSupplyCapAfterYear10`, `MAX_MINT_CAP_FRACTION`, the double-application claim, or the `2.04%` figure. S-893 is not listed in the "also found by" submission roster for any finding either. C4A's PJQA/triage process **dismissed** S-893 during finalization; this document's rebuttal only records the internal reasoning behind the same dismissal so downstream auditors or readers of the (now-removed) `docs/Vulnerabilities_list_tokenomics.md#13` entry can trace why.

Scope: the same analysis applies to both `getInflationForYear` (line 81) and `getActualInflationForYear` (line 134) — they share the identical else-branch arithmetic.

---

## 1. What `numYears` actually means

The single consumer of `getInflationForYear` / `getActualInflationForYear` in the post-year-10 path is `Tokenomics.checkpoint()`. Line 1135 of `contracts/Tokenomics.sol`:

```solidity
uint256 numYears = (block.timestamp - timeLaunch) / ONE_YEAR;
```

That is **integer full years elapsed since launch**, i.e.:

| elapsed time | `numYears` | we are in operational year |
|---|---|---|
| 0 ≤ t < 1 year | 0 | **year 1** |
| 1 ≤ t < 2 years | 1 | year 2 |
| … | … | … |
| 9 ≤ t < 10 years | 9 | year 10 |
| 10 ≤ t < 11 years | 10 | **year 11** |
| 11 ≤ t < 12 years | 11 | **year 12** |

So `numYears = k` means **we are currently living through operational year `k + 1`**, and `getInflationForYear(k)` must return the inflation budget **for year `k + 1`**.

This is confirmed by the first-10-years pre-computed table:

```solidity
uint88[10] memory inflationAmounts = [
    3_159_000e18,   // [0] = year-1 inflation
    40_254_084e18,  //   ...
    …
    30_161_788e18   // [9] = year-10 inflation
];
```

Cross-check against `getActualSupplyCapForYear`:

- `cap[9] − cap[8] = 761_726_593 − 731_564_805 = 30_161_788` ✓ — matches `inflationAmounts[9]`.

So the table maps `numYears = k → year (k + 1)`. The post-year-10 branch must follow the same convention.

## 2. What the OLAS contract actually requires for years ≥ 11

From `TokenomicsConstants.sol:26-27`:

```solidity
// After 10 years the inflation is 2% per year as defined by the OLAS contract
uint256 public constant MAX_MINT_CAP_FRACTION = 2;
```

The OLAS token contract caps annual inflation for year `y ≥ 11` at `2% of cap(year y − 1)`. Expressed in terms of the year-10 cap `S10 = 761_726_593e18`:

| operational year | cap at end-of-year | inflation DURING that year |
|---|---|---|
| 10 | `S10` | — (pre-tabulated = 30_161_788e18) |
| 11 | `S10 · 1.02` | `S10 · 1.02 − S10 = S10 · 0.02` |
| 12 | `S10 · 1.02²` | `S10 · 1.02² − S10 · 1.02 = S10 · 1.02 · 0.02` |
| 13 | `S10 · 1.02³` | `S10 · 1.02² · 0.02` |
| k ≥ 11 | `S10 · 1.02^(k − 10)` | `S10 · 1.02^(k − 11) · 0.02` |

## 3. What the current code returns (trace)

```solidity
function _calculateSupplyCapAfterYear10(uint256 firstYear, uint256 lastYear) internal pure returns (uint256) {
    lastYear -= 9;
    uint256 supplyCap = SUPPLY_CAP_YEAR10; // = S10
    for (uint256 i = firstYear; i < lastYear; ++i) {
        supplyCap += (supplyCap * MAX_MINT_CAP_FRACTION) / 100;
    }
    return supplyCap;
}
```

Call from the `else` branch of `getInflationForYear`: `_calculateSupplyCapAfterYear10(1, numYears)`.

| `numYears` | meaning | `lastYear` after `-= 9` | loop iterations `i ∈ [1, lastYear)` | returned `supplyCap` | `inflation = supplyCap · 2 / 100` | interpretation |
|---|---|---|---|---|---|---|
| 10 | year 11 | 1 | 0 (empty range `[1, 1)`) | `S10` | `S10 · 0.02` | year-11 inflation ✓ |
| 11 | year 12 | 2 | 1 (i = 1) | `S10 · 1.02` | `S10 · 1.02 · 0.02` | year-12 inflation ✓ |
| 12 | year 13 | 3 | 2 (i = 1, 2) | `S10 · 1.02²` | `S10 · 1.02² · 0.02` | year-13 inflation ✓ |
| k | year k+1 | k − 9 | k − 10 | `S10 · 1.02^(k − 10)` | `S10 · 1.02^(k − 10) · 0.02` | year-(k+1) inflation ✓ |

Every row matches the target column in §2. **The current implementation is arithmetically correct.**

## 4. Why the auditor's reading gives "2.04%"

Submission S-893 describes the result of `getInflationForYear(11)` as `S10 · 0.0204`, then compares that number against "2% of S10" and concludes the code is off.

That comparison is only valid if `numYears = 11 → year 11`. Under that convention the expected year-11 inflation would be `2% of cap(year 10) = S10 · 0.02`, and `S10 · 0.0204` would indeed be wrong.

But the table pinning (§1) and the single on-chain consumer (`Tokenomics.checkpoint()` at line 1135) both use `numYears = 11 → year 12`. Under that convention the target is year-12 inflation = `S10 · 1.02 · 0.02 = S10 · 0.0204`, which is exactly what the code returns.

The `0.0204` coefficient is not "2%-applied-twice" — it is the literal year-12 inflation expressed relative to `S10`: `cap(year 12) · 2% = (S10 · 1.02) · 2% = S10 · 0.0204`. The factor of `1.02` is not a second application of the mint cap; it is the compounding of the year-10 supply cap forward to year 11 before the 2% is taken for year 12.

## 5. What the proposed "fix" would actually do

Applying the S-893 patch `_calculateSupplyCapAfterYear10(1, numYears - 1)`:

| `numYears` | meaning | code after patch | inflation | correct target | status |
|---|---|---|---|---|---|
| 10 | year 11 | `_calc(1, 9)` → `lastYear=0`, empty loop → `S10` | `S10 · 0.02` | `S10 · 0.02` | coincidentally fine |
| 11 | year 12 | `_calc(1, 10)` → `lastYear=1`, empty loop → `S10` | `S10 · 0.02` | `S10 · 1.02 · 0.02` | **UNDER-COUNT (−2%)** |
| 12 | year 13 | `_calc(1, 11)` → `lastYear=2`, 1 iter → `S10 · 1.02` | `S10 · 1.02 · 0.02` | `S10 · 1.02² · 0.02` | **UNDER-COUNT (−2%)** |
| k ≥ 11 | year k+1 | `_calc(1, k−1)` | `S10 · 1.02^(k − 11) · 0.02` | `S10 · 1.02^(k − 10) · 0.02` | **one year stale** |

The "fix" returns the previous year's inflation budget for every year past year 11, i.e., the inflation schedule would stall at year-11 forever. Over time this is an under-issuance, not a security loss, but it is a real functional regression — `checkpoint()` would have less OLAS to distribute than the OLAS-contract cap permits.

## 6. Conclusion

- Item #13 in `docs/Vulnerabilities_list_tokenomics.md` is **removed** rather than fixed.
- The current code is correct under the `numYears = (block.timestamp − timeLaunch) / ONE_YEAR` convention used by its sole on-chain consumer.
- The S-893 submission is **respectfully rejected**. If the auditors can show a call-site that passes `numYears` under the alternative "year number" convention (where `numYears = 11 → year 11`), we will re-open; none exists in this repository.

## Appendix — concrete numbers for audit reproduction

```
S10 = 761_726_593e18 OLAS
MAX_MINT_CAP_FRACTION = 2

Year 11 inflation  = S10 × 0.02               = 15_234_531.86e18 OLAS
Year 12 inflation  = S10 × 1.02 × 0.02        = 15_539_222.50e18 OLAS
Year 13 inflation  = S10 × 1.02² × 0.02       = 15_850_006.95e18 OLAS
Year 20 inflation  = S10 × 1.02⁹ × 0.02       = 18_211_... e18 OLAS
```

Current `getInflationForYear` returns these values verbatim for `numYears = 10, 11, 12, …, 19`. The proposed patch would make `getInflationForYear(11) = 15_234_531.86e18` (year-11 value, off by 2%).
