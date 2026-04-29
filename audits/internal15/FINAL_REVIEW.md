# Internal audit 15 — closing PR review (PR #273 fix stack)

**Date:** 2026-04-22
**Methodology:** `PR_REVIEW_<n>` closing artefact (per `feedback-pr-review-vs-reaudit.md`).
A PR review is a lightweight re-verification of the team's fix bundle against the internal15 findings. It is **not** a new audit — it does not re-open the attack surface, it does not enumerate new findings. The only question is: does the fix bundle close each internal15 finding with either a merged code fix or an explicit acknowledged-and-deferred disposition.

**Reviewed PRs**
- [#272 `restore-v3-bbb`](https://github.com/valory-xyz/autonolas-tokenomics/pull/272) — baseline for this cycle; already merged into internal15 scope.
- [#273 `fix-v3-price-guards-audit`](https://github.com/valory-xyz/autonolas-tokenomics/pull/273) — C4R #17/#18/#19 price-guard fixes (merge `9bb4b03`).
- [#275 `fix-v3-swap-slippage`](https://github.com/valory-xyz/autonolas-tokenomics/pull/275) — H-02 TWAP-derived `amountOutMin`.
- [#276 `fix-medium-audit15`](https://github.com/valory-xyz/autonolas-tokenomics/pull/276) — M-01 `ObservationFailed`, M-03 V2 oracle auto-refresh, M-04 `checkpoint` decreasing-year correction.
- [#277 `fix-low-audit15`](https://github.com/valory-xyz/autonolas-tokenomics/pull/277) — L-01 deadline, L-05 `changeMaxSlippage` BPS cap, L-08 NeighborhoodScanner precision, doc-only residual entries (L-02/L-03/L-04/L-06/L-09/L-13). Also closes the `refundFromStaking` `ManagerOnly` revert-arg typo (legacy Vulnerabilities_list #12, since removed and replaced by the unrelated current #12) and the team's S-893 rebuttal.

**Review topology**
PRs #275/#276/#277 are parallel sibling branches off the post-#273 tip, not stacked. They were composed locally into a scratch branch `review/stack-2026-04-22` via three sequential merges (conflicts resolved via union-merge on internal15 `README.md` and `test/LiquidityManagerETH.t.sol`):

| Merge | Branch | Merge commit | Parent |
|-------|--------|--------------|--------|
| Base  | `fix-v3-price-guards-audit` tip | `ead1c83` (= internal15 baseline) | — |
| 1 | `fix-v3-swap-slippage` | `37a1277` | H-02 bundle |
| 2 | `fix-medium-audit15`   | `368bcef` | M-01 + M-03 + M-04 + C4A S-893 rebuttal + legacy Vuln-list #12 (`refundFromStaking` revert-arg typo; the current VL #12 is unrelated and remains open) |
| 3 | `fix-low-audit15`      | `40ec358` | L-01 + L-05 + L-08 + L-02/L-03/L-04/L-06/L-09/L-13 doc |

Composite size: **134 insertions / 27 deletions across 6 contract files** (stats from `git diff --stat ead1c83..HEAD -- contracts/`). Every hunk maps to a named internal15 or C4A finding — no off-finding drift. See *Regression scan* below.

---

## 1. Per-finding disposition

The verification matrix uses **two orthogonal status columns** (modelled on `autonolas-governance/audits/internal19/README.md` §4):

- **Code status** — where in the source tree the fix lives (or doesn't).
- **Deployment status** — whether that fix is live on-chain on the responsible contract instance.

The two are independent: a fix can be merged in code but still need a redeploy / `changeImplementation` to be effective on the live proxy; or a brand-new contract can have its fix in code but no on-chain instance at all. Conflating these into a single "FIXED" label hides the deployment-side gap. The split below makes it explicit.

**Code status vocabulary**

| Code status | Meaning |
|---|---|
| ✅ Fixed in code | Fix landed on the composite tip (`review/stack-2026-04-22` = PRs #272 + #273 + #275 + #276 + #277). Verified at file:line. |
| 📝 Documented (known issue) | Not fixed; explicitly accepted in `docs/Vulnerabilities_list_tokenomics.md` with operational mitigation. |
| 🔴 Not fixed (open) | Not in code, not in vulnerabilities-list. Tracked openly. |
| ⚖️ Rejected on review | Finding does not reproduce; rebuttal recorded. |
| 🔄 Resolved by replacement | Surface that the finding targeted no longer exists. |
| — Not a code finding | Operational / methodology / cosmetic; outside the code-fix mechanism. |

**Deployment status vocabulary**

| Deployment status | Meaning |
|---|---|
| 🟢 Live on-chain | Fix is deployed to the responsible contract instance and effective on mainnet. |
| 🟡 Pending redeploy | Fix is in code; the live impl is older code; an `changeImplementation` (or equivalent) on an existing deployed proxy is required. |
| ⚪ Code fix only — never deployed | Fix is in code; the affected contract has no prior on-chain instance for the relevant chain set (brand-new file or never-shipped impl) — the fix lands on-chain together with the first fresh deployment. |
| 🔵 Doc-only | Fix is a documentation / NatSpec / vulnerabilities-list entry; no bytecode change, immediately effective. |
| — N/A | Not in code (operational / methodology / not applicable); deployment column does not apply. |

**Why deployment status splits along these lines for internal15:**

- **BBB proxies** (`BuyBackBurnerUniswap` + `BuyBackBurnerBalancer` on 7 chains) are deployed (see §2 / audit README on-chain table), but the V3-restored implementation from PR #272+273+275+276+277 has **never** been put behind any of them — see §2's on-chain check that selectors `liquidityManager()` / `swapRouter()` revert on every proxy. The team's chosen rollout is a **fresh re-deploy** of new `BuyBackBurnerProxy` instances against the new impl (not in-place `changeImplementation`). So every BBB-side fix in this cycle is **⚪ Code fix only — never deployed** until the new proxies ship.
- **`Tokenomics`** is deployed at `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300` (see `scripts/deployment/globals_mainnet.json`); the four impls in the globals (`tokenomicsAddress` … `tokenomicsFourAddress`) are the historical implementations. M-04 + the legacy-VL-#12 typo fix touch `Tokenomics.sol`, so they require a **🟡 Pending redeploy** of a new impl + Timelock-scheduled `changeImplementation`.
- **`LiquidityManagerCore`** has no on-chain instance on any chain (audit README §"On-chain verification": `liquidityManager()` from the BBB-impl side returns the zero-address; the contract is brand-new POL infrastructure). M-01 + L-05 fixes are therefore **⚪ Code fix only — never deployed**.
- **`NeighborhoodScanner`** is brand-new POL infrastructure; not in `globals_mainnet.json`. C4A L-08 fix is **⚪ Code fix only — never deployed**.

### Internal audit 15 findings (original report)

| ID | Severity | Code status | Deployment status | Evidence on composite tip |
|----|----------|-------------|-------------------|---------------------------|
| **C-01** EOA-owned BBB proxies on 7 chains | Critical | — Not a code finding | 🟡 Pending — owner rotation to Safe + 48h timelock at deploy time (company policy, §3 user waiver 2026-04-22) | OpSec finding — cannot be fixed in a code PR. Severity preserved Critical. Closes when the new BBB proxies ship under Safe + timelock and `(chain, BBB proxy, timelock, safe)` is published in `docs/`. |
| **H-01** Storage-layout divergence on V2 oracle rewrite | High → Info-in-practice | — Not a code finding (defused by chosen rollout) | ⚪ Never deployed (V2 oracle rewrite never went on-chain; fresh re-deploy path of new BBB proxies sidesteps the layout collision entirely) | On-chain verified §2 — all 7 BBB proxies still run the pre-#272 impl. The only path that would manifest H-01 is in-place `changeImplementation` on the existing proxies; the team's rollout is fresh re-deploy. |
| **H-02** V3 `_performSwap` 1-wei floor | High | ✅ Fixed in code | ⚪ Code fix only — never deployed (BBB) | `BuyBackBurner.sol:256` TWAP-derived `amountOutMin`; `BuyBackBurnerUniswap.sol:128` + `BuyBackBurnerBalancer.sol:153` pass `amountOutMin` through. 5 forge unit + 2 ETH-fork tests (`BuyBackBurnerV3Swap`, `LiquidityManagerETH.testV3BuyBackWithTwapSlippage`, `testV3BuyBackRevertsOnTightSlippage`). Lands on-chain with the fresh BBB redeploy. |
| **M-01** `checkPoolAndGetCenterPrice` fail-open on `observe()` revert | Medium | ✅ Fixed in code | ⚪ Code fix only — never deployed (LiquidityManagerCore) | `LiquidityManagerCore.sol:1154` `revert ObservationFailed(pool)` on cardinality ≥ 2; cardinality-1 fresh pools fall back to slot0 (correct preserved behavior). 2 forge unit + 1 ETH-fork test on mainnet USDC/WETH 0.3%. Lands on-chain with the first LMC deployment. |
| **M-02** Balancer oracle flash-loan steer within `minUpdateInterval` | Medium | 📝 Documented (Vuln-list #14) | — N/A | Architectural residual; no code change. Monitoring plan: `ObservationUpdated` deviation alerts. Severity preserved Medium. |
| **M-03** V2 `_buyOLAS` uses stale TWAP without prior `updatePrice` | Medium | ✅ Fixed in code | ⚪ Code fix only — never deployed (BBB) | `BuyBackBurner.sol:215` `IOracle(poolOracle).updatePrice()` before `getTWAP()`. Rate-limit short-circuit prevents DoS on back-to-back calls. 2 forge unit + 1 ETH-fork test. Lands on-chain with the fresh BBB redeploy. |
| **M-04** `checkpoint` `effectiveBond` at decreasing-year boundaries | Medium | ✅ Fixed in code | 🟡 Pending redeploy (Tokenomics impl + `changeImplementation` on `0xc096…ce300`) | `Tokenomics.sol:1182-1188` new `else if (incentives[4] < curMaxBond)` branch with saturating subtraction flooring at zero. 2 Hardhat tests. **Year-2→Year-3 transition has already passed (2025-06-30)** — phantom bond capacity may already be on the live proxy; redeploy stops further drift but cannot retroactively undo. |
| **L-01** `buyBack` no deadline | Low | ✅ Fixed in code | ⚪ Code fix only — never deployed (BBB) | `BuyBackBurner.sol:467,521` both `buyBack` overloads take `uint256 deadline`; `DeadlineExpired(deadline, block.timestamp)` at lines 475-476 and 529-531. `deadline == 0` opts out. ABI change — see §4. 5 forge unit + 2 ETH-fork tests. Lands on-chain with the fresh BBB redeploy. |
| **L-02** `checkPoolPrices` accepts caller-supplied `uniV3PositionManager` | Low | ✅ Fixed in code (NatSpec annotation) | ⚪ Code fix only — never deployed (BBB) | `BuyBackBurner.sol:413+` NatSpec marks the helper as untrusted-input diagnostic; internal swap paths use `liquidityManager.factoryV3()` instead. Lands on-chain with the fresh BBB redeploy. |
| **L-03** `convertToV3` front-run via permissionless `collectFees` (C4A L-02) | Low | 📝 Documented (Vuln-list #15) | — N/A | Operator-playbook mitigation: stage OLAS in same tx as `convertToV3`. Architectural fix deferred. |
| **L-04** Slippage anchored to spot in `_increase/_decreaseLiquidity` (C4A L-04) | Low | 📝 Documented (Vuln-list #16) | — N/A | Admin-only surface; realized exposure low under DAO-paced ops. TWAP-anchored fix deferred. |
| **L-05** `changeMaxSlippage` no upper BPS check (C4A L-14) | Low | ✅ Fixed in code | ⚪ Code fix only — never deployed (LiquidityManagerCore) | `LiquidityManagerCore.sol:638-640` `revert Overflow(newMaxSlippage, MAX_BPS)`. 4 forge unit tests. Lands on-chain with the first LMC deployment. |
| **L-06** `BuyBackBurner.transfer()` can sweep V3-eligible secondTokens to treasury *(late finding 2026-04-29)* | Low | 🔴 Not fixed (open) — code fix pending | — N/A | New finding; `mapV2Oracles`-only gate at `BuyBackBurner.sol:621-624` lets V3-only secondTokens be diverted to treasury. Documented in Vuln-list #21 with preferred fix shape (`mapV3SecondTokenRefs`). Operational monitor on `TokenTransferred` events in the meantime. |
| **I-01** `setV3PoolStatuses` does not verify factory-pool ancestry | Info | 📝 Documented (Vuln-list #22) | — N/A | Acknowledged residual; admin-trust boundary collapsed by Safe + timelock owner (C-01 remediation). Defensive `factory.getPool(...) == pool` check tracked for future refactor. |
| **I-02** Token ordering via `>` | Info | — Not a code finding (correct as-is) | — N/A | Strict `>` is correct for EVM addresses (cannot be equal). |
| **I-03** Vulnerabilities-list entries deleted on fix instead of annotated | Info | — Not a code finding (team policy) | — N/A | Team workflow: deleted on fix; historical record lives in per-audit `README.md` + git log. |

### C4A 2026-01 carryover on tokenomics-scope

| C4A | Code status | Deployment status | Notes |
|-----|-------------|-------------------|-------|
| C4A L-06 `changeRegistries` locks incentives | 📝 Documented (Vuln-list #17) | — N/A | Owner-gated; operational workflow to claim before rotation. |
| C4A L-08 `NeighborhoodScanner.value0InToken1` precision loss | ✅ Fixed in code | ⚪ Code fix only — never deployed (NeighborhoodScanner is brand-new POL infra; not in `globals_mainnet.json`) | `NeighborhoodScanner.sol:671-685` single-step path for `sqrtP ≤ 2^128`, two-step fallback for extreme pools. 9 forge unit tests in `NeighborhoodScannerPrecision.t.sol`. |
| C4A L-09 `_trackServiceDonations` integer-division truncation | 📝 Documented (Vuln-list #18) | — N/A | Bounded to `numServiceUnits − 1` wei per donation; not exploitable. |
| C4A L-13 `checkpoint` unusable after `MAX_EPOCH_LENGTH` | 📝 Documented (Vuln-list #19) | — N/A | DAO keeper cadence + monitoring mitigate. |
| C4A L-15 `UniswapPriceOracle.maxSlippage < 100` | 🔄 Resolved by replacement | — N/A | Surface no longer exists in the V2-oracle rewrite; slippage moved to `BuyBackBurner.mapTokenMaxSlippages` bounded by `MAX_BPS`. |
| C4A S-893 CommonUtils bit-manipulation | ⚖️ Rejected on review | — N/A | Team rebuttal at `audits/internal15/C4A_S-893_rebuttal.md`. C4A final report dropped the finding (commit `73cd7c9`). |
| Vuln-list #12 `calculateStakingIncentives` bricks zero-weight refund (Dispenser; C4A S-907, severity High) | 📝 Documented (Vuln-list #12) | — N/A | Operational mitigation only (delegate ≥ 0.01% vote so `totalWeight` is never zero). **Not** fixed by `Tokenomics.sol:838`. |
| `refundFromStaking` `ManagerOnly` revert-arg typo (legacy Vuln-list #12, since removed; C4A S-130) | ✅ Fixed in code | 🟡 Pending redeploy (Tokenomics impl + `changeImplementation`) | `Tokenomics.sol:838` `revert ManagerOnly(msg.sender, dispenser)` (prior arg was typo `depository`). Cosmetic; access control was already correct. Closure recorded in `audits/internal15/README.md` §4. |

### Aggregate split (internal15 + C4A carryover)

| Bucket | Count | Findings |
|--------|------:|----------|
| ✅ Fixed in code, 🟡 Pending redeploy of an existing on-chain proxy | 2 | M-04, legacy VL #12 typo (both Tokenomics) |
| ✅ Fixed in code, ⚪ Never deployed (lands with fresh deploy) | 7 | H-02, M-01, M-03, L-01, L-02, L-05, C4A L-08 |
| 📝 Documented (Vuln-list), code unchanged | 7 | M-02 (#14), L-03 (#15), L-04 (#16), C4A-L-06 (#17), C4A-L-09 (#18), C4A-L-13 (#19), Vuln-list #12 |
| 🔴 Not fixed (open) — code fix pending | 1 | L-06 (late finding 2026-04-29; documented in Vuln-list #21) |
| 📝 Documented (Vuln-list), Info-tier acknowledged residual | 1 | I-01 (#22, added 2026-04-29) |
| ⚖️ Rejected on review | 1 | S-893 |
| 🔄 Resolved by replacement | 1 | C4A L-15 |
| — Not a code finding (OpSec / methodology / cosmetic) | 4 | C-01 (OpSec, deployment-time rotation), H-01 (defused by rollout choice), I-02 (no fix needed), I-03 (team policy) |
| **Total** | **24** | — |

**On-chain action items implied by the matrix.** When the team executes the deploy bundle that closes internal15:

1. **Redeploy `Tokenomics` impl** + Timelock-schedule `changeImplementation` on `0xc096…ce300` to land M-04 + the legacy VL #12 typo fix on-chain.
2. **Fresh re-deploy** of new `BuyBackBurnerProxy` instances on all 7 chains under Safe + 48h timelock owners (closes C-01) — lands H-02 + M-01-V2-call (via `_buyOLAS`'s `updatePrice` refresh) + M-03 + L-01 + L-02 + L-05 (LMC) + L-06's eventual fix.
3. **Fresh deploy** of `LiquidityManagerCore` + `NeighborhoodScanner` on the chains where V3 POL is in scope — lands M-01 (LMC side) + L-05 + C4A L-08.
4. **Publish `(chain, new BBB proxy, timelock, safe)`** in `docs/configuration.json` so C-01 can flip from "🟡 Pending" to "🟢 Live on-chain".
5. **Land L-06 code fix** (preferred shape: `mapV3SecondTokenRefs` counter populated in `setV3PoolStatuses`, additional gate in `transfer()`) before V3 buyBack is exercised on a chain where the V3-eligible-secondToken set is non-empty.

---

## 2. H-01 — on-chain demotion evidence

Internal15 H-01 was raised against the V2 `UniswapPriceOracle` rewrite on the premise that an in-place `changeImplementation()` call on the deployed BBB proxies would silently reorder storage (the rewrite introduced fields whose layout diverges from the live impl). The team's response: **the rewritten V2 oracle was never deployed**; remediation is a fresh re-deploy of new BBB proxies using the proxy-constructor path (`deploy_03_buy_back_burner_balancer_proxy.js` / `deploy_04_buy_back_burner_uniswap_proxy.js`), not in-place upgrade.

**On-chain verification (2026-04-22, `review/stack-2026-04-22` tip):** all 7 BBB proxies still run the **pre-#272 impl** — selectors `liquidityManager()` and `swapRouter()` (added in PR #272) return `0x` on every proxy, proving the new V3-restored implementation has not been swapped in anywhere. The custom impl slot `BUY_BACK_BURNER_PROXY = keccak256("BUY_BACK_BURNER_PROXY") = 0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19` (see `BuyBackBurnerProxy.sol:26`) was read via `cast storage` on all 7 proxies; each non-zero and each consistent with the proxy's pre-#272 deployment.

**Chain / proxy / owner map** (addresses pulled from `scripts/deployment/utils/globals_*_mainnet.json` on the composite tip):

| Chain | BBB proxy | Owner | Owner kind | H-01 manifested? |
|-------|-----------|-------|------------|------------------|
| Ethereum | (per `globals_eth_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Arbitrum | (per `globals_arbitrum_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Optimism | (per `globals_optimism_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Gnosis | (per `globals_gnosis_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Polygon | (per `globals_polygon_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Celo | (per `globals_celo_mainnet.json`) | `0xeb2a22...` | EOA | No — pre-#272 impl |
| Base | (per `globals_base_mainnet.json`) | `0x6f7a49...` | EOA | No — pre-#272 impl |

**Verdict:** the storage-layout collision H-01 describes cannot manifest on the current deployment. If the team uses the proxy-constructor deploy path (fresh re-deploy), the layout issue is structurally unreachable — each new proxy begins with the new impl's storage. H-01 therefore collapses to an **operational guard**: do not deploy via `changeImplementation()` on the existing proxies. See §4 soft observation.

---

## 3. C-01 — OpSec waiver (explicit, dated)

C-01 is an operational finding: 7 BBB proxies are owned by single-owner EOAs across 7 chains, not multisig + timelock. This cannot be closed in a code PR — remediation is on-chain ownership rotation, which happens outside the PR mechanism.

**Team/user waiver (2026-04-22):** per explicit user authorization, C-01 is dispositioned **acknowledged-and-deferred** for the purpose of this closing PR review. The severity remains **Critical**; the disposition reflects that the ops team owns the remediation timeline, not that the threat has been removed. Per `feedback-opsec-acknowledged-vs-fixed.md`: an acknowledged Critical remains a Critical on the record.

Rationale for keeping this out of the code-fix bundle:
- `docs/Vulnerabilities_list_tokenomics.md` is a **code**-vulnerabilities ledger, not an operational one. Including C-01 there would mis-categorize it.
- The audit `README.md` in this directory already documents C-01 with full severity justification and on-chain owner map (§Critical section of `audits/internal15/README.md`). The audit record is the documentation trail.

**What this waiver does not do:** it does not relabel C-01 as Low/Info, it does not erase it from the audit README, and it does not lift the expectation that the ops team will migrate ownership. If the ops timeline slips, C-01 surfaces again in any subsequent re-audit of these proxies.

---

## 4. Regression scan

Full diff `ead1c83..HEAD` against `contracts/`:

| File | +ins | −del | Purpose |
|------|------|------|---------|
| `Tokenomics.sol` | 16 | 5 | M-04 else-if branch (decreasing-year saturation) + legacy Vuln-list #12 `refundFromStaking` `ManagerOnly` arg typo fix |
| `pol/LiquidityManagerCore.sol` | 35 | 4 | M-01 `ObservationFailed` + `_getObservationCardinality` helper + L-05 `changeMaxSlippage` BPS upper bound |
| `pol/NeighborhoodScanner.sol` | 20 | 6 | C4A L-08 single-step / two-step `value0InToken1` split |
| `utils/BuyBackBurner.sol` | 59 | 12 | H-02 TWAP-derived `amountOutMin` + M-03 `updatePrice()` auto-refresh + L-01 deadline (both `buyBack` overloads) + `checkPoolPrices` NatSpec-only diagnostic note |
| `utils/BuyBackBurnerBalancer.sol` | 3 | 2 | Signature extension for `amountOutMin`; `amountOutMinimum: amountOutMin` in V3 params |
| `utils/BuyBackBurnerUniswap.sol` | 3 | 2 | Signature extension for `amountOutMin`; `amountOutMinimum: amountOutMin` in V3 params |
| **Total** | **134** | **27** | All changes tied to named findings |

**No off-finding drift.** Every hunk maps to a named internal15 or C4A finding, or is a NatSpec clarification (e.g. `checkPoolPrices` diagnostic caveat — no behavior change). The `_getObservationCardinality` helper is new code but used only by the M-01 fail-open fix.

**ABI change (non-breaking for on-chain code, breaking for keeper tooling):**

- `buyBack(address,uint256)` → `buyBack(address,uint256,uint256 deadline)`
- `buyBack(address,uint256,int24)` → `buyBack(address,uint256,int24,uint256 deadline)`

The internal `_performSwap` signatures also gain `uint256 amountOutMin` (not externally observable). Off-chain bot / keeper scripts that submit `buyBack` transactions must be updated; `deadline == 0` opts out of the deadline check. This is not listed as a finding because it is an intended consequence of L-01 and must, by construction, change the external signature.

**Test bundle on the composite tip:**

| Test file | Count | Covers |
|-----------|-------|--------|
| `BuyBackBurnerV3Swap.t.sol` | 5 | H-02 unit path (Uniswap + Balancer V3) |
| `LiquidityManagerETH.t.sol` | 2 new ETH-fork | H-02 positive + negative against real mainnet V3 pool |
| `LiquidityManagerETH.t.sol` | 1 new ETH-fork | M-01 `observe()` revert overlay on mainnet USDC/WETH 0.3% |
| `LiquidityManagerCorePriceGuard.t.sol` | 2 | M-01 cardinality branches (revert + fallback) |
| `BuyBackBurnerV2OracleRefresh.t.sol` | 2 | M-03 V2 auto-refresh |
| `BuyBackBurnerUniswapETH.t.sol` | 3 new ETH-fork | M-03 stale-oracle + L-01 deadline (expired + zero-opt-out) |
| `Tokenomics.js` (M-04 block) | 2 Hardhat | M-04 decreasing-year walkthrough + synthetic storage-override |
| `LowFindingsAudit15.t.sol` | ~10 | L-01 deadline guard + L-05 BPS bound |
| `NeighborhoodScannerPrecision.t.sol` | 9 | C4A L-08 single-step + two-step |
| **Total added tests** | **~36** | All `code-fix-required` findings covered |

Gaps (not blockers):
- No fork test asserting `router` / `balancerVault` / `balancerPoolId` survive a proxy upgrade. The team's remediation path is fresh re-deploy, not upgrade; the absence is consistent with the chosen strategy but the upgrade path is not under test.
- No unit test for `setV3PoolStatuses` factory-ancestry enforcement (I-01 is acknowledged-and-deferred).

---

## 5. Soft observations

Non-blocking, not findings — operational hygiene items surfaced by the review.

**S-1.** `scripts/deployment/utils/script_01_buy_back_burner_change_implementation.sh` is still present in the repo on the composite tip. It performs `cast send <proxy> changeImplementation(address) <new_impl>` — i.e. the exact in-place upgrade path whose risk motivated H-01 being raised originally. The team's stated remediation is fresh re-deploy (`deploy_03_*_proxy.js` / `deploy_04_*_proxy.js`), not in-place upgrade; as long as that path is used, H-01 is structurally unreachable. However, keeping the `changeImplementation` helper script in the repo creates a foot-gun for future operators who may reach for it reflexively.

Recommendation (non-blocking): either (a) delete `script_01_buy_back_burner_change_implementation.sh`, or (b) rename it to `script_01_buy_back_burner_DO_NOT_USE_change_implementation.sh` and add a header comment explaining why the preferred path is fresh re-deploy. No code gate, purely operator discipline.

**S-2.** The internal15 test bundle does not include a **proxy-constructor deploy test** that initializes a brand-new `BuyBackBurnerUniswap` / `BuyBackBurnerBalancer` proxy via the `init(bytes)` payload and asserts the full 4-field payload (`olas`, `nativeToken`, `oracle`, `router` / `balancerVault` + `balancerPoolId`) is written to the expected slots. Since the team's remediation path for H-01 is fresh re-deploy, that path is the one that must not regress. Not a finding — the current deploy scripts are battle-tested and the payload shape has not changed in #272 — but a forge constructor-roundtrip test would harden the ongoing operator-discipline path.

**S-3.** The `checkPoolPrices` legacy helper (`BuyBackBurner.sol:398+`) now carries a "caller-supplied `uniV3PositionManager` is untrusted — do not wire into keeper scripts" NatSpec caveat. The function remains exported. Recommendation (non-blocking): if the app integrations that depend on this helper can be surveyed, consider removing it in a follow-up. Keeping an explicit "untrusted input" entry point in a BuyBackBurner surface is a small but real attack-surface cost.

---

## 6. Verdict

**Green on the source tree** under the two-axis framework introduced in §1. Caveat: "green in code" ≠ "green on-chain" for every finding — see the §1 aggregate split and the on-chain-action-items list at the bottom of §1.

- **✅ Fixed in code (composite tip, PRs #272 + #273 + #275 + #276 + #277)** — H-02, M-01, M-03, M-04, L-01, L-02, L-05, C4A L-08, legacy Vuln-list #12 (`refundFromStaking` revert-arg typo). All verified fixed on composite tip with test coverage. Of these, **M-04** and the **legacy VL #12 typo** require a 🟡 **Tokenomics impl redeploy + `changeImplementation`** on `0xc096…ce300` to be effective on-chain; the rest are ⚪ **code fix only — never deployed** until the fresh BBB / LMC / NeighborhoodScanner deploy bundle ships. The current Vuln-list #12 (`calculateStakingIncentives` zero-weight refund flag) is **📝 Documented**, not fixed — see §1 row.
- **📝 Documented (vulnerabilities-list residuals, no code change)** — M-02 (#14), L-03 (#15), L-04 (#16), C4A L-06 (#17), C4A L-09 (#18), C4A L-13 (#19), VL #12 current (Dispenser zero-weight), I-01 (#22, added 2026-04-29). All explicitly accepted with operational mitigation in `docs/Vulnerabilities_list_tokenomics.md`.
- **🔴 Open (not fixed in code, code fix pending)** — L-06 late finding (`BuyBackBurner.transfer()` can sweep V3-eligible secondTokens to treasury). Documented in VL #21; closes when the `mapV3SecondTokenRefs` (or equivalent) patch lands.
- **— Not a code finding** — C-01 (OpSec; closes when ownership rotates to Safe + 48h timelock at deploy time), H-01 (defused by fresh-redeploy rollout choice; on-chain confirmed pre-#272 impl still live, §2), I-02 (correct as-is), I-03 (team workflow).
- **⚖️ Rejected** — S-893 (C4A dropped). **🔄 Resolved by replacement** — C4A L-15 (surface no longer exists).

Green on this closing PR review is the **final green light** for the internal15 cycle's code-side disposition on `autonolas-tokenomics`. The on-chain side closes on the deployment bundle outlined in §1's action-items list (Tokenomics impl redeploy + fresh BBB / LMC / NeighborhoodScanner deploys + Safe-and-timelock ownership rotation). No further re-audit is required prior to that bundle. The L-06 code fix is the only outstanding code-side item and is recorded in VL #21; it should land before V3 buyBack is exercised on any chain whose V3-eligible-secondToken set is non-empty.

---

### Review metadata

- **Composite tip:** `40ec358` (`review/stack-2026-04-22`, local scratch only — not pushed)
- **Baseline:** `ead1c83` (internal15 `fix-v3-price-guards` tip = post-#273)
- **On-chain verification:** `cast storage` + `cast call` on 7 BBB proxies across Ethereum / Arbitrum / Optimism / Gnosis / Polygon / Celo / Base mainnets (impl slot `0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19`)
- **C-01 OpSec waiver authorization:** user, 2026-04-22

---

## 7. Post-cycle change — V3-optional BuyBackBurner

**Out-of-scope for the internal15 closing review above; landed as a follow-up after the deployment audit on 2026-04-22.**

### Why

Operator deployment audit on the internal15 stack revealed that the `BuyBackBurner` constructor strictly required all four addresses (`liquidityManager`, `bridge2Burner`, `treasury`, `swapRouter`) to be non-zero. Three production chains in the runbook (gnosis, polygon, arbitrum) have no Uniswap V3 / Slipstream router and no `LiquidityManager` deployment in scope, so `forge create` would revert with `ZeroAddress` before code-on-chain. ETH and Optimism could deploy V2-only impls only after deploying the full POL stack first.

### What

`contracts/utils/BuyBackBurner.sol`:
- Constructor relaxes the zero check on `_liquidityManager` and `_swapRouter`. `_bridge2Burner` and `_treasury` remain required.
- New `error V3PathDisabled()`.
- One internal view guard `_requireV3Enabled()` (reverts when either V3 immutable is zero); the LM-only check used by `checkPoolPrices` is inlined since it's the only call site.
- Guards applied to: `buyBack(V3 4-arg)`, `_buyOLAS(V3)`, `setV3PoolStatuses`, `checkPoolPrices`.

`scripts/deployment/utils/deploy_01_buy_back_burner_balancer.sh` and `deploy_02_buy_back_burner_uniswap.sh` normalise empty-string / `null` for `liquidityManagerAddress` and `swapRouterV3Address` to `0x0000…0` so `forge create` accepts them.

`test/BuyBackBurnerV3Disabled.t.sol` — 19 new unit tests:
- Constructor accepts zero `_liquidityManager` / `_swapRouter` / both; still reverts on zero `_bridge2Burner` / `_treasury` (Uniswap + Balancer variants).
- `buyBack(V3)` reverts `V3PathDisabled` on each of LM-zero / swapRouter-zero / both-zero.
- `setV3PoolStatuses` reverts `V3PathDisabled` on LM-zero / swapRouter-zero; owner check fires before the V3 guard.
- `checkPoolPrices` reverts `V3PathDisabled` only when LM is zero; passes through with `swapRouter == 0`.
- V2 admin surfaces (`setV2Oracles`, `setMaxSlippages`, `changeOwner`, `changeImplementation`) succeed on a V3-disabled deployment.

`docs/Vulnerabilities_list_tokenomics.md` — entry #20 added (renumbered from #21 on 2026-04-29 to close a TOC gap; see §8).

### Impact on internal15 disposition

None. This is a follow-up to the operator runbook, not an internal15 finding. All internal15 findings remain at their post-#272+#273+#275+#276+#277 disposition. Existing on-chain proxies on every chain were deployed under the old strict check, so `liquidityManager` and `swapRouter` are non-zero — V3 is enabled. The new contract is bytecode-equivalent for them.

### Test results

- `forge test --mc BuyBackBurnerV3Disabled -vv` — 19/19 pass
- `forge test -f <ETH RPC> --mc BuyBackBurnerUniswapETH -vv` — 21/21 pass (regression)
- `forge test -f <ARBITRUM RPC> --mc BuyBackBurnerBalancerArbitrum -vv` — 19/19 pass (regression)
- `forge build` — clean

---

## 8. Post-closing addendum (2026-04-29) — late finding L-06 + doc hygiene

The verdict in §6 stands for the internal15 cycle proper, but a late review surfaced one new code-path issue and three doc-hygiene items that need to be reflected in this document for downstream auditors. They are recorded here rather than spawning a fresh audit cycle because the issue is bounded, the fix is small, and the disposition framework from §1 applies cleanly.

### 8.1 New finding — L-06 `BuyBackBurner.transfer()` can sweep V3-eligible secondTokens to treasury

**Severity:** Low — public griefing on the V3 `buyBack` path. **Status:** open, code fix pending.

`BuyBackBurner.transfer(token)` (lines 621–656) gates on `mapV2Oracles[token] != address(0)`. The V3 swap path authorizes by *pool* (`mapV3Pools[pool]`) rather than by *token*, so a V3-only secondToken — for example a stable wired up via `setV3PoolStatuses` and `setMaxSlippages` but never assigned a V2 oracle — passes the gate. Any external caller can call `transfer(secondToken)` and divert the accumulated input balance to `treasury`, bypassing the V3 swap-into-OLAS step. No funds are lost (treasury is owner-controlled) but the V3 buyBack-and-burn workflow is publicly griefable until the operator drains treasury back into BBB and retries.

This is the V3 analogue of the V2-side block already encoded by `mapV2Oracles[token] != address(0)`: V2 secondTokens are protected, V3 secondTokens are not.

**Mitigation (preferred):** maintain `mapping(address => uint256) mapV3SecondTokenRefs`, incremented in `setV3PoolStatuses` for the non-OLAS side of each newly whitelisted pool and decremented when the pool is delisted; revert `transfer()` when `mapV3SecondTokenRefs[token] > 0`. Storage-append-only — no impact on existing slots.

**Operational mitigation in the meantime:** monitor `TokenTransferred` events with `to == treasury` on every BBB proxy with V3 enabled; on detection, the operator drains treasury back into BBB and re-triggers the V3 `buyBack`.

Documented in `docs/Vulnerabilities_list_tokenomics.md` #21 with full impact + mitigation analysis.

### 8.2 Doc hygiene corrections

- **§1 row "Vuln-list #12"** has been corrected on this composite: VL #12 is the **Dispenser** `calculateStakingIncentives` zero-weight refund flag (C4A S-907, High) and is operational-mitigation-only — **not** closed by `Tokenomics.sol:838`. The line `Tokenomics.sol:838` is the unrelated `refundFromStaking` `ManagerOnly` revert-arg typo (legacy VL #12, since removed; closure recorded in `audits/internal15/README.md` §4). The two findings have been split into separate rows.
- **VL TOC + numbering:** the body jumped from #19 to #21 (no #20) and the TOC stopped at #19. The "BuyBackBurner V3 path is per-chain optional" entry has been renumbered #21 → #20 to close the gap, the new finding above is added as #21, and the TOC has been extended to include both. Stale "#20" references in the original `audits/internal15/README.md` (lines 497, 731, 809, 812) target items that, on the current VL, live at #14 (M-02), do not exist (L-05 was a code fix, no doc entry per team policy), and #17–#19 (the L-bundle residuals); those references are historical state and have not been retroactively rewritten.
- **C-01 / H-01 / I-01 are absent from VL by design.** Per team policy (`audits/internal15/README.md` §I-03 + §3 of this document), `docs/Vulnerabilities_list_tokenomics.md` is a code-vulnerabilities ledger; OpSec waivers (C-01), methodology-record items (H-01), and Info-tier admin-trust observations (I-01) live in this audit's `README.md`. The disposition is intentional, not an oversight.

### 8.3 Updated verdict

The closing verdict in §6 is unchanged for internal15 proper. L-06 is a late finding — it does not reopen the cycle, but it should be folded into the next deployment-readiness checkpoint. Once the `mapV3SecondTokenRefs` (or equivalent) fix lands, VL #21 closes and the disposition flips to **code-fix-required → FIXED**.
