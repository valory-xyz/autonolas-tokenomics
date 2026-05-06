# Internal audit 16 — closing PR review (C4R 2026-01 tokenomics-scope cross-reference)

**Date:** 2026-05-05
**Scope:** Every C4R 2026-01 Olas finding whose code lives in `autonolas-tokenomics`. Registries / governance findings are out of scope for this repo and omitted entirely from the matrices below — see the corresponding sibling-repo audit trails for their dispositions.
**Source of truth — C4R draft report:** [gist `kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38`](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38)
**Source of truth — fix dispositions / on-chain implications:** [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md). This doc is a C4R-ID-keyed re-presentation of the same dispositions, intended as a single landing page for downstream auditors who arrive holding the C4R draft and want to know, finding-by-finding, where each one was addressed.

> **Why this doc exists.** [`audits/internal15/README.md`](../internal15/README.md) and [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) together carry the full disposition story, but they are organized around *internal* finding IDs. A reader holding only the C4R draft (e.g. an Immunefi reviewer, a third-party auditor, or a future maintainer trying to verify "C4R L-01 — was it fixed or only documented?") has to triangulate across three documents. This file collapses that to a single matrix keyed by C4R ID, with the fix commit hash (or `docs/Vulnerabilities_list_tokenomics.md` entry number) cited inline.

> **What this doc does *not* duplicate.** This is **not** a re-audit. The fix mechanics, the orthogonal Code/Deployment matrix framework, the on-chain owner verification (C-01), and the H-01 storage-layout demotion analysis live in [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md). Use this doc to navigate from a C4R ID to the fix commit; use internal15 to understand what the fix actually does and whether the live on-chain proxies have it yet.

---

## §1. Disposition legend

Same legend as [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) §1, condensed for the C4R cross-reference:

| Code status | Meaning |
|---|---|
| ✅ Fixed in code | Fix landed in a named commit on `main` (or branch staged for merge). Cited inline. |
| 📝 Documented | Not fixed; explicitly accepted in [`docs/Vulnerabilities_list_tokenomics.md`](../../docs/Vulnerabilities_list_tokenomics.md). Cited as **VL #N**. |
| 🔄 Resolved by replacement | Surface that the C4R finding targeted no longer exists (e.g. function removed by a rewrite). |
| ⚖️ Rejected on review | Finding does not reproduce on the audited code; rebuttal cited. |

A given finding can map to two commits (e.g. an oracle rewrite + a follow-up `getTWAP()` extraction). Both are cited.

**Important — `docs/Vulnerabilities_list_tokenomics.md` is forward-looking.** Per team policy ([internal15/README.md §I-03](../internal15/README.md), 2026-04-21 user direction), VL is a "currently known, not yet resolved" list. When a finding is fixed, its VL entry is **removed**, not annotated. The historical record for fixed items lives in (a) the audit README that closed it, (b) the fix commit, and (c) this doc. So a C4R finding marked ✅ Fixed below will *not* have a corresponding live VL entry — that is intentional, not an omission.

**Per-row "Disposition" reads from left to right.** Severity is the C4R rating; *Code status* is one of the four buckets above; *Where it landed* names the fix commit (linked) or VL entry (numbered) or rejection rationale; *Evidence on `main`* points at file:line where the relevant logic now lives or where the finding's referenced surface has been removed.

---

## §2. Tokenomics-scope C4R findings — full matrix

### High (6 of 11; 5 are registries/governance, out of scope for this repo)

