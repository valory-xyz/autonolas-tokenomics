# Internal audit 15 of autonolas-tokenomics — PR #273 re-audit (v2.22 methodology)
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
branch: `fix-v3-price-guards`, tip `ead1c83` — stacked on PR #272 `restore-v3-bbb`<br>
merge-base with `main`: `1d07c94` (5 commits, 26 files, +954 / −148 LOC)<br>
**Assumption**: PR #272 + PR #273 treated as merged into `main`.<br>

> **Closing review (2026-04-22):** the final disposition of every internal15 finding — across PRs #272, #273, #275, #276, #277 — is recorded in [`FINAL_REVIEW.md`](FINAL_REVIEW.md). That document is the authoritative justification for the resolution of all issues in this audit: per-finding evidence on the composite tip, on-chain verification of the H-01 non-manifestation, the dated C-01 OpSec waiver, and the regression scan. Verdict: **green** — no further re-audit required for the internal15 cycle.

## C4R 2026-01 fix matrix (PR #273 payload)

Stated purpose of PR #273 = three C4R 2026-01 price-guard fixes. All three landed in a single code commit with tests/docs in a follow-up commit; the PR merged at `9bb4b03`.

| C4R | Summary | Status | Fix commit |
|-----|---------|--------|------------|
| **#17** | Variable overwrite in `checkPoolAndGetCenterPrice` — `twapSqrtPriceX96` conflated with `centerSqrtPriceX96` | **FIXED** | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) |
| **#18** | Logic inversion in instant-vs-TWAP price guard (direction not preserved) | **FIXED** | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) |
| **#19** | `changeRanges` silently routes single-sided liquidity to treasury instead of reverting | **FIXED** | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) |

Tests + doc cleanup: [`d22b0f5`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d22b0f518f9c97d89c1d7814076a81e0b739ca11). PR merge: [`9bb4b03`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9bb4b03cb822faa5ec01fc1a13a44bd2fdd0252b).

For the full internal-audit-15 finding set (H-01 / H-02 / M-01…M-04 / L-01…L-05 / I-01…I-03 / C-01) and their dispositions + fix commits, see [`FINAL_REVIEW.md`](FINAL_REVIEW.md) §1.

## Objectives
This re-audit is driven by the developer reversing the **"fix-by-exclusion"** approach from Internal14. Internal14 verified that the V3 swap path in `BuyBackBurner` had been **removed** ("V3 ABI mismatch → V3 swap path removed entirely"); PR #272 **restores** it, and PR #273 layers on top the three C4R 2026-01 price-guard fixes (#17/#18/#19).

Because the exclusion is no longer in force, the restored V3 code must be re-verified against **all** prior audit findings that applied to it — not just the three fixes the PR advertises. Internal rule: the developer reads the 3 fixed C4R items; the auditor reads all 23 C4A items **plus** the integration surface the restoration introduces.

Methodology: Playbook v2.22 re-audit checklist — on-chain owner verification (Kelp-style OpSec), storage-layout preservation across proxy upgrades, full C4A 2026-01 cross-check.

Framing: we are the last line of defense before Immunefi. Risk = bounty payouts to external auditors for issues found after us.

**Scope restriction:** this report tracks only findings that land on the `autonolas-tokenomics` repository. C4A 2026-01 items whose code lives in `autonolas-registries` or `autonolas-governance` have been removed from the matrices below — they belong in the corresponding audit trails of those repos.

### Scope
PR #272 + PR #273 combined — 26 files, +954 / −148 LOC. Primary targets:
- `contracts/utils/BuyBackBurner.sol` — storage layout + V3 path restoration
- `contracts/utils/BuyBackBurnerUniswap.sol` + `BuyBackBurnerBalancer.sol` — V3 `_performSwap`
- `contracts/pol/LiquidityManagerCore.sol` — C4R #17/#18/#19 fixes
- `contracts/oracles/UniswapPriceOracle.sol` + `BalancerPriceOracle.sol` — regression check
- OpSec scope: 7 deployed BBB proxies across ETH + Arbitrum + Optimism + Gnosis + Polygon + Celo + Base

### Audit streams

| # | Stream | Target | Result |
|---|--------|--------|--------|
| 1 | C4R 2026-01 #17/#18/#19 logic fixes | `LiquidityManagerCore.checkPoolAndGetCenterPrice` + `changeRanges` | 3/3 FIXED |
| 2 | V3 restoration — storage layout on upgrade | `BuyBackBurner` base + derived proxies | **High (H-01)** |
| 3 | V3 restoration — swap slippage floor | `_performSwap` V3 branch (Uniswap + Balancer children) | **High (H-02)** |
| 4 | Oracle V2 residuals | `UniswapPriceOracle`, `BalancerPriceOracle` | Medium (M-02, M-03) |
| 5 | Price-guard residuals | `checkPoolAndGetCenterPrice` fail-open | Medium (M-01) |
| 6 | OpSec — on-chain ownership map | 7 BBB proxies × EVM chains | **Critical (C-01)** |
| 7 | V3 auxiliary surface | `checkPoolPrices`, `setV3PoolStatuses`, `getV3Pool` | Low / Info |
| 8 | `buyBack` deadline + parameter hygiene | external entry points | Low (L-01) |
| 9 | Full C4A 2026-01 re-verification matrix | all 11 High + 12 Medium findings | see matrix below |

## C4A findings fix verification

Scope verification was performed against the tokenomics-scope subset of the C4A 2026-01 report ([gist `kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38`](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38)). Registries and governance items are omitted per the scope restriction noted above. Each in-scope finding was re-checked against the current code on `fix-v3-price-guards`.

### High (tokenomics-scope subset)

Registries/governance items (C4A H-05, H-06, H-07, H-09, H-10) are handled in the corresponding repos and are not tracked here.

| C4A | Repo | Status | Fix commit |
|-----|------|--------|------------|
| H-01 Broken TWAP validation (UniswapPriceOracle spot = TWAP) | tokenomics/oracles | **FIXED** — full rewrite with two stored observations + rate-limit + counterfactual extrapolation | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) (V2 oracle rewrite) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) (`getTWAP()` extraction) |
| H-02 Variable overwrite in `checkPoolAndGetCenterPrice` | tokenomics/pol | **FIXED** (C4R #17) — TWAP decoded into separate `twapSqrtPriceX96`; returns TWAP | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273)) |
| H-03 Balancer oracle uses vault spot balances → steerable | tokenomics/oracles | **PARTIAL** — `getPrice()` still reads spot balances; rate-limited updates + commit-on-success mitigate but do not remove steer within `minUpdateInterval` → tracked as **M-02 (this report)** | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) (rate-limit + commit-on-success); residual unfixed by design |
| H-04 Incorrect TWAP in BalancerPriceOracle | tokenomics/oracles | **FIXED** — new rolling-observations TWAP | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) |
| H-08 Logic inversion in price guard + fail-open | tokenomics/pol | **Logic FIXED** (C4R #17/#18); fail-open staticcall residual surfaced as this report's **M-01**, then closed in PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276) | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR #273 — logic) + [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) (PR #276 — fail-open closed) |
| H-11 `cumulativePrice` corrupted on rejected update | tokenomics/oracles | **FIXED** — commit-on-success pattern | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) |

### Medium (tokenomics-scope subset)

Registries/governance items (C4A M-01 governance, M-08, M-10) are handled in the corresponding repos and are not tracked here.