| C4R | Title | Code status | Where it landed | Evidence on `main` |
|-----|-------|-------------|-----------------|---------------------|
| **H-01** | Broken TWAP validation in `UniswapPriceOracle.validatePrice()` (TWAP collapses to spot) | ✅ Fixed in code | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) (V2 oracle rewrite) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) (`getTWAP()` extraction) | `contracts/oracles/UniswapPriceOracle.sol` — full rewrite; two stored observations (`prevObservation` + `lastObservation`) + rate-limited `updatePrice` + `getTWAP()` reading the cumulative delta. The `validatePrice()` surface that the C4R finding targets **no longer exists** on this contract; downstream slippage moved to `BuyBackBurner.mapTokenMaxSlippages` bounded by `MAX_BPS`. |
| **H-02** | Variable overwrite in `LiquidityManagerCore.checkPoolAndGetCenterPrice()` makes the deviation check dead code | ✅ Fixed in code | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273), C4R #17) + [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) (PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276), fail-open early-return closed) | `contracts/pol/LiquidityManagerCore.sol:checkPoolAndGetCenterPrice` — TWAP decoded into a separate `twapSqrtPriceX96` local; deviation compared against the preserved spot. Cardinality ≥ 2 fail-open replaced by `revert ObservationFailed(pool)` (closing both Root Cause B and the cardinality-bound part of Root Cause A from the C4R writeup). Cardinality-1 fresh pools still fall back to slot0 (intentional — see L-03). |
| **H-03** | Balancer oracle uses Vault spot balances; permissionless `updatePrice()` lets any address set the snapshot | ✅ Fixed in code (rate-limit + commit-on-success); residual flash-loan steerability within `minUpdateInterval` documented as VL #14 | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) (Balancer oracle V2 rewrite) | `contracts/oracles/BalancerPriceOracle.sol` — rolling-observations TWAP; rate-limit via `minUpdateInterval`; commit-on-success rejects samples that breach `maxSlippage` against the prior observation. The H-3 *steerability mechanism* (raw vault balances → snapshot) is bounded but not eliminated; the residual is **VL #14** with off-chain `ObservationUpdated` monitoring as the operational mitigation. |
| **H-04** | Incorrect TWAP formula in `BalancerPriceOracle.updatePrice()` (recursive averaging of `averagePrice`) | ✅ Fixed in code | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | `contracts/oracles/BalancerPriceOracle.sol` — old `cumulativePrice += averagePrice * elapsedTime` formula removed; replaced by Uniswap-V3-style two-observation rolling window with proper cumulative delta. The C4R recursive-averaging bug is structurally absent. |
| **H-08** | Logic inversion in `LiquidityManagerCore.checkPoolAndGetCenterPrice()` (instant vs TWAP direction) + fail-open early returns | ✅ Fixed in code | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR #273, C4R #18 — direction-preserving compare) + [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) (PR #276 — fail-open closed) | `contracts/pol/LiquidityManagerCore.sol:checkPoolAndGetCenterPrice` — real instant-vs-TWAP comparison preserves direction; cardinality ≥ 2 path now reverts on observe failure rather than returning unprotected spot. Same fix as H-02 — these two C4R IDs cover overlapping bugs in the same function. |
| **H-11** | `cumulativePrice` corrupted on rejected `BalancerPriceOracle.updatePrice` calls | ✅ Fixed in code | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) | `contracts/oracles/BalancerPriceOracle.sol` (and the matching `UniswapPriceOracle.sol`) — commit-on-success pattern: state writes happen only after the new sample passes the slippage band check against the prior observation. Rejected samples leave `cumulativePrice` and `lastObservation` untouched. |

### Medium (9 of 12; 3 are registries/governance, out of scope for this repo)

| C4R | Title | Code status | Where it landed | Evidence on `main` |
|-----|-------|-------------|-----------------|---------------------|
| **M-02** | Uniswap V2 `validatePrice` per-block grief via `pair.sync()` | ✅ Fixed in code | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) | `contracts/oracles/UniswapPriceOracle.sol` — the rewritten oracle is rate-limited via `minUpdateInterval`, so per-block `sync()` cannot overwrite the snapshot. The grief surface is structurally closed. |
| **M-03** | `UniswapPriceOracle` uses `priceCumulativeLast` inverted (wrong `direction`) | ✅ Fixed in code | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) | `contracts/oracles/UniswapPriceOracle.sol` — `direction == 0 → price0CumulativeLast`, `direction == 1 → price1CumulativeLast`. Fixed as part of the rewrite. |
| **M-04** | `UniswapPriceOracle` DoS / unit mismatch in liquidity migration (`maxSlippage / 100` divisor) | 🔄 Resolved by replacement | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) (V2 oracle rewrite — surface removed) | `contracts/oracles/UniswapPriceOracle.sol` — the rewrite has no `validatePrice` / `maxSlippage` surface; slippage enforcement moved to `BuyBackBurner.mapTokenMaxSlippages` bounded by `MAX_BPS`. |
| **M-05** | `BalancerPriceOracle.validatePrice` uses stale TWAP | ✅ Fixed in code | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | `contracts/oracles/BalancerPriceOracle.sol` — `_maxStalenessSeconds` is set in the constructor and enforced by `getTWAP()`; stale observations are rejected before they reach a slippage check. |
| **M-06** | `LiquidityManagerCore.changeRanges` silently sends single-sided liquidity to treasury | ✅ Fixed in code | [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) (PR [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273), C4R #19) | `contracts/pol/LiquidityManagerCore.sol:changeRanges` — `revert ZeroValue()` on `amounts[0] == 0 \|\| amounts[1] == 0`. The silent-fall-through-to-treasury branch is removed. |
| **M-07** | Slipstream `refundETH` DoS on `BuyBackBurnerBalancer._performSwap` | ✅ Fixed in code | [`62f5c6f`](https://github.com/valory-xyz/autonolas-tokenomics/commit/62f5c6f93d841186eaafe7880a5f9c94129ad216) (Internal14 cycle) | `contracts/utils/BuyBackBurner.sol` — `receive() external payable {}` added in the base, inherited by both Uniswap and Balancer children. Slipstream's `refundETH` now succeeds on zero-data ETH delivery; the front-run-and-pre-fund DoS is closed. |
| **M-09** | `Tokenomics.checkpoint()` does not correct `effectiveBond` downward at year boundaries where inflation decreases (Y2→3, Y9→10) | ✅ Fixed in code (🟡 redeploy required to be live on-chain) | [`9447968`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9447968) (PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276)) | `contracts/Tokenomics.sol` — new `else if (incentives[4] < curMaxBond)` branch with saturating subtraction (floors at zero). **Note:** the Year 2→3 transition is **2025-06-30 — already past** at the time of this writing (2026-05-05). Phantom bond capacity from that boundary may already be live on `0xc096…ce300`; the redeploy stops further drift but cannot retroactively undo it. See [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) §1 row M-04 for the full deployment-side analysis. |
| **M-11** | V3 `_performSwap` uses `amountOutMinimum = 1` (no slippage protection on Uniswap V3 / Slipstream swap) | ✅ Fixed in code | [`b45b9fa`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b45b9fa) (PR [#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275)) | `contracts/utils/BuyBackBurner.sol:_buyOLASV3` — TWAP-derived `amountOutMin` computed from `checkPoolAndGetCenterPrice` × `mapTokenMaxSlippages[secondToken]`; passed through to both Uniswap (`BuyBackBurnerUniswap._performSwap`) and Balancer/Slipstream (`BuyBackBurnerBalancer._performSwap`) children. Same fix simultaneously closes C4R **L-01**. |
| **M-12** | `BalancerPriceOracle` deadlock from cumulative-price weight (oracle becomes inertial; rejected updates freeze state) | ✅ Fixed in code | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | `contracts/oracles/BalancerPriceOracle.sol` — the deadlock-prone `cumulativePrice / averagePrice` formula is gone; the new oracle uses a two-observation rolling window with bounded staleness. The "frozen cumulative weight dominates new time period" deadlock is structurally absent. |

### Low / QA (13 of 15; 2 are registries, out of scope for this repo)

| C4R | Title | Code status | Where it landed | Evidence on `main` |
|-----|-------|-------------|-----------------|---------------------|
| **L-01** | V3 swaps slippage bypass (low-tick-liquidity / JIT manipulation; `amountOutMinimum = 1`) | ✅ Fixed in code | [`b45b9fa`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b45b9fa) (PR [#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275)) — same commit as M-11 | `contracts/utils/BuyBackBurner.sol:_buyOLASV3` — TWAP-derived `amountOutMin` makes JIT and low-tick-liquidity sandwiches unprofitable. The C4R writeup mentions "1 wei amountOutMinimum"; that surface is gone (see M-11 row). |
| **L-02** | `convertToV3` front-run via permissionless `collectFees` (burns OLAS staged for V3 conversion) | 📝 Documented | VL **#15** — added in [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | [`docs/Vulnerabilities_list_tokenomics.md` §15](../../docs/Vulnerabilities_list_tokenomics.md). Operator-playbook mitigation: stage OLAS in the same tx as `convertToV3` (atomic) instead of the bare two-tx pattern. Architectural fix deferred. |
| **L-03** | Slot0 fallback on newly-deployed pools with insufficient observations (`checkPoolAndGetCenterPrice` returns spot) | ✅ Partial (cardinality ≥ 2 case fixed); residual on cardinality-1 fresh pools is the L-04 surface | [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) (PR [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276)) closes the cardinality ≥ 2 portion via `revert ObservationFailed(pool)`. The residual cardinality-1 fresh-pool case (and the `_increaseLiquidity` / `_decreaseLiquidity` slot0 reads) tracked under L-04 (VL #16). | `contracts/pol/LiquidityManagerCore.sol:checkPoolAndGetCenterPrice:1154` — `revert ObservationFailed(pool)` on cardinality ≥ 2; cardinality-1 fresh pools fall back to slot0 (intentional preserved behavior — bootstrap window). |
| **L-04** | Ineffective slippage in `_increaseLiquidity` / `_decreaseLiquidity` due to spot-derived amounts | 📝 Documented | VL **#16** — added in [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | [`docs/Vulnerabilities_list_tokenomics.md` §16](../../docs/Vulnerabilities_list_tokenomics.md). Admin-only surface (`onlyOwner` via `convertToV3` / `changeRanges` / `increaseLiquidity` / `decreaseLiquidity`); realized exposure low under DAO-paced ops. TWAP-anchored `amountsMin` fix deferred. |
| **L-05** | Uniswap V2 `validatePrice` TWAP equals tradePrice (algebraic collapse) | ✅ Fixed in code (subsumed by H-01 rewrite) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) | `contracts/oracles/UniswapPriceOracle.sol` — the synthetic `cumulativePrice = cumulativePriceLast + (tradePrice * elapsedTime)` formula is gone. Real cumulative delta from two stored observations. Same fix as H-01. |
| **L-06** | `Tokenomics.changeRegistries` can lock pending user incentives | 📝 Documented | VL **#17** — added in [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | [`docs/Vulnerabilities_list_tokenomics.md` §17](../../docs/Vulnerabilities_list_tokenomics.md). Owner-gated; operational workflow is to claim outstanding incentives before rotating registries. Migration-preserving fix deferred. |
| **L-07** | Post-swap slippage validation doubles protection (trade-price compared to TWAP-band) | ✅ Fixed in code | [`62f5c6f`](https://github.com/valory-xyz/autonolas-tokenomics/commit/62f5c6f93d841186eaafe7880a5f9c94129ad216) (Internal14 cycle) | `contracts/utils/BuyBackBurner.sol` — the old post-swap `lowerBound`/`upperBound` recheck has been removed. The pre-swap TWAP band (Uniswap) / TWAP-derived `amountOutMin` (V3) is the single slippage gate. |
| **L-08** | `NeighborhoodScanner.value0InToken1` precision loss via two-step `mulDiv` | ✅ Fixed in code | [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | `contracts/pol/NeighborhoodScanner.sol:671-685` — single-step formulation (`amount · sqrtP² / 2^192`) for `sqrtP ≤ 2^128`; two-step `mulDiv` fallback retained only for extreme `sqrtP > 2^128` pools. Covered by 9 forge unit tests in `test/NeighborhoodScannerPrecision.t.sol`. |
| **L-09** | `Tokenomics._trackServiceDonations` integer-division precision loss across service units | 📝 Documented | VL **#18** — added in [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | [`docs/Vulnerabilities_list_tokenomics.md` §18](../../docs/Vulnerabilities_list_tokenomics.md). Bounded to `numServiceUnits − 1` wei per donation event; not exploitable; documented for completeness. Same finding class as the new L-NEW-4 surfaced in [`audits/internal16/README.md`](README.md) §3. |
| **L-10** | V2 `validatePrice(maxSlippage / 100)` forbids sub-1% slippage on `LiquidityManagerETH` / `LiquidityManagerOptimism` | ✅ Fixed in code | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | The `validatePrice(maxSlippage / 100)` divisor is gone — the V2 oracle rewrite removed the `validatePrice` surface entirely. Slippage enforcement is via `BuyBackBurner.mapTokenMaxSlippages` (BPS) on `BuyBackBurner.sol`; LiquidityManager-side V2 removal continues to use the TWAP gate via `getTWAP`. |
| **L-13** | `Tokenomics.checkpoint` permanently unusable if not called within `MAX_EPOCH_LENGTH` | 📝 Documented | VL **#19** — added in [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | [`docs/Vulnerabilities_list_tokenomics.md` §19](../../docs/Vulnerabilities_list_tokenomics.md). Surgical fix considered too entangled with epoch accounting; operationally mitigated by DAO keeper cadence + monitoring on missed checkpoint windows. Documented so a future `checkpoint()` refactor can bundle the fix. |
| **L-14** | `LiquidityManagerCore.changeMaxSlippage` no upper BPS check | ✅ Fixed in code | [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) (PR [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277)) | `contracts/pol/LiquidityManagerCore.sol:changeMaxSlippage:638-640` — `revert Overflow(newMaxSlippage, MAX_BPS)`. Mirrors the `initialize()` guard. 4 forge unit tests in `test/LowFindingsAudit15.t.sol`. |
| **L-15** | `UniswapPriceOracle.maxSlippage` not bounded `< 100` | 🔄 Resolved by replacement | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | `contracts/oracles/UniswapPriceOracle.sol` — the rewritten oracle has no `maxSlippage` storage and no `validatePrice` surface. Slippage moved to `BuyBackBurner.mapTokenMaxSlippages` (BPS) and bounded by `MAX_BPS` in `setMaxSlippages`. The C4R finding targets a function that no longer exists. |

---

## §3. Aggregate roll-up

### By disposition (tokenomics-scope C4R findings only — 28 total)

| Bucket | Count | C4R IDs |
|--------|------:|---------|
| ✅ Fixed in code | **20** | H-01, H-02, H-03¹, H-04, H-08, H-11, M-02, M-03, M-05, M-06, M-07, M-09², M-11, M-12, L-01, L-03¹, L-05, L-07, L-08, L-10, L-14 |
| 📝 Documented (VL entry) | **6** | H-03¹ (VL #14), L-02 (VL #15), L-04 (VL #16), L-06 (VL #17), L-09 (VL #18), L-13 (VL #19) |
| 🔄 Resolved by replacement | **2** | M-04, L-15 |
| ⚖️ Rejected on review | **0** | — |
| **Total** | **28** | — |

¹ H-03 is split: rate-limit + commit-on-success closes most of the surface (✅), the within-`minUpdateInterval` flash-loan steerability residual is documented (📝 VL #14). L-03 is split similarly: cardinality ≥ 2 path fixed (✅ via `b1542da`), cardinality-1 + spot reads in `_increase`/`_decreaseLiquidity` documented as VL #16 (= L-04). They are listed in the "majority disposition" row above; the secondary disposition is noted in the per-finding row in §2.
² M-09 is ✅ in code but **not yet live on-chain**: the Tokenomics impl deployment + Timelock `changeImplementation` on `0xc096…ce300` is a 🟡 pending step. See [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) §1 action items.

### By severity (tokenomics-scope C4R findings only)

| Severity | In scope | Out of scope (registries / governance) | C4R total |
|----------|---------:|---------------------------------------:|----------:|
| High | 6 | 5 | 11 |
| Medium | 9 | 3 | 12 |
| Low / QA | 13 | 2 | 15 |
| **Total** | **28** | **10** | **38** |

(C4R total of 38 reflects 11 H + 12 M + 15 L; the report's headline "23 unique vulnerabilities" counts only H + M.)

---

## §4. Fix-commit roll-up by PR

The same fix commits cited above, organised by the PR that landed them. Useful when a reader wants to verify a *PR* rather than a finding. Disposition matrix in §2 cites the *commit* (more granular); this table cites the *PR*.

| PR | Branch | Merge commit / tip | Tokenomics-scope C4R IDs closed |
|----|--------|---------------------|---------------------------------|
| Internal14 cycle (pre-#272) | several | [`62f5c6f`](https://github.com/valory-xyz/autonolas-tokenomics/commit/62f5c6f93d841186eaafe7880a5f9c94129ad216) | M-07, L-07 |
| Oracle V2 rewrite | (pre-#272) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b8a2db1ed1464a47a7f3aafb6d7daf69cb) + [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4f72eff39c0ace5c2fb93cd07e575dbfee) + [`d2515a6`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d2515a6fe4232cfda70d6d4ae6fbb570305f0076) | H-01, H-04, H-11 (partly), M-02, M-03, M-04, M-05, M-12, L-05, L-10, L-15 |
| [#272](https://github.com/valory-xyz/autonolas-tokenomics/pull/272) `restore-v3-bbb` | `restore-v3-bbb` | (per internal15) | (re-introduces the V3 swap surface; closures land in the follow-up PRs below) |
| [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273) `fix-v3-price-guards-audit` | `fix-v3-price-guards` | [`9bb4b03`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9bb4b03cb822faa5ec01fc1a13a44bd2fdd0252b) (merge of [`c8ca1d8`](https://github.com/valory-xyz/autonolas-tokenomics/commit/c8ca1d80a459bea23a66efca7555b1922dd4523d) + [`d22b0f5`](https://github.com/valory-xyz/autonolas-tokenomics/commit/d22b0f518f9c97d89c1d7814076a81e0b739ca11)) | H-02, H-08, M-06 |
| [#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275) `fix-v3-swap-slippage` | `fix-v3-swap-slippage` | [`b45b9fa`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b45b9fa) | M-11, L-01 |
| [#276](https://github.com/valory-xyz/autonolas-tokenomics/pull/276) `fix-medium-audit15` | `fix-medium-audit15` | [`b1542da`](https://github.com/valory-xyz/autonolas-tokenomics/commit/b1542da) + [`9447968`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9447968) | M-09 (Tokenomics decreasing-year), H-02 fail-open closure, L-03 cardinality ≥ 2 portion |
| [#277](https://github.com/valory-xyz/autonolas-tokenomics/pull/277) `fix-low-audit15` | `fix-low-audit15` | [`34e1a85`](https://github.com/valory-xyz/autonolas-tokenomics/commit/34e1a85) + [`eb55924`](https://github.com/valory-xyz/autonolas-tokenomics/commit/eb55924) | L-08, L-14, and the doc-only entries L-02 (VL #15), L-04 (VL #16), L-06 (VL #17), L-09 (VL #18), L-13 (VL #19) |
| `fix-l06-v3-second-token-mapping` (internal15 §8 follow-up; this audit's branch) | `fix-l06-v3-second-token-mapping` | [`a378ac4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/a378ac4) (+ [`5fadd70`](https://github.com/valory-xyz/autonolas-tokenomics/commit/5fadd70) test expansion) | (Closes internal-only L-06 + I-01; not a C4R finding — surfaced 2026-04-29 by internal review.) |

---

## §5. Quick reference — VL # ↔ current `Vulnerabilities_list_tokenomics.md` entry

The "VL #N" citations in §2 follow the numbering in [`docs/Vulnerabilities_list_tokenomics.md`](../../docs/Vulnerabilities_list_tokenomics.md) at the time of writing (HEAD `5fadd70`). Per team policy, VL entries are removed when fixed; the live numbering may shift over time as entries close. The mapping below is a snapshot.

| VL # (current) | Title | C4R origin |
|---|---|---|
| #14 | `BalancerPriceOracle.updatePrice` flash-loan steerability within `minUpdateInterval` | H-03 (residual) |
| #15 | `LiquidityManagerCore.convertToV3` front-run via permissionless `collectFees` | L-02 |
| #16 | `LiquidityManagerCore` slippage from spot in `_increaseLiquidity` / `_decreaseLiquidity` | L-04 |
| #17 | `Tokenomics.changeRegistries` can lock pending user incentives | L-06 |
| #18 | `Tokenomics._trackServiceDonations` precision loss via integer division | L-09 |
| #19 | `Tokenomics.checkpoint` permanently unusable after `MAX_EPOCH_LENGTH` without a call | L-13 |
| #20 | `BuyBackBurner` V3 path is per-chain optional (post-internal15 follow-up) | (operational, not a C4R finding) |

VL entries #1–#13 predate the C4R 2026-01 cycle and originate from earlier internal audits; not reproduced here.

---

## §6. Verdict

Every C4R 2026-01 tokenomics-scope finding has a known disposition on the current code:

- **20 of 28 are ✅ Fixed in code** with named fix commits.
- **6 of 28 are 📝 Documented** in `docs/Vulnerabilities_list_tokenomics.md` (VL entries #14, #15, #16, #17, #18, #19).
- **2 of 28 are 🔄 Resolved by replacement** (the `validatePrice`/`maxSlippage` surfaces no longer exist after the V2 oracle rewrite).
- **None are open or unaccounted-for.**

For the deployment-side picture (which fixes are 🟢 live on-chain vs ⚪ never deployed vs 🟡 pending redeploy on `0xc096…ce300`), see [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) §1's orthogonal Code/Deployment matrix. The summary: every BBB-side fix is ⚪ — it lands on-chain together with the fresh `BuyBackBurnerProxy` redeploy bundle that also closes C-01 (EOA-owner OpSec). The Tokenomics-side fix (M-09 + the legacy `refundFromStaking` typo) is 🟡 pending redeploy of a new impl + Timelock `changeImplementation`.

For the new findings that this audit cycle (internal16) surfaced beyond the C4R scope — 1 MEDIUM (Bridge2BurnerPolygon L1 destination), 5 LOW, 3 INFO — see [`audits/internal16/README.md`](README.md) §3.

---

### Doc metadata

- **Author:** internal audit 16 closing review (2026-05-05)
- **Composite tip:** `5fadd70` (`fix-l06-v3-second-token-mapping`)
- **C4R draft:** [gist](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38)
- **Companion documents:** [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) (full disposition framework + on-chain analysis), [`audits/internal15/README.md`](../internal15/README.md) (original C4A 2026-01 fix matrix), [`audits/internal16/README.md`](README.md) (this cycle's L-06/I-01 re-audit + broad-scope sweep)