| C4A | Repo | Status | Fix commit |
|-----|------|--------|------------|
| M-02 Uniswap `sync()` per-block grief | tokenomics/oracles | **FIXED** — new oracle is rate-limited via `minUpdateInterval` | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) |
| M-03 Price cumulative used inverted | tokenomics/oracles | **FIXED** — `direction == 0 → price0CumulativeLast` | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) |
| M-04 DoS unit mismatch in UniswapPriceOracle | tokenomics/oracles | **RESOLVED by replacement** | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) (V2 oracle rewrite) |
| M-05 `BalancerPriceOracle.validatePrice` uses stale TWAP | tokenomics/oracles | **FIXED** — `maxStaleness` enforced | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) |
| M-06 `changeRanges` silently sends liquidity to treasury | tokenomics/pol | **FIXED** (C4R #19) — `revert ZeroValue()` on single-sided | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273)) |
| M-07 Malicious user DoS Slipstream buyBack via `refundETH` | tokenomics/utils | **FIXED** — `receive() external payable {}` added at `BuyBackBurner.sol:585` (inherited by Balancer child) | [`62f5c6f`](https://github.com/valory-xyz/autonolas-tokenomics/commit/62f5c6f93d841186eaafe7880a5f9c94129ad216) (Internal14 cycle) |
| **M-09 `checkpoint()` no downward `effectiveBond` correction at year boundaries** | **tokenomics/Tokenomics.sol** | **FIXED** — `else if (incentives[4] < curMaxBond)` branch added with saturating subtraction at `Tokenomics.sol:1182`; tracked as this report's **M-04** | [`9447968`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9447968) (PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276)) |
| M-11 `amountOutMinimum = 1` on Slipstream/V3 swap | tokenomics/utils | **FIXED** — TWAP-derived `amountOutMinimum` wired through `_performSwap` V3 overrides, `mapTokenMaxSlippages[secondToken]` now read on the V3 path (closes this report's **H-02**) | [`b45b9fa`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b45b9fa) (PR [#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275)) |
| M-12 Balancer oracle deadlock from cumulative weight | tokenomics/oracles | **FIXED** — new oracle uses rolling observations, old `cumulativePrice / averagePrice` deadlock formula removed | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) |

### C4R 2026-01 PR-body items (the stated purpose of PR #273): 3/3 FIXED
All three fixed in [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (tests + docs in [`d22b0f5`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d22b0f518f9c97d89c1d7814076a81e0b739ca11)):
- [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) — **#17 variable overwrite** — `twapSqrtPriceX96` decoded separately; returns TWAP
- [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) — **#18 logic inversion** — real instant-vs-TWAP compare, direction-preserving
- [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) — **#19 `changeRanges` single-sided** — `revert ZeroValue()` on zero amount

### Low (tokenomics-scope subset)

Registries-scope C4A Lows (L-11, L-12) are handled in the registries repo and are not tracked here.

| C4A | Status | Fix commit |
|-----|--------|------------|
| L-01 V3 slippage bypass (JIT / low-tick-liquidity) | **FIXED (together with H-02)** — TWAP-derived `amountOutMinimum` closes the sandwich surface | [`b45b9fa`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b45b9fa) (PR [#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275)) |
| L-02 `convertToV3` front-run burns OLAS via `collectFees` | **NOT FIXED** (residual) — permissionless `collectFees` still allows burn-before-convert race; tracked as this report's **L-03**, documented residual | [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (doc-only, PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-03 slot0 fallback on new pools (few observations) | **PARTIAL** — subsumed by this report's **M-01** for cardinality ≥ 2; residual `_increaseLiquidity` / `_decreaseLiquidity` slot0 reads tracked as this report's **L-04** | [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) (PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276) — M-01 portion) |
| L-04 Ineffective slippage from spot in `_increaseLiquidity`/`_decreaseLiquidity` | **NOT FIXED** (residual) — LMC admin-only surface; flagged as this report's **L-04**, documented residual | [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (doc-only, PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-05 V2 oracle TWAP = spot | **FIXED** (H-01 rewrite) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) |
| L-06 Registry-address changes lock incentives | **DOCUMENTED residual** — not planned; added as item #17 of `docs/Vulnerabilities_list_tokenomics.md`. Owner-gated; operational mitigation only | [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (doc-only, PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-07 Post-swap slippage double-count | **FIXED** — old post-swap comparison removed (Internal14 cycle) | [`62f5c6f`](https://github.com/valory-xyz/autonolas-tokenomics/commit/62f5c6f93d841186eaafe7880a5f9c94129ad216) (Internal14) |
| L-08 Precision loss in `NeighborhoodScanner.value0InToken1` | **FIXED** — switched to Uniswap OracleLibrary single-step formulation (`amount · sqrtP² / 2^192`), two-step fallback retained only for `sqrtP > 2^128`. Covered by 9 forge unit tests in `test/NeighborhoodScannerPrecision.t.sol` | [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-09 Precision loss in `_trackServiceDonations` | **DOCUMENTED residual** — not planned; added as item #18 of `docs/Vulnerabilities_list_tokenomics.md`. Bounded to `numServiceUnits − 1` wei per donation event; not exploitable | [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (doc-only, PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-10 V2 `validatePrice(maxSlippage/100)` forbids sub-1% | **FIXED** — oracle rewrite removed `/100` divisor | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) |
| L-13 `checkpoint()` permanently unusable if not called within `MAX_EPOCH_LENGTH` | **DOCUMENTED residual** — not planned; added as item #19 of `docs/Vulnerabilities_list_tokenomics.md`. Entangled with epoch accounting, surgical fix deferred; DAO keeper cadence + off-chain monitoring mitigate operationally | [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (doc-only, PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-14 `changeMaxSlippage` no upper BPS check | **FIXED** — `LiquidityManagerCore.changeMaxSlippage` rejects `newMaxSlippage > MAX_BPS`; tracked as this report's **L-05** | [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) |
| L-15 `UniswapPriceOracle` maxSlippage not `< 100` | **RESOLVED BY REPLACEMENT** — rewritten `UniswapPriceOracle` has no `maxSlippage` or `validatePrice` surface; slippage enforcement moved to `BuyBackBurner.mapTokenMaxSlippages`, bounded by `MAX_BPS` in `setMaxSlippages` on `BuyBackBurner.sol`. C4R finding targets a function that no longer exists | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) |

### BuyBackBurner V3 restoration (previously "removed — fix by exclusion")

Internal14 recorded: *"V3 ABI mismatch → V3 swap path removed entirely (fix by exclusion)"*. That exclusion is **gone** as of PR #272. The restored surface adds:
- `liquidityManager`, `swapRouter` immutables set in constructor (signature widened from 2 → 4 args)
- `mapV3Pools` whitelist with `setV3PoolStatuses` owner-only setter
- V3 `_buyOLAS` branch that calls `checkPoolAndGetCenterPrice(pool)` then `_performSwap(...)`
- V3 `_performSwap` in both Uniswap and Balancer children
- `checkPoolPrices` external helper
- `getV3Pool(tokens[0], tokens[1], feeTier)` factory lookup

Re-verification on the restored code:
- V3 `amountOutMinimum = 1`, `sqrtPriceLimitX96 = 0` → **NEW High H-02** (= unfixed C4A M-11; `mapTokenMaxSlippages` still not read on V3 path)
- V3 storage additions inserted mid-base-class → **NEW High H-01** (layout break; V2 path dies silently on upgrade)
- `checkPoolPrices` accepts caller-supplied `uniV3PositionManager` → **Low L-06 (this report)**
- `setV3PoolStatuses` owner-only whitelist → **Info I-01** (does not verify pool is returned by factory for its `(token0, token1, fee)` triple)

### OpSec (NEW — not part of the C4A scope)
- All 7 BBB proxy owners are EOAs → **NEW Critical C-01** (Kelp-DAO pattern; single-key compromise → `changeImplementation()` → drain). Added to the re-audit checklist after the Kelp $294M incident on 2026-04-18.

## `docs/Vulnerabilities_list_tokenomics.md` hygiene

The project maintains a curated list of known vulnerabilities at `docs/Vulnerabilities_list_tokenomics.md` (16 items). This re-audit cross-checked the list for (a) coverage of the tokenomics-scope C4A 2026-01 findings and (b) rationale accuracy. Findings:

### 1. **Critically incomplete coverage of C4A 2026-01 (tokenomics scope only).** The list documents only **2** of the tokenomics-scope C4A items:
- Item #15 — C4A **M-09** (`checkpoint` effectiveBond year boundaries)
- Item #16 — Internal14's C2-1 (`updateInflationPerSecondAndFractions` effectiveBond reset)

The following **are not documented** in the list and should be added with current fix status:

| Missing C4A item | Current status | Suggested doc-list severity |
|------------------|----------------|------------------------------|
| H-01 UniswapPriceOracle TWAP = spot | FIXED (rewrite) | High — mark as FIXED |
| H-02 Variable overwrite in `checkPoolAndGetCenterPrice` | FIXED in [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR #273, C4R #17) | High — mark as FIXED |
| H-03 Balancer vault-balance steerability | PARTIAL (rate-limited) | High — mark as PARTIAL with residual link |
| H-04 Incorrect TWAP formula (Balancer) | FIXED (rewrite) | High — mark as FIXED |
| H-08 Logic inversion + fail-open in price guard | Logic FIXED, fail-open residual | High — mark as PARTIAL |
| H-11 `cumulativePrice` corrupted on rejection | FIXED (commit-on-success) | High — mark as FIXED |
| M-02, M-03, M-04, M-05, M-12 (oracle set) | FIXED by rewrite | Medium — batch entry referencing rewrite commit |
| M-06 `changeRanges` single-sided silent fail | FIXED in [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR #273, C4R #19) | Medium — mark as FIXED |
| M-07 Slipstream `refundETH` DoS | FIXED (`receive()` added at `BuyBackBurner.sol:585`) | Medium — mark as FIXED |
| **M-11 V3 `amountOutMinimum = 1`** | **NOT FIXED** (re-opened by PR #272) | **Medium → High** — the restored V3 path re-introduces this unfixed |
| **L-02 `convertToV3` front-run burns OLAS via `collectFees`** | NOT FIXED | Low — document + mitigation note |
| **L-04 Ineffective slippage in LMC `_increaseLiquidity`/`_decreaseLiquidity`** | NOT FIXED | Low — document |
| **L-14 `changeMaxSlippage` no upper BPS check** | NOT FIXED | Low — document |
| L-15 `UniswapPriceOracle` maxSlippage not `< 100` | Needs verify on rewrite | Low — verify + document |

### 2. **Item #15 rationale is factually wrong.** The doc reads:

> *"This is not an issue for the moment since every year the inflation slightly increases. This issue will be reconsidered in due time, as tokenomics is being constantly refactored."*

But the actual schedule in `contracts/TokenomicsConstants.sol:85-96` has **two decreasing transitions**:

| Transition | Old inflation | New inflation | Change |
|------------|---------------|---------------|--------|
| Year 2 → 3 | 40,400,000 OLAS | 25,260,023 OLAS | **-37.5%** |
| Year 9 → 10 | 30,161,788 OLAS | ~15,234,531 OLAS (2% compound) | **-49.5%** |

The C4A submission (S-1030) demonstrates ~346,068 OLAS phantom bond capacity at Y2→3 with comparable amount at Y9→10, totalling ~412K OLAS (~0.04% of total supply). The bug fires automatically at those year boundaries with no admin action needed. Current severity "Informative" and the "not an issue" rationale are both incorrect. Suggested re-classification: **Medium (pending fix) or Low (if explicit owner-only `changeTokenomicsParameters` is expected to catch the boundary first)**. Either way, the "inflation always increases" premise must be removed.

### 3. **PR #273 deletes entries instead of annotating them as FIXED.**
The diff `1d07c94..ead1c83 -- docs/Vulnerabilities_list_tokenomics.md` removes several historical entries wholesale rather than marking them as FIXED with the resolving commit hash. This breaks change-log auditability — future auditors cannot tell which entries were closed-and-fixed vs closed-and-reopened-later.

**Disposition (2026-04-21, team decision):** this is the team's established workflow (see I-03 below) — entries are removed once closed; the historical record lives in the per-audit README and git log. Closed as acknowledged.

### 4. **Item #12 (`refundFromStaking` incorrect revert address)** — FIXED on branch `fix-low-audit15`

**Finding recap** (C4A 2026-01 submission #130): `refundFromStaking` gates access on `dispenser` but the `ManagerOnly` revert reports `depository` as the second parameter. Purely cosmetic — access control is correct, only the error payload is misleading.

**Fix applied:** `contracts/Tokenomics.sol:838` changed from `revert ManagerOnly(msg.sender, depository)` → `revert ManagerOnly(msg.sender, dispenser)`.

**Test:** `test/Tokenomics.js` — extended "Should fail when calling dispenser-owned functions" test with an assertion on the revert parameters: `withArgs(signers[1].address, dispenserSigner.address)`. Passes with a non-matching depository configured to ensure the check isn't a tautology.

Entry removed from `docs/Vulnerabilities_list_tokenomics.md`.

[x] Closed by branch `fix-low-audit15`.

### 5. **Item #13 (`getInflationForYear` double-applied mint cap, C4A S-893)** — REJECTED on review, not a real issue

C4A 2026-01 submission **S-893** claimed that `getInflationForYear(numYears)` for `numYears >= 11` yields 2.04% annual inflation instead of the intended 2.00%, on the grounds that `MAX_MINT_CAP_FRACTION` is applied to an already-compounded supply cap.

On careful review of the single on-chain consumer (`Tokenomics.checkpoint` at line 1135), the `numYears` variable is **integer years elapsed since launch** — so `numYears = k` corresponds to operational **year `k + 1`**, not year `k`. Under that convention (which the first-10-years pre-computed table also follows), `getInflationForYear(11)` must return the year-12 inflation budget, which is `2% of cap(year 11) = S10 · 1.02 · 0.02 = S10 · 0.0204` — exactly what the code returns. The `0.0204` coefficient is not "2% applied twice"; it is literally the year-12 absolute amount expressed relative to `S10`.

Applying the submission's proposed patch (`_calculateSupplyCapAfterYear10(1, numYears - 1)`) would under-count inflation for every year ≥ 12, stalling the schedule one year behind — a real functional regression.

Full numerical derivation, trace table, and response to the submission authors: see [`C4A_S-893_rebuttal.md`](C4A_S-893_rebuttal.md).

Entry #13 removed from `docs/Vulnerabilities_list_tokenomics.md` as rejected-on-review (not fixed).

[x] Closed as rejected on branch `fix-low-audit15`.

## On-chain verification (fork + direct RPC)

| Check | Method | Result |
|-------|--------|--------|
| Storage layout break — derived fields currently at slot 7 | `cast storage <proxy> 7` on 7 chains | **Observed**: slot 7 = UniswapV2Router02 `0x7a250d56...` on ETH; Balancer Vault `0xba12222...` on L2s (original `63706f7` layout — V2-oracle rewrite never deployed). Only relevant if PR #272+273 is rolled out via in-place `changeImplementation()`. Fresh re-deployment (chosen path) sidesteps the mismatch entirely. |
| EOA owners — 6 chains | `cast storage <proxy> 0` + `cast codesize <owner>` | **CONFIRMED**: owner `0xeb2a22b27c7ad5eee424fd90b376c745e60f914e`, codesize = 0 on ETH / Arbitrum / Optimism / Gnosis / Polygon / Celo |
| EOA owner — Base | same | **CONFIRMED**: owner `0x6f7a4938ab3bbf69480e7c109af778ee78099be7`, codesize = 0 |
| LiquidityManager deployed? | `cast codesize` on BBB `liquidityManager()` | **NOT DEPLOYED** on any chain. V3 `_buyOLAS` calls `address(0)` today and reverts; admin must deploy and wire before V3 path can be exercised. |
| `initialize()` re-callable? | `cast call <impl> "initialize(...)"` → `AlreadyInitialized` | **CONFIRMED one-shot** — no re-init path exists on deployed implementations |

Deployed BBB proxies (verified 2026-04-20):

| Chain | ChainID | BBB proxy | Owner | Owner codesize |
|-------|---------|-----------|-------|----------------|
| Ethereum | 1 | `0xfAd04813BffD759a308A2BEaAcEf587720ba743F` | `0xeb2a22b27c7ad5eee424fd90b376c745e60f914e` | 0 (EOA) |
| Arbitrum | 42161 | `0xd2ff4Cf0927c3cFbF3BB27391044dBaf6f4ca7b9` | `0xeb2a22…914e` | 0 (EOA) |
| Optimism | 10 | `0x4891f5894634DcD6d11644fe8E56756EF2681582` | `0xeb2a22…914e` | 0 (EOA) |
| Gnosis | 100 | `0x153196110040A0c729227C603Db3A6c6D91851B2` | `0xeb2a22…914e` | 0 (EOA) |
| Polygon | 137 | `0x88943F63E29cd436B62cFfE332aD54De92AdCE98` | `0xeb2a22…914e` | 0 (EOA) |
| Celo | 42220 | `0x11949cBC85d8793B360029E26b18ae759708e28b` | `0xeb2a22…914e` | 0 (EOA) |
| Base | 8453 | `0x3FD8C757dE190bcc82cF69Df3Cd9Ab15bCec1426` | `0x6f7a4938ab3bbf69480e7c109af778ee78099be7` | 0 (EOA) |

## Security issues

### Critical. C-01 EOA owners on all 7 deployed BBB proxies (no multisig, no timelock)
```
All 7 deployed BuyBackBurner proxies (ETH mainnet + 6 L2s) are owned by
externally-owned accounts (codesize = 0):

  Ethereum  0xfAd04813BffD759a308A2BEaAcEf587720ba743F  owner 0xeb2a22…914e (EOA)
  Arbitrum  0xd2ff4Cf0927c3cFbF3BB27391044dBaf6f4ca7b9  owner 0xeb2a22…914e (EOA)
  Optimism  0x4891f5894634DcD6d11644fe8E56756EF2681582  owner 0xeb2a22…914e (EOA)
  Gnosis    0x153196110040A0c729227C603Db3A6c6D91851B2  owner 0xeb2a22…914e (EOA)
  Polygon   0x88943F63E29cd436B62cFfE332aD54De92AdCE98  owner 0xeb2a22…914e (EOA)
  Celo      0x11949cBC85d8793B360029E26b18ae759708e28b  owner 0xeb2a22…914e (EOA)
  Base      0x3FD8C757dE190bcc82cF69Df3Cd9Ab15bCec1426  owner 0x6f7a49…9be7 (EOA)

owner → changeImplementation() → arbitrary implementation → drain all buyBack flow.
Same Kelp-DAO-style setup as the $294M hack (2026-04-18).

Single-key compromise = total loss. Same EOA holds 6 chains — one key compromise
cascades across Arbitrum + Optimism + Gnosis + Polygon + Celo + Ethereum.
No multisig, no timelock, no on-chain governance gate.

PR #272+273 *widens* the attack surface that this one key controls: it adds
setV3PoolStatuses, setMaxSlippages, setLiquidityManager as additional levers.

Files: deployed implementations (admin functions changeImplementation, changeOwner)

Suggested fix:
  1. Rotate ownership to 3/5 Safe multisig on each of the 7 chains.
  2. Add 48h timelock on changeImplementation / changeOwner / setV3PoolStatuses /
     setMaxSlippages / setLiquidityManager (same as production Tokenomics/Dispenser pattern).
  3. Publish the multisig signer set + timelock deployer addresses in docs.
```

#### Developer remediation checklist for C-01

Minimum acceptable posture before re-enabling BBB upgrades on any of the 7 chains:

1. **Deploy the Safe + timelock stack in the right order, per chain:**
   - [ ] Deploy `Safe` (Gnosis Safe) with threshold **≥ 3 of 5** signers. Signers must be distinct humans with distinct hardware wallets; no two signers on the same HSM/cloud KMS; document the signer roster off-chain.
   - [ ] Deploy a `Timelock` (`OpenZeppelin TimelockController` or Olas `Timelock`) with `minDelay ≥ 48h`. `proposers = [Safe]`, `executors = [Safe]` or `[address(0)]` (anyone-can-execute-after-delay is fine — delay is the security).
   - [ ] Verify the Timelock bytecode with `cast code <timelock>` against the pinned source hash.
   - [ ] Rotate BBB proxy ownership with `changeOwner(<Timelock>)` — **Timelock**, not Safe, becomes the direct owner. Safe only acts as proposer/executor for the Timelock.

2. **Per-chain consistency:**
   - [ ] The same signer set on all 7 chains (makes rotation coordinated).
   - [ ] Timelock delay identical on all 7 chains.
   - [ ] Publish `(chain, BBB proxy, timelock, safe)` table in `docs/` so third parties can verify on-chain.

3. **Scope of timelock-gated functions** (the admin surface that PR #272+273 *widens*):
   - [ ] `changeImplementation(address)` — implementation upgrade
   - [ ] `changeOwner(address)` — ownership transfer
   - [ ] `setV3PoolStatuses(...)` — V3 pool whitelist (newly introduced)
   - [ ] `setMaxSlippages(...)` — per-token slippage caps
   - [ ] `setLiquidityManager(...)` / `setSwapRouter(...)` — swap routing (newly introduced)
   - [ ] Treasury / Depository drain paths (`drainer`, `drain(...)`)

4. **Defense-in-depth:**
   - [ ] `Pause` / `Guardian` role on a separate 2/3 Safe (instant response; can only **stop** buyBack, cannot reconfigure).
   - [ ] On-chain event emission for every admin action (already present — verify no silent paths).
   - [ ] Off-chain monitor (Tenderly / Defender / Watchdog) alerting on any `OwnershipTransferred`, `ImplementationChanged`, `MaxSlippagesChanged`, `LiquidityManagerSet` events on all 7 chains. Pager-grade (Opsgenie / PagerDuty).
   - [ ] Periodic (≤ 30 days) on-chain audit: `cast storage <bbb> 0` to assert owner has not drifted.

5. **Testing before cutover:**
   - [ ] Dry-run on each L2 testnet: deploy Safe+Timelock+BBB, upgrade implementation via the timelock path, verify 48h delay enforced.
   - [ ] Timelock `executeBatch` with `salt` to prevent hash collisions across chains.

6. **Risk acceptance (only if #1–5 will not happen before merge):**
   - [ ] Written risk-acceptance memo signed by governance; link it from `SECURITY.md`. Without this, C-01 blocks merge.

Reference implementations to borrow from (already in the Olas org): `Tokenomics` (owner = Timelock), `Treasury` (owner = Timelock), `Dispenser` (owner = Timelock). BBB is the outlier — match the pattern.

**Team response (2026-04-21):** acknowledged, and already covered by company policy — ownership on every BBB instance is rotated to Safe + timelock as part of any deployment/update cycle. Concretely: the fresh re-deployment that ships PR #272+273 will stand up the new `BuyBackBurnerProxy` instances and immediately transfer ownership to the per-chain Safe+timelock stack (matching the pattern already used by Tokenomics/Treasury/Dispenser). The finding is retained here as a checkpoint rather than a blocker: it gets closed when the deploy script publishes `(chain, new BBB proxy, timelock, safe)` in `docs/`.

[ ] Tracked — no code change needed in this PR. Closes at deployment time when ownership rotation is recorded in `docs/configuration.json`.

### High. H-01 Storage layout break — V2 `buyBack` path dies on in-place upgrade

**Re-evaluation (2026-04-21):** the original finding assumed the deployed proxies would receive the PR #272+273 implementation via in-place `changeImplementation()`. Cross-checking against the currently deployed implementations referenced in `docs/configuration.json` (BBB Uniswap `0x07749207793DC1f9208BFCAAA08ef1ea204402A6`, BBB Balancer across L2s) shows those implementations are the **original** BBB deploys (commit `63706f7`, Feb 2025) — i.e., the layout predates the V2-oracle rewrite:

```
Original base class ends at slot 6 (mapAccountActivities mapping), then:
  Uniswap child:  slot 7 = router                                (address, single slot)
  Balancer child: slot 7 = balancerVault, slot 8 = balancerPoolId
```

The intermediate "V2-oracle rewrite" implementation (which moved `mapV2Oracles` into slot 7 and pushed `router` / `balancerVault` down by one slot) was **never deployed** — the ABIs at `abis/0.8.28/BuyBackBurnerUniswap.json` / `BuyBackBurnerBalancer.json` expose only the original `oracle` / `router` / `maxSlippage` / `nativeToken` getters, and do not contain `mapV2Oracles` / `mapV3Pools` / `mapTokenMaxSlippages` / `liquidityManager` / `swapRouter`. So on-chain, the only proxies that exist are the original-layout proxies.

**Deployment plan for PR #272+273 is a fresh re-deployment** (new proxy + new implementation + `initialize(...)` on genesis storage), not an in-place upgrade of the existing proxies. Under the fresh-deploy path:

- `owner`, `olas`, `nativeToken`, `oracle` are set via `initialize(...)` as before.
- `mapV2Oracles` / `mapV3Pools` / `mapTokenMaxSlippages` are new mappings whose root slots read as empty from genesis.
- `router` (Uniswap child) / `balancerVault` + `balancerPoolId` (Balancer child) are written by `_initialize(...)` to their NEW slots (Uniswap: slot 10; Balancer: slot 10–11) — no stale value to conflict with.
- `liquidityManager`, `bridge2Burner`, `treasury`, `swapRouter` are immutables in code, so they consume no storage.

Conclusion: **H-01 does not fire under the intended deployment path.** The original finding is retained below as a methodology record, because it would be correct if the team were to attempt an in-place upgrade instead. Enforcement actions:

1. **Re-deployment is a hard requirement** for PR #272+273 — the deploy script must create new `BuyBackBurnerProxy` instances rather than pointing existing proxies at the new implementation.
2. The swap-over of off-chain consumers (`BuyBackBurner` addresses referenced in keeper scripts, dashboards, bridge2burner configuration) must be coordinated with the new proxy addresses.
3. Old proxies stay owned by the current EOA — they should be either (a) left untouched with the V2 path continuing to function on their original implementation, or (b) self-destructed / emptied, at the team's discretion.

Keep this as an **Info-only** artifact once the re-deployment path is committed in the deployment script. If the deployment strategy ever changes to in-place upgrade, the pre-rewrite analysis below applies verbatim.

<details>
<summary>Original in-place-upgrade analysis (applies only if an upgrade path is chosen instead of re-deployment)</summary>

```
PR #272 inserts `mapV3Pools` into the BASE class `BuyBackBurner` between
`mapV2Oracles` and `mapTokenMaxSlippages`. Derived classes
(BuyBackBurnerUniswap, BuyBackBurnerBalancer) declare their own state AFTER
the base — so `router` / `balancerVault` / `balancerPoolId` slots shift down
by the size of the inserted mappings.

On-chain verification of CURRENT layout (pre-upgrade):
  ETH (Uniswap):       cast storage <proxy> 7 = 0x7a250d56… (UniswapV2Router02) ← current `router`
  Optimism (Balancer): cast storage <proxy> 7 = 0xba12222…  (Balancer Vault)   ← current `balancerVault`

After in-place upgrade to the PR #272+273 implementation, the derived-class
fields are read from different slots and return 0x0:
  - Uniswap child: IRouter(router).swapExactTokensForTokens(...)   → revert on address(0)
  - Balancer child: IVault(balancerVault).swap(...)                → revert on address(0)

initialize() is ONE-SHOT — guarded by
  if (owner != address(0)) revert AlreadyInitialized();
so no re-init can re-populate the derived slots.
No external setter exists for router / balancerVault / balancerPoolId.

Result: V2 buyBack entirely DEAD on any upgraded proxy. Silent, unrecoverable.

Suggested fix (pick ONE):
  A. Add one-shot owner-only setters: setRouter(address), setBalancerVault(address),
     setBalancerPoolId(bytes32). Each guarded by `if (router != address(0)) revert`.
  B. Redeploy BBB proxies fresh on each of the 7 chains instead of upgrading.  ← CHOSEN
  C. Place `mapV3Pools` AT THE END of the base-class state (after all currently-occupied
     derived-class slots) to preserve layout. Requires per-child storage reasoning
     because Uniswap vs Balancer children have different derived-slot counts.
```
</details>

#### Methodology to prevent future storage-layout regressions

The root cause of the in-place-upgrade variant of H-01 is a process gap, not a coding bug. The PR body did not mention a storage-layout change; the `mapV3Pools` insertion was labeled as "restoration" and the derived-class slot shift was implicit. Even though the fresh-re-deployment path defuses H-01 for *this* PR, the following process controls should be adopted going forward so that a future in-place upgrade does not hit the same footgun.

1. **Mandatory pre-merge slot diff** — for any PR that touches a `.sol` file whose contract is deployed behind a proxy:
   - [ ] Generate the storage layout of `main` HEAD: `forge inspect <Contract> storage-layout --pretty > before.txt` (or `npx hardhat check --storage-layout`).
   - [ ] Generate the storage layout of the PR HEAD: `forge inspect <Contract> storage-layout --pretty > after.txt`.
   - [ ] `diff before.txt after.txt` — **any** non-additive change (slot renumbering, type change, insertion mid-contract, removal) blocks merge until explicitly justified.
   - [ ] For contracts with derived children (BBB → Uniswap/Balancer), run the diff on **each child**, not just the base. The bug here was invisible at the base-class level and only surfaced in children.

2. **Codify storage-append-only rule.** Upgradable contract source files should carry a header:
   ```solidity
   // STORAGE-APPEND-ONLY: new state variables MUST be added at the end of this file.
   // Any insertion or removal above this marker breaks deployed proxies.
   // ┌──────────────────────────────────────── DO NOT INSERT ABOVE THIS LINE ─┐
   mapping(address => Observation) public mapV2Oracles;
   mapping(address => uint256)     public mapTokenMaxSlippages;
   // ├──────────────────────────────────────── STORAGE APPEND BELOW ──────────┤
   mapping(address => uint8)       public mapV3Pools;   // ← NEW, appended
   // └────────────────────────────────────────────────────────────────────────┘
   ```
   The marker is enforced by a CI script that rejects diffs inserting a line above the "append below" comment in files tagged `STORAGE-APPEND-ONLY`.

3. **Derived-class storage reservation.** The BBB base currently has no storage gap. Add one going forward:
   ```solidity
   uint256[50] private __gap;   // reserved for future base-class state
   ```
   This lets future base-class additions consume gap slots without shifting derived-class state. Document the gap size as a contract invariant.

4. **On-chain layout verification at upgrade time.** Before `changeImplementation` is called on any proxy, the deploy script MUST run (scripted, not manual):
   - [ ] `cast storage <proxy> 0..N` for every non-mapping slot, comparing to the expected value from a pinned JSON snapshot.
   - [ ] Any mismatch halts the upgrade. The deploy script should emit the slot diff report to CI artifacts.

5. **Proxy upgrade test matrix in Foundry.** For every upgradable contract, maintain a fork-mode test that:
   - [ ] Forks mainnet at head.
   - [ ] Loads each deployed proxy on each supported chain.
   - [ ] Simulates `changeImplementation(<new impl from PR HEAD>)`.
   - [ ] Calls every derived-class function that reads post-gap state (`buyBack`, swap path, getters).
   - [ ] Asserts that no derived-class field reads `address(0)` / `bytes32(0)` / `0`.
   - [ ] Runs on every PR that touches upgradable contracts. This test would have caught H-01 automatically on branch `fix-v3-price-guards`.

6. **`initialize()` re-entry in emergencies.** The current `initialize() { if (owner != address(0)) revert AlreadyInitialized(); }` pattern makes rescue impossible. For future implementations, consider an owner-only `reinitialize(uint256 version)` pattern (OZ's `Initializable.reinitializer(v)` modifier) so that post-upgrade misconfiguration can be repaired without redeploying the proxy.

7. **PR template.** Extend the repo's PR template with a mandatory section:
   ```
   ## Storage layout impact
   - [ ] This PR does NOT touch any upgradable contract (skip the rest)
   - [ ] This PR touches an upgradable contract. Storage layout impact:
     - [ ] No change (append-only; append position confirmed)
     - [ ] Change — justified below with fix plan (A/B/C from H-01 playbook)
   ```

Adopting 1 + 2 + 5 covers ~90% of the risk. 3 + 4 + 6 are defense-in-depth.

[ ] **Does NOT block merge** given the fresh re-deployment plan. Add a deployment-script assertion that new `BuyBackBurnerProxy` instances are created (not an in-place `changeImplementation()` on existing proxies), and the item can be closed as Info.

### High. H-02 V3 `_performSwap` slippage floor = 1 wei — FIXED on branch `fix-v3-swap-slippage`

**Original finding:**
```
Both V3 swap implementations used:
  amountOutMinimum:  1
  sqrtPriceLimitX96: 0

The only guard was LiquidityManagerCore.checkPoolAndGetCenterPrice(), which
allows slot0 vs TWAP deviation up to MAX_ALLOWED_DEVIATION (±10%).

mapTokenMaxSlippages[token] was read ONLY in the V2 _buyOLAS path
(BuyBackBurner.sol:209). The V3 _buyOLAS branch called
  checkPoolAndGetCenterPrice(pool)
but did NOT read mapTokenMaxSlippages[secondToken] anywhere.

Consequence: permissionless buyBack(..., V3 path) could absorb sandwich losses
up to the full ±10% band on every trade. The per-token slippage cap configured
by setMaxSlippages was bypassed on the V3 route.

Files: contracts/utils/BuyBackBurnerUniswap.sol                (V3 _performSwap)
       contracts/utils/BuyBackBurnerBalancer.sol               (V3 _performSwap)
       contracts/utils/BuyBackBurner.sol                       (V3 _buyOLAS branch)
```

**Fix applied (branch `fix-v3-swap-slippage`):**
- `_buyOLAS(secondToken, amount, feeTierOrTickSpacing)` in `BuyBackBurner.sol` now captures the TWAP-derived `centerSqrtPriceX96` returned by `ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool)`, converts it to an OLAS-per-secondToken quote using the pool's token ordering (`olas == tokens[0]` vs `olas == tokens[1]`), and derives `amountOutMin = olasQuote * (MAX_BPS - mapTokenMaxSlippages[secondToken]) / MAX_BPS`. Math uses `FixedPointMathLib.mulDivDown` on a two-step `priceX128 = sqrtPriceX96^2 / 2^64` reduction to stay within uint256.
- V3 `_performSwap` virtual signature grew an `amountOutMin` argument; both Uniswap and Balancer children now forward it straight into `exactInputSingle.amountOutMinimum`.
- Unset per-token slippage keeps V2-path symmetry: `amountOutMin == full TWAP quote` → DEX naturally reverts.

**Tests:** `test/BuyBackBurnerV3Swap.t.sol` (5 unit tests, `forge test --mc BuyBackBurnerV3Swap`) and `test/LiquidityManagerETH.t.sol` (`testV3BuyBackWithTwapSlippage`, `testV3BuyBackRevertsOnTightSlippage` on ETH fork).

**Deployment note:** `mapTokenMaxSlippages` must now be populated for every `secondToken` used on the V3 path — same requirement the V2 path already has.

[x] Closed by branch `fix-v3-swap-slippage`.

### Medium. M-01 `checkPoolAndGetCenterPrice` fails open on `observe()` revert — FIXED on branch `fix-medium-audit15`

**Original finding:**
```
After the #17/#18 fix, the staticcall wrapper still contained:
  if (!success || returnData.length == 0) return centerSqrtPriceX96;

If observe() reverts (malformed pool, OLD revert, cardinality = 1, etc.), the
function silently returned the slot0 price — no TWAP check applied.

Combined with H-02 (±10% band as the only bound), a buyBack against an
adversarial V3 pool could burn OLAS at arbitrary price if the pool's observe()
was crafted to revert. The only remaining gate was setV3PoolStatuses (owner
whitelist), so this collapsed to a pure admin-trust boundary.
```

**Fix applied (branch `fix-medium-audit15`):** when the staticcall to `getTwapFromOracle` fails, read `slot0().observationCardinality` via a new `_getObservationCardinality(pool)` helper and branch on it — cardinality ≤ 1 means the pool is freshly-initialized and legitimately has no history to synthesize (the original fail-open semantic), so fall back to slot0; cardinality ≥ 2 means the pool claims history but its `observe()` is misbehaving (malformed or crafted to bypass the slippage guard), so revert with `ObservationFailed(pool)`. Preserves the admin-path `convertToV3` flow on fresh pools while closing the adversarial-pool escape hatch for permissionless `buyBack`.

Covered by:
- `test/LiquidityManagerCorePriceGuard.t.sol` — 2 unit tests: `test_checkPoolAndGetCenterPrice_revertsOnObserveRevert` (cardinality 60) and `test_checkPoolAndGetCenterPrice_fallsBackOnObserveRevertWithCardinalityOne`.
- `test/LiquidityManagerETH.t.sol` — `testCheckPoolAndGetCenterPrice_RevertsOnObserveRevertForkOverlay` exercises the revert path on the mainnet USDC/WETH 0.3% V3 pool (cardinality ~15k) using `vm.mockCallRevert` to force observe() failure.

[x] Closed by branch `fix-medium-audit15`.

### Medium. M-02 `BalancerPriceOracle.updatePrice()` still flash-loan-steerable within `minUpdateInterval` — Acknowledged residual, no code change
```
BalancerPriceOracle.updatePrice() reads spot balances from the Vault once per
minUpdateInterval and commits them as the new observation. Within that window,
a flash-loan move that happens to coincide with the update is committed to
state — the commit-on-success pattern (H-11 fix) does not reject the
adversarial sample because getPrice() returns non-zero on the manipulated balance.

Partial fix vs C4A H-03: rate-limited, but not immune to single-update
manipulation.

File: contracts/oracles/BalancerPriceOracle.sol — updatePrice()
```

**Disposition (branch `fix-medium-audit15`):** tracked as an accepted residual in `docs/Vulnerabilities_list_tokenomics.md` item #14 (renumbered from #20 in the source list during the L-bundle merge). The fix is architectural (swap the oracle source or rely on Vault-on-swap callbacks) rather than a local code edit — not in scope for this PR. Mitigations already in place: rate-limited updates, `maxStaleness` enforcement on `getTWAP()`, and per-token `mapTokenMaxSlippages` on the buyBack consumer. Off-chain monitoring on `ObservationUpdated` deviations is the primary control going forward; escalates to High if `updatePrice` ever becomes permissionlessly callable at tighter cadence or if `buyBack` volumes grow materially.

[x] Documented as residual.

### Medium. M-03 V2 `_buyOLAS` calls `getTWAP()` without prior `updatePrice()` — FIXED on branch `fix-medium-audit15`

**Original finding:**
```
V2 branch of _buyOLAS:
  uint256 twapPrice = IOracle(oracle).getTWAP();
is called WITHOUT an explicit IOracle(oracle).updatePrice() first.

If updatePrice() has not been called in the current interval, getTWAP returns
a value up to minUpdateInterval old.
```

**Fix applied (branch `fix-medium-audit15`):** insert `IOracle(poolOracle).updatePrice()` before `getTWAP()` in the V2 `_buyOLAS` branch. `updatePrice()` returns `false` (it does not revert) when the rate-limit window has not yet elapsed, so back-to-back buyBack calls are not self-DoSed — the oracle simply reuses the already-fresh observation.

Covered by:
- `test/BuyBackBurnerV2OracleRefresh.t.sol` — 2 forge unit tests with a mock oracle: `test_buyBack_refreshesOracle` asserts `updatePrice()` fires exactly once per `buyBack` and the router's `amountOutMin` matches the TWAP math; `test_buyBack_backToBackStillInvokesUpdatePrice` proves no self-DoS.
- `test/BuyBackBurnerUniswapETH.t.sol::testBuyBackRefreshesStaleOracle` — ETH-fork test that warps past `minUpdateInterval` and asserts the oracle's `lastObservation.timestamp` advances through the `buyBack` call.

[x] Closed by branch `fix-medium-audit15`.

### Medium. M-04 `checkpoint()` does not correct `effectiveBond` downward at year boundaries (C4A M-09) — FIXED on branch `fix-medium-audit15`

> **Note for readers: this is NOT a new finding.** M-04 is C4A 2026-01 submission **S-1030 (M-09)** tracked forward because it remained **unfixed** on branch `fix-v3-price-guards`. It is re-filed in this report (rather than only listed in the C4A verification matrix) because:
> 1. The branch crosses the **first** of the two trigger boundaries (Y2→Y3, 2025-06-30) during its lifetime — Y2→Y3 is already in the past as of the audit date (`currentYear() == 3` on mainnet 2026-04-20).
> 2. `docs/Vulnerabilities_list_tokenomics.md` item #15 documents the bug but with a **factually wrong rationale** ("every year the inflation slightly increases") that contradicts `TokenomicsConstants.sol:85-96`.
> 3. The fix is a **3-line code change** to an upgradable proxy (Tokenomics at `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300`, Timelock-owned) — low-cost to apply, not blocked by any scope restriction.
>
> Treat M-04 as a re-filing, not a duplicate: the severity stays at C4A's Medium, but the "Informative" label in item #15 must be corrected and the fix must be scheduled before any further year-boundary crossings.

```
C4A M-09 (submission S-1030) remains unfixed on branch `fix-v3-price-guards`.

Current code at Tokenomics.sol:1172-1177:
  // This has to be always true, or incentives[4] == curMaxBond if the epoch
  // is settled exactly at the epochLen time
  if (incentives[4] > curMaxBond) {
      // Adjust the effectiveBond
      incentives[4] = effectiveBond + incentives[4] - curMaxBond;
      effectiveBond = uint96(incentives[4]);
  }

There is NO `else if (incentives[4] < curMaxBond)` branch. The comment asserts
"this has to be always true", but that assertion is WRONG at year boundaries
where inflation DECREASES.

OLAS inflation schedule (TokenomicsConstants.sol:85-96) — actual values:
  Year 2 → 3: 40,400,000 → 25,260,023 OLAS (-37.5%)
  Year 9 → 10: 30,161,788 → ~15,234,531 OLAS (-49.5%)

At each decreasing-year crossing, `inflationPerEpoch` is computed as a blend
of old (higher) and new (lower) rates (lines 1138-1147), so
`incentives[4] < curMaxBond` — the `if` is false, the over-credit is never
subtracted, phantom bond capacity persists forever.

Impact (per C4A S-1030 PoC):
  ~346,068 OLAS phantom bond capacity at Y2→3
  Comparable at Y9→10
  Total ~412,000 OLAS (~0.04% of total supply)

`reserveAmountForBondProgram()` uses `effectiveBond` as its sole gatekeeper,
so Depository can create bond programs against the phantom and Treasury will
actually mint OLAS to pay bondholders.

The bug triggers AUTOMATICALLY at year boundaries with no admin action required.

Timeline (verified on-chain 2026-04-20, mainnet Tokenomics proxy
0xc096362fa6f4A4B1a9ea68b1043416f3381ce300):
  timeLaunch    = 1656584807 (2022-06-30 11:06 UTC)
  currentYear() = 3
  Year 2 → 3 boundary: 2025-06-30 — ALREADY IN THE PAST (~10 months ago).
  Year 3 → 4 boundary: 2026-06-30 — ~2 months ahead (no decrement here, +3%).
  Year 9 → 10 boundary: 2032-06-30 — ~6 years in the future.

Of the 11 year-boundary transitions in the OLAS inflation schedule, only TWO
are decrements (Y2→Y3 and Y9→Y10). At every other boundary `curMaxBond`
grows, so the developer's monotonicity assumption "this has to be always
true" holds for 9/11 transitions and for the entire post-Y10 +2% compound
regime. That explains why the bug was not caught during reviews; it also
means the bug is NOT hypothetical — the first of the two decrement points
has already been crossed on mainnet, and any epoch settled near that
boundary that landed `incentives[4] < curMaxBond` leaked phantom bond
capacity that is now permanently in `effectiveBond`.

Priority: the second decrement is years away, but the first ALREADY fired.
A fix-and-upgrade cycle is needed not only to protect Y9→Y10 but to close
the door on any further phantom accumulation (subsequent epochs in Y3 can
still drift `effectiveBond` away from its true ceiling — the phantom never
clears).

docs/Vulnerabilities_list_tokenomics.md item #15 describes this bug but
classifies it as "Informative" with rationale "every year the inflation
slightly increases" — this rationale is FACTUALLY WRONG (see schedule above).
The rationale is true for 9 of 11 year boundaries but false for exactly the
two boundaries where the bug actually fires, and one of those two is
already in the past.

Suggested fix (per C4A S-1030):
  if (incentives[4] > curMaxBond) {
      incentives[4] = effectiveBond + incentives[4] - curMaxBond;
      effectiveBond = uint96(incentives[4]);
+ } else if (incentives[4] < curMaxBond) {
+     // Adjust the effectiveBond downward when actual maxBond is less than pre-credited
+     effectiveBond = uint96(effectiveBond - (curMaxBond - incentives[4]));
  }

File: contracts/Tokenomics.sol:1172-1177
```

**Fix applied (branch `fix-medium-audit15`):** added the `else if (incentives[4] < curMaxBond)` branch with **saturating subtraction** (floors at 0) rather than the audit's raw `effectiveBond - (curMaxBond - incentives[4])` — so a hypothetical over-issuance of bonds before the boundary cannot underflow-revert checkpoint and brick epoch advancement. Direction stays conservative (under-counts remaining bond capacity, never over-counts). Also updates `docs/Vulnerabilities_list_tokenomics.md#15` rationale: replaces the factually-wrong "every year inflation slightly increases" premise with the actual schedule, marks severity **Medium** (not Informative), and records FIXED status with the branch reference.

Covered by two Hardhat tests in `test/Tokenomics.js` (grep `M-04`):
- *decreasing-year boundary* — walks `currentYear` 0→1→2→3 across the Y2→Y3 inflation decrease and asserts the crossing settles cleanly under the new branch.
- *else-if synthetic trigger* — uses `hardhat_setStorageAt` to double the packed `maxBond` slot (preserving `owner` in the low 160 bits) between checkpoints and asserts the settlement reduces `effectiveBond` by the full over-credit, matching the fix's arithmetic within 2 seconds of timing drift.

[x] Closed by branch `fix-medium-audit15`.

### Low. L-01 `buyBack(...)` has no `deadline`
```
buyBack() has no user-supplied deadline. A long-pending mempool tx can execute
at stale prices. Standard router-style deadline should be exposed to the caller.

File: contracts/utils/BuyBackBurner.sol — buyBack external

Suggested fix: add `uint256 deadline` parameter + `if (block.timestamp > deadline) revert Expired();`.
```

**Fix applied (branch `fix-low-audit15`):** both `buyBack` overloads now accept a trailing `uint256 deadline` parameter. The guard is `if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);`, so callers that don't need a deadline can pass `0` to opt out. New error `DeadlineExpired(uint256 deadline, uint256 blockTimestamp)` is defined alongside the existing custom errors in `BuyBackBurner.sol`. All existing test call sites and downstream fork tests updated to the new signature.

Covered by:
- `test/LowFindingsAudit15.t.sol` — 5 forge unit tests against a proxy + mocked ERC20 `balanceOf`: `test_L01_buyBack_V2_revertsWhenDeadlinePassed`, `test_L01_buyBack_V2_deadlineZeroOptsOut`, `test_L01_buyBack_V2_deadlineEqualsNowSucceedsDeadlineCheck`, `test_L01_buyBack_V3_revertsWhenDeadlinePassed`, `test_L01_buyBack_V3_deadlineZeroOptsOut`.
- `test/BuyBackBurnerUniswapETH.t.sol` — ETH-fork tests `testBuyBackRevertsOnExpiredDeadline` (funded proxy reverts on past deadline, then succeeds with a fresh deadline) and `testBuyBackDeadlineZeroOptsOut` (funded proxy succeeds with `deadline = 0`).

[x] Closed by branch `fix-low-audit15`.

### Low. L-02 `checkPoolPrices` accepts caller-supplied `uniV3PositionManager` — FIXED (annotation-only) on branch `fix-low-audit15`

**Original finding:**
```
External helper `checkPoolPrices(address uniV3PositionManager, ...)` trusts the
caller to supply a V3 NonfungiblePositionManager. A malicious contract can
supply a fake manager that returns arbitrary prices.

Exposure: read-only helper, no state change. Info-level risk today; Low risk if
it ever becomes wired into upgrade automation or keeper scripts.

File: contracts/utils/BuyBackBurner.sol — checkPoolPrices external

Suggested fix:
  require(uniV3PositionManager == TRUSTED_UNI_V3_NPM, UntrustedPositionManager());
Or annotate the function as "for diagnostic/read-only use — not safe to trust".
```

**Disposition (branch `fix-low-audit15`):** NatSpec on `checkPoolPrices` extended to make it explicit that the helper is a read-only diagnostic aid, that `uniV3PositionManager` is caller-supplied and untrusted, and that the result must NOT be wired into any trust-critical flow. Internal swap paths already use the pinned `liquidityManager.factoryV3()` instead. The no-pin / no-allowlist decision is kept to preserve the "legacy diagnostic" compatibility mode; entry #17 added to `docs/Vulnerabilities_list_tokenomics.md` records the constraint for downstream consumers.

[x] Closed (annotation-only) by branch `fix-low-audit15`.

### Low. L-03 `convertToV3` front-run via permissionless `collectFees` (C4A L-02, NOT FIXED) — Documented residual

**Original finding:**
```
C4A L-02 unfixed. `convertToV3()` in LiquidityManagerCore.sol expects tokens to
be pre-transferred; `collectFees()` is permissionless and burns OLAS balance.
An attacker watching the mempool can back-run a direct OLAS transfer + front-run
`convertToV3` with `collectFees`, burning the OLAS intended for V3 liquidity.

Exposure: owner-gated conversion workflow + permissionless collectFees. Low
realizable risk if the admin playbook avoids bare direct-transfer patterns, but
footgun remains.

File: contracts/pol/LiquidityManagerCore.sol — convertToV3 / collectFees

Suggested fix: atomic transfer+convert path; or gate collectFees by a
cooldown / skip-on-inflight-conversion flag. Document in the admin playbook.
```

**Disposition (branch `fix-low-audit15`):** added as entry #18 in `docs/Vulnerabilities_list_tokenomics.md`. Realized exposure is low when the operator avoids bare direct-transfer-then-call patterns (stage the OLAS inside the same transaction that calls `convertToV3`). The architectural fix (atomic transfer+convert path or in-flight cooldown) is out of scope for the low bundle; tracked for future LMC refactors.

[x] Documented as residual.

### Low. L-04 LMC slippage computed off spot-derived amounts (C4A L-04, NOT FIXED) — Documented residual

**Original finding:**
```
`_increaseLiquidity` / `_decreaseLiquidity` in LiquidityManagerCore compute
amountsMin from spot-derived amounts:

  amountsMin[i] = amountsMin[i] * (MAX_BPS - maxSlippage) / MAX_BPS;

Although `checkPoolAndGetCenterPrice` validates TWAP separately, the slippage
math is applied to amounts produced from slot0 — realized worst-case slippage
can stack up to `maxSlippage + ±10%` (deviation band).

Admin-only surface today, but increases MEV window on owner-initiated liquidity ops.

File: contracts/pol/LiquidityManagerCore.sol — _increaseLiquidity, _decreaseLiquidity

Suggested fix: use TWAP-derived center price for the amountsMin computation,
then apply maxSlippage to those TWAP-derived amounts.
```

**Disposition (branch `fix-low-audit15`):** added as entry #19 in `docs/Vulnerabilities_list_tokenomics.md`. Admin-only surface (`onlyOwner` via `convertToV3` / `changeRanges` / `increaseLiquidity` / `decreaseLiquidity`); realized exposure is low under normal DAO-paced operations. The TWAP-anchored fix is out of scope for the low bundle; tracked for future LMC refactors.

[x] Documented as residual.

### Low. L-05 `changeMaxSlippage` missing upper BPS bound (C4A L-14, NOT FIXED) — FIXED on branch `fix-low-audit15`

**Original finding:**
```
C4A L-14 unfixed. `LiquidityManagerCore.changeMaxSlippage()` checks only zero:

  if (newMaxSlippage == 0) revert ZeroValue();

No `if (newMaxSlippage > MAX_BPS) revert Overflow(...)` check, despite
`initialize()` having it. Misconfiguration could cause underflow on
`MAX_BPS - maxSlippage` in downstream math.

File: contracts/pol/LiquidityManagerCore.sol — changeMaxSlippage

Suggested fix:
  if (newMaxSlippage > MAX_BPS) revert Overflow(newMaxSlippage, MAX_BPS);
```

**Fix applied (branch `fix-low-audit15`):** `LiquidityManagerCore.changeMaxSlippage(uint16)` now mirrors the upper-bound check already present in `initialize()` — it reverts with `Overflow(newMaxSlippage, MAX_BPS)` when `newMaxSlippage > MAX_BPS`, closing the admin-misconfig path that could otherwise underflow the `(MAX_BPS - maxSlippage)` math in `_optimizeTicksAndMintPosition` / `_increase` / `_decreaseLiquidity`.

Covered by four forge unit tests in `test/LowFindingsAudit15.t.sol`:
- `test_L05_changeMaxSlippage_revertsAboveMaxBps` — expects `Overflow(10_001, 10_000)`.
- `test_L05_changeMaxSlippage_acceptsExactMaxBps` — boundary value `10_000` is accepted.
- `test_L05_changeMaxSlippage_acceptsWithinRange` — typical mid-range value.
- `test_L05_changeMaxSlippage_revertsZero` — regression on the existing zero-value guard.

Entry #20 added to `docs/Vulnerabilities_list_tokenomics.md` with FIXED status and test references.

[x] Closed by branch `fix-low-audit15`.

### Low. L-06 `BuyBackBurner.transfer()` can sweep V3-eligible secondTokens to treasury — late finding (2026-04-29), code fix pending

**Surfaced after** `FINAL_REVIEW.md` was issued (2026-04-22). Recorded here for the audit trail; full disposition lives in `FINAL_REVIEW.md` §8.1.

```
BuyBackBurner.transfer(token) at contracts/utils/BuyBackBurner.sol:621-656
gates on mapV2Oracles[token] != address(0). The V3 swap path authorizes
by *pool* (mapV3Pools[pool]), not by *token*, so a V3-only secondToken
(for example a stable wired up via setV3PoolStatuses + setMaxSlippages
but never given a V2 oracle) has mapV2Oracles[secondToken] == address(0)
and passes the eligibility check.

Any external caller can front-run the V3 buyBack overload with
transfer(secondToken) and divert the accumulated input balance to
treasury, bypassing the V3 swap into OLAS. No funds lost (treasury is
owner-controlled), but the V3 buyBack-and-burn workflow is publicly
griefable until the operator drains treasury back into BBB and retries.

Affected surface:
  - buyBack(address, uint256, int24, uint256)   (V3 4-arg overload)
  - any chain where the V3 path is enabled with at least one secondToken
    that has no V2 oracle (intended common case on V3-only chains)

Files: contracts/utils/BuyBackBurner.sol
       - transfer(address)              lines 621-656
       - setV3PoolStatuses(...)         lines 384-411
       - mapV2Oracles / mapV3Pools      lines 142-144

Suggested fix (preferred):
  Add `mapping(address => uint256) public mapV3SecondTokenRefs;`
  - In setV3PoolStatuses, when toggling pool status, read pool.token0() /
    token1(), pick the non-OLAS side as secondToken, and inc/dec the ref
    count. Skip the bookkeeping when the new status equals the old one
    so toggles are idempotent.
  - In transfer(), additionally revert with UnauthorizedToken(token)
    when mapV3SecondTokenRefs[token] > 0.

  Storage-append-only — no impact on existing slot layout.
  No re-init needed; bookkeeping is rebuilt by the operator re-toggling
  V3 pool whitelist via setV3PoolStatuses (or by a one-shot owner-only
  backfill helper if preferred).
```

**Operational mitigation (until fix lands):** off-chain monitor on every BBB proxy with V3 enabled, alerting on `TokenTransferred` events whose `to == treasury` and whose token is in the V3 secondToken set. On detection, the operator drains the diverted balance from treasury back into BBB and re-triggers the V3 `buyBack`.

Tracked in `docs/Vulnerabilities_list_tokenomics.md` #21.

[ ] Open — code fix pending. Closes when `mapV3SecondTokenRefs` (or equivalent) fix lands and `transfer()` rejects V3-eligible secondTokens.

### Notes. I-01 `setV3PoolStatuses` does not verify pool is returned by factory
```
Owner can whitelist an arbitrary address as a V3 pool. If the owner is
compromised (see C-01), an adversarial pool with a cooperating observe()
(see M-01) becomes a drain vector.

Suggested fix:
  require(IUniswapV3Factory(factory).getPool(token0, token1, fee) == pool,
          NotCanonicalV3Pool());
```
[ ] Captured via C-01 ownership rotation — if owner is Safe + timelock this is low risk.

### Notes. I-02 Token ordering via `>`
Token ordering uses strict `>`. OK for EVM addresses (cannot be equal).<br>
[x] No fix needed.

### Notes. I-03 `docs/Vulnerabilities_list_tokenomics.md` entries deleted instead of annotated `FIXED` — Acknowledged (team policy)

Audit hygiene — the PR removes entries wholesale rather than annotating them as resolved with commit hash. Makes change-log auditing harder. Doc-only.

**Disposition (2026-04-21, team decision):** the team's established workflow is to **remove** entries from `docs/Vulnerabilities_list_tokenomics.md` once a finding is fixed / addressed, rather than annotating as `FIXED in commit <hash>`. The change-log surface lives in (a) the per-audit README under `audits/<audit-id>/README.md` that closed the finding, and (b) the fix commit itself (`git log`, commit message). The `Vulnerabilities_list_tokenomics.md` doc is intentionally a forward-looking "currently known, not yet resolved" list — not a historical ledger. I-03 is therefore closed as acknowledged, not fixed: the recommendation to keep history in-list is explicitly declined in favour of the existing audit-README + git-log trail.

[x] Acknowledged — no doc protocol change. Each fix branch deletes its own closed entries from the vulnerabilities list; the audit README records the closure.

---

## Review summary

| Severity | Count |
|----------|-------|
| Critical | 1 (C-01 ownership rotation tracked as deployment-time operational item per company policy) |
| High     | 0 (H-02 FIXED on `fix-v3-swap-slippage`; H-01 demoted to Info under fresh re-deployment plan) |
| Medium   | 1 (M-02 acknowledged residual; M-01, M-03, M-04 FIXED on `fix-medium-audit15`) |
| Low      | 1 open (L-06 late finding 2026-04-29, code fix pending; L-01 + L-05 FIXED on `fix-low-audit15`; L-02 annotation-only, L-03 / L-04 documented residuals) |
| Notes    | 3 |
| **Total**| **6 residual; 9 closed** |

**Orthogonal Code / Deployment status split** (full per-finding matrix in `FINAL_REVIEW.md` §1; the table above conflates source-side and on-chain-side closure into a single severity count, which is exactly what the §1 split is meant to disambiguate):

| Bucket | Count | Findings |
|--------|------:|----------|
| ✅ Fixed in code, 🟡 Pending redeploy of an existing on-chain proxy (Tokenomics) | 2 | M-04, legacy VL #12 typo |
| ✅ Fixed in code, ⚪ Never deployed (lands with the fresh BBB / LMC / NeighborhoodScanner deploy bundle) | 7 | H-02, M-01, M-03, L-01, L-02, L-05, C4A L-08 |
| 📝 Documented (vulnerabilities-list residual), code unchanged | 8 | M-02 (#14), L-03 (#15), L-04 (#16), C4A-L-06 (#17), C4A-L-09 (#18), C4A-L-13 (#19), VL #12 current, I-01 (#22) |
| 🔴 Not fixed (open) — code fix pending | 1 | L-06 (late finding; documented in VL #21) |
| ⚖️ Rejected on review / 🔄 Resolved by replacement | 2 | S-893, C4A L-15 |
| — Not a code finding (OpSec / methodology / cosmetic) | 4 | C-01, H-01, I-02, I-03 |

### Test coverage gaps

| Priority | Contract:Function | Tests | Risk |
|:--------:|-------------------|:-----:|------|
| P0 | `BuyBackBurner` proxy upgrade preserving V2 storage (router/balancerVault/balancerPoolId) | 0 | H-01 — V2 path silently dies post-upgrade |
| P0 | `BuyBackBurnerUniswap._performSwap` + `BuyBackBurnerBalancer._performSwap` sandwich fork test against real V3 / Slipstream pools | 5 unit (`BuyBackBurnerV3Swap`) + 2 ETH-fork (`LiquidityManagerETH`) on `fix-v3-swap-slippage` | H-02 — 1-wei floor (CLOSED) |
| P1 | `LiquidityManagerCore.checkPoolAndGetCenterPrice` with reverting `observe()` | 2 unit (`LiquidityManagerCorePriceGuard.test_checkPoolAndGetCenterPrice_revertsOnObserveRevert` + `_fallsBackOnObserveRevertWithCardinalityOne`) + 1 ETH-fork (`LiquidityManagerETH.testCheckPoolAndGetCenterPrice_RevertsOnObserveRevertForkOverlay`, mocks observe() on the mainnet USDC/WETH 0.3% V3 pool) | M-01 fail-open (CLOSED on `fix-medium-audit15`) |
| P1 | `BalancerPriceOracle.updatePrice` flash-loan steer within minUpdateInterval | 0 — accepted residual | M-02 residual (documented, no code change) |
| P1 | V2 `_buyOLAS` getTWAP staleness without prior updatePrice | 2 forge unit (`BuyBackBurnerV2OracleRefresh.test_buyBack_refreshesOracle` + `_backToBackStillInvokesUpdatePrice`) + 1 ETH-fork (`BuyBackBurnerUniswapETH.testBuyBackRefreshesStaleOracle`) | M-03 (CLOSED on `fix-medium-audit15`) |
| P1 | `Tokenomics.checkpoint` else-if effectiveBond correction at year boundaries | 2 Hardhat (`Tokenomics.js#M-04`: decreasing-year walkthrough + storage-override synthetic trigger) | M-04 (CLOSED on `fix-medium-audit15`) |
| P2 | `buyBack` long-pending-tx at stale price | 5 forge unit (`LowFindingsAudit15.test_L01_buyBack_*`) + 2 ETH-fork (`BuyBackBurnerUniswapETH.testBuyBackRevertsOnExpiredDeadline` + `testBuyBackDeadlineZeroOptsOut`) | L-01 (CLOSED on `fix-low-audit15`) |
| P2 | `changeMaxSlippage` upper BPS bound | 4 forge unit (`LowFindingsAudit15.test_L05_changeMaxSlippage_*`) | L-05 (CLOSED on `fix-low-audit15`) |
| P2 | `setV3PoolStatuses` factory-ancestry enforcement | 0 | I-01 |

Systemic: no fork test on the V3 path against real Uniswap V3 (ETH/L2) or Slipstream (Base) pools; no cross-chain owner-ownership fixture; `testProxyUpgradePathMaxSlippagePreserved` covers `mapTokenMaxSlippages` but does NOT assert `router` / `balancerVault` / `balancerPoolId` survive the upgrade.

### Conclusion

> **Final disposition:** see [`FINAL_REVIEW.md`](FINAL_REVIEW.md) for the closing PR-review artefact covering PRs #272 + #273 + #275 + #276 + #277. It enumerates every internal15 finding as either **code-fix-required → FIXED** (with file:line evidence on the composite tip) or **acknowledged-and-deferred** (with the relevant residual or waiver). This supersedes the per-finding "required before deployment" list immediately below and is the justification for closing the internal15 cycle.

**PR #273 in isolation is correct** — the three C4R 2026-01 price-guard logic fixes (#17/#18/#19) are properly implemented in `checkPoolAndGetCenterPrice` and `changeRanges`.

**PR #272 + PR #273 as a unit still carries residual risk that should be addressed before deployment:**

1. **C-01 (Critical, OpSec)** — EOA owners on the existing proxies. Company policy rotates ownership to Safe+timelock at deploy time; captured but not a code-change item.
2. **H-02 (High, V3 slippage)** — FIXED on branch `fix-v3-swap-slippage` (TWAP-derived `amountOutMinimum` on both V3 overrides, `mapTokenMaxSlippages` now honored on the V3 path).
3. **H-01 (demoted to Info with fresh re-deployment plan)** — in-place upgrade would silently kill V2 `buyBack` on the existing proxies; fresh re-deployment sidesteps this. Must be locked in via the deploy script.

Required before deployment:
1. Rotate owner of the **new** BBB proxies to 3/5 Safe + 48h timelock on all 7 chains (closes C-01) — per company policy this happens at deploy time.
2. Lock the deployment script to a fresh `BuyBackBurnerProxy` path (closes H-01).
3. ~~Tighten V3 `_performSwap` to compute `amountOutMinimum` from TWAP + `mapTokenMaxSlippages`~~ — done on branch `fix-v3-swap-slippage` (closes H-02 / C4A M-11).
4. ~~Revert on `observe()` failure in `checkPoolAndGetCenterPrice`~~ — done on branch `fix-medium-audit15` (closes M-01).
5. ~~Auto-`updatePrice()` in V2 `_buyOLAS`~~ — done on branch `fix-medium-audit15` (closes M-03).
6. ~~Year-boundary `effectiveBond` correction in `checkpoint()`~~ — done on branch `fix-medium-audit15` (closes M-04 / C4A M-09); `docs/Vulnerabilities_list_tokenomics.md#15` rationale corrected in the same commit.
7. ~~Add `deadline` to `buyBack` while the surface is open~~ — done on branch `fix-low-audit15` (closes L-01).
8. ~~Fix `changeMaxSlippage` upper BPS bound~~ — done on branch `fix-low-audit15` (closes L-05 / C4A L-14).
9. Update `docs/Vulnerabilities_list_tokenomics.md`: add the tokenomics-scope C4A 2026-01 items with FIXED/PARTIAL/NOT-FIXED status + resolving commit hash; correct item #15 rationale (the "inflation always increases" claim contradicts TokenomicsConstants.sol:85-96). Entries #17–#20 added on branch `fix-low-audit15` cover the low bundle (L-02 annotation, L-03/L-04 documented residuals, L-05 FIXED).

Tracked follow-ups (not blocking):
- **M-02** — acknowledged architectural residual (`BalancerPriceOracle.updatePrice` spot sample inside `minUpdateInterval`). Documented in `docs/Vulnerabilities_list_tokenomics.md#14`; off-chain monitoring is the primary control.
- ~~L-02 / L-03 / L-04~~ — annotated + documented in `docs/Vulnerabilities_list_tokenomics.md` on branch `fix-low-audit15`. L-03 and L-04 remain tracked residuals (architectural fixes out of scope for the low bundle).

### Deployment-script impact sweep for the medium bundle

Walked `scripts/deployment/` (top level + `oracles/`, `utils/`, `staking/` and all chain subdirs) plus adjacent `scripts/proposals/`, `scripts/fork/`, `scripts/audit_chains/` for anything that touches the changed symbols (`checkpoint`, `effectiveBond`, `observe`, `ObservationFailed`, `checkPoolAndGetCenterPrice`, `getTWAP`, `updatePrice`, `updateInflation`):

| Script | What it does | Impact |
|--------|--------------|--------|
| `scripts/audit_chains/audit_contracts_setup.js:624-626` | Reads `polygonDepositProcessorL1.checkpointManager()` — unrelated to Tokenomics.checkpoint | none |
| `scripts/proposals/proposal_16_update_tokenomics_inflation.js:30` | Governance proposal calling `updateInflationPerSecondAndFractions(25, 4, 2, 69)` | none — M-04 changes internal-branch logic inside `checkpoint`, not the governance surface |
| `scripts/fork/tokenomics_update_with_timelock_account.js` | Fork helper reading `effectiveBond` + calling `updateInflationPerSecondAndFractions` | none — read + governance call, no change to expected behavior |
| `scripts/proposals/proposal_03_calculate_LP_OLAS_WETH_uniswap.js:232` | Reads `effectiveBond` | none — read-only |
| `scripts/deployment/staking/polygon/bridge_new_token.js:7` | URL comment mentioning `_checkpointManager` | none — comment only |

No deploy-script code changes required. Operator-facing notes (no script edits, just awareness):
- **M-01** — fresh V3 pools (cardinality == 1 immediately after `createAndInitializePoolIfNecessary`) still fall back to slot0; the TWAP guard engages naturally as swaps accrue observations. Deploy sequence for `convertToV3` on a brand-new pool is unchanged.
- **M-03** — the existing oracle warm-up sequence (two spaced `updatePrice()` calls before the first `buyBack`) is still required to populate `prevObservation` + `lastObservation`. The fix only adds an intra-buyBack refresh on top; it does not replace warm-up.
- **M-04** — no deploy step touches the new `else if` branch; the fix is internal to `checkpoint()`. Governance can continue to use `updateInflationPerSecondAndFractions` unchanged (item #16's separate effectiveBond-reset caveat still applies).

### Key observation — fix-by-exclusion reversed
Internal14 relied on "V3 swap path removed entirely" as the closure for a cluster of C4A V3 concerns. PR #272 reverses that by restoring V3, so the V3 surface returns to the audit scope — **and brings two new integration-era issues** (H-01 storage layout, H-02 1-wei floor) that could not exist while V3 was absent. The developer's PR #273 description fixes 3 C4R items; the re-audit must cover the 23 C4A items **plus** the restoration's integration footprint **plus** deployment/OpSec state. This asymmetry is exactly why fix-by-exclusion is an anti-pattern: the moment the exclusion is reversed, the audit budget balloons.

### Methodology
- Playbook: v2.22 re-audit checklist — OpSec on-chain owner map + storage-layout preservation + C4A 2026-01 cross-check (tokenomics-scope only)
- On-chain verification: 7 EVM chains via public RPC + QuikNode (`cast storage`, `cast codesize`, `cast call`)
- C4A baseline: gist `kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38` — only tokenomics-scope items are re-filed here; registries/governance items are tracked in those repos
- BBB proxy addresses verified (see "On-chain verification" table above)
- Owner EOAs verified codesize = 0:
  - `0xeb2a22b27c7ad5eee424fd90b376c745e60f914e` (ETH + Arbitrum + Optimism + Gnosis + Polygon + Celo)
  - `0x6f7a4938ab3bbf69480e7c109af778ee78099be7` (Base)
- 3 C4A findings explicitly re-verified as PARTIAL → tracked as this report's M-01 / M-02 / M-03
- 2 NEW findings outside C4A scope — H-01 (storage layout on upgrade) + C-01 (OpSec) — surfaced by this re-audit
