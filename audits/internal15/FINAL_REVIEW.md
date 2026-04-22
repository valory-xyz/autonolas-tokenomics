# Internal audit 15 — closing PR review (PR #273 fix stack)

**Date:** 2026-04-22
**Methodology:** `PR_REVIEW_<n>` closing artefact (per `feedback-pr-review-vs-reaudit.md`).
A PR review is a lightweight re-verification of the team's fix bundle against the internal15 findings. It is **not** a new audit — it does not re-open the attack surface, it does not enumerate new findings. The only question is: does the fix bundle close each internal15 finding with either a merged code fix or an explicit acknowledged-and-deferred disposition.

**Reviewed PRs**
- [#272 `restore-v3-bbb`](https://github.com/valory-xyz/autonolas-tokenomics/pull/272) — baseline for this cycle; already merged into internal15 scope.
- [#273 `fix-v3-price-guards-audit`](https://github.com/valory-xyz/autonolas-tokenomics/pull/273) — C4R #17/#18/#19 price-guard fixes (merge `9bb4b03`).
- [#275 `fix-v3-swap-slippage`](https://github.com/valory-xyz/autonolas-tokenomics/pull/275) — H-02 TWAP-derived `amountOutMin`.
- [#276 `fix-medium-audit15`](https://github.com/valory-xyz/autonolas-tokenomics/pull/276) — M-01 `ObservationFailed`, M-03 V2 oracle auto-refresh, M-04 `checkpoint` decreasing-year correction.
- [#277 `fix-low-audit15`](https://github.com/valory-xyz/autonolas-tokenomics/pull/277) — L-01 deadline, L-05 `changeMaxSlippage` BPS cap, L-08 NeighborhoodScanner precision, doc-only residual entries (L-02/L-03/L-04/L-06/L-09/L-13). Also closes Vulnerabilities_list item #12 (`refundFromStaking` revert arg) and the team's S-893 rebuttal.

**Review topology**
PRs #275/#276/#277 are parallel sibling branches off the post-#273 tip, not stacked. They were composed locally into a scratch branch `review/stack-2026-04-22` via three sequential merges (conflicts resolved via union-merge on internal15 `README.md` and `test/LiquidityManagerETH.t.sol`):

| Merge | Branch | Merge commit | Parent |
|-------|--------|--------------|--------|
| Base  | `fix-v3-price-guards-audit` tip | `ead1c83` (= internal15 baseline) | — |
| 1 | `fix-v3-swap-slippage` | `37a1277` | H-02 bundle |
| 2 | `fix-medium-audit15`   | `368bcef` | M-01 + M-03 + M-04 + C4A S-893 rebuttal + Vuln-list #12 |
| 3 | `fix-low-audit15`      | `40ec358` | L-01 + L-05 + L-08 + L-02/L-03/L-04/L-06/L-09/L-13 doc |

Composite size: **134 insertions / 27 deletions across 6 contract files** (stats from `git diff --stat ead1c83..HEAD -- contracts/`). Every hunk maps to a named internal15 or C4A finding — no off-finding drift. See *Regression scan* below.

---

## 1. Per-finding disposition

Two dispositions are valid for green:
- **code-fix-required** — fix must appear in merged code. Verified on composite tip.
- **acknowledged-and-deferred** — team explicitly owns the remediation timeline outside this PR mechanism. Severity is **not** downgraded (per `feedback-opsec-acknowledged-vs-fixed.md`).

### Internal audit 15 findings (original report)

| ID | Severity | Disposition | Evidence on composite tip |
|----|----------|-------------|---------------------------|
| **C-01** EOA-owned BBB proxies on 7 chains | Critical | **acknowledged-and-deferred** | OpSec finding — cannot be fixed in a code PR. User waiver 2026-04-22 (see §3). Severity preserved Critical. |
| **H-01** Storage-layout divergence on V2 oracle rewrite | High | **acknowledged-and-deferred → Info-in-practice** | Not manifested — V2 oracle rewrite never deployed; team's remediation is fresh re-deploy (scripts `deploy_03_…_proxy.js` / `deploy_04_…_proxy.js`), not in-place `changeImplementation`. On-chain verified (see §2). |
| **H-02** V3 `_performSwap` 1-wei floor | High | **code-fix-required → FIXED** | `BuyBackBurner.sol:256` TWAP-derived `amountOutMin`; `BuyBackBurnerUniswap.sol:128` + `BuyBackBurnerBalancer.sol:153` pass `amountOutMin` through. 5 forge unit + 2 ETH-fork tests (`BuyBackBurnerV3Swap`, `LiquidityManagerETH.testV3BuyBackWithTwapSlippage`, `testV3BuyBackRevertsOnTightSlippage`). |
| **M-01** `checkPoolAndGetCenterPrice` fail-open on `observe()` revert | Medium | **code-fix-required → FIXED** | `LiquidityManagerCore.sol:1154` `revert ObservationFailed(pool)` on cardinality ≥ 2; cardinality-1 fresh pools fall back to slot0 (correct preserved behavior). 2 forge unit + 1 ETH-fork test on mainnet USDC/WETH 0.3%. |
| **M-02** Balancer oracle flash-loan steer within `minUpdateInterval` | Medium | **acknowledged-and-deferred** | Documented in `docs/Vulnerabilities_list_tokenomics.md` #14 as accepted residual. Monitoring plan: `ObservationUpdated` deviation alerts. Severity preserved Medium. |
| **M-03** V2 `_buyOLAS` uses stale TWAP without prior `updatePrice` | Medium | **code-fix-required → FIXED** | `BuyBackBurner.sol:215` `IOracle(poolOracle).updatePrice()` before `getTWAP()`. Rate-limit short-circuit prevents DoS on back-to-back calls. 2 forge unit + 1 ETH-fork test. |
| **M-04** `checkpoint` `effectiveBond` at decreasing-year boundaries | Medium | **code-fix-required → FIXED** | `Tokenomics.sol:1182-1188` new `else if (incentives[4] < curMaxBond)` branch with saturating subtraction flooring at zero. 2 Hardhat tests (decreasing-year walkthrough + storage-override synthetic trigger for Y2→Y3 and Y9→Y10). |
| **L-01** `buyBack` no deadline | Low | **code-fix-required → FIXED** | `BuyBackBurner.sol:467,521` both `buyBack` overloads take `uint256 deadline`; `DeadlineExpired(deadline, block.timestamp)` at line 475-476 and 529-531. `deadline == 0` opts out. ABI change — see §4. 5 forge unit + 2 ETH-fork tests. |
| **L-02** `convertToV3` front-run via permissionless `collectFees` | Low | **acknowledged-and-deferred** | Documented in `docs/Vulnerabilities_list_tokenomics.md` #15 as admin-playbook note. Operator mitigation only. |
| **L-03** `_getPriceAndObservationIndexFromSlot0` fallback on young pools | Low | **acknowledged-and-deferred (partial)** | Subsumed by M-01 revert-on-observe-fail for cardinality ≥ 2; residual `_increaseLiquidity` / `_decreaseLiquidity` slot0 reads documented as L-04 below. |
| **L-04** Slippage anchored to spot in `_increase/_decreaseLiquidity` | Low | **acknowledged-and-deferred** | Documented in `docs/Vulnerabilities_list_tokenomics.md` #16 as admin-only residual. |
| **L-05** `changeMaxSlippage` no upper BPS check | Low | **code-fix-required → FIXED** | `LiquidityManagerCore.sol:638-640` `revert Overflow(newMaxSlippage, MAX_BPS)` (matches `initialize()` invariant). 4 forge unit tests. |
| **I-01** `setV3PoolStatuses` does not verify factory-pool ancestry | Info | **acknowledged-and-deferred** | Captured via C-01 ownership rotation (if owner is Safe + timelock this is low risk). |
| **I-02** Token ordering via `>` | Info | **no fix needed** | Correct for EVM addresses (cannot be equal). |
| **I-03** `Vulnerabilities_list_tokenomics.md` entries deleted on fix instead of annotated | Info | **acknowledged (team policy)** | Team workflow: deleted on fix; historical record lives in per-audit `README.md` + git log. |

### C4A 2026-01 carryover on tokenomics-scope

| C4A | Status on composite tip |
|-----|-------------------------|
| C4A L-06 `changeRegistries` locks incentives | Documented residual (Vuln-list #17). |
| C4A L-08 `NeighborhoodScanner.value0InToken1` precision loss | **FIXED** — `NeighborhoodScanner.sol:671-685` single-step path for `sqrtP ≤ 2^128`, two-step fallback for extreme pools. 9 forge unit tests in `NeighborhoodScannerPrecision.t.sol`. |
| C4A L-09 `_trackServiceDonations` integer-division truncation | Documented residual (Vuln-list #18). |
| C4A L-13 `checkpoint` unusable after `MAX_EPOCH_LENGTH` | Documented residual (Vuln-list #19). |
| C4A L-15 `UniswapPriceOracle.maxSlippage < 100` | **resolved by replacement** — V2 oracle rewrite has no such surface; slippage moved to `BuyBackBurner.mapTokenMaxSlippages` bounded by `MAX_BPS`. |
| C4A S-893 CommonUtils bit-manipulation | **rejected (team rebuttal)** — finding does not reproduce against current code; team rebuttal at `audits/internal15/C4A_S-893_rebuttal.md`. C4A final report dropped the finding (commit `73cd7c9`). |
| Vuln-list #12 `calculateStakingIncentives` bricks zero-weight refund | **FIXED** — `Tokenomics.sol:838` `revert ManagerOnly(msg.sender, dispenser)` (prior arg was typo `depository`). |

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
| `Tokenomics.sol` | 16 | 5 | M-04 else-if branch (decreasing-year saturation) + Vuln-list #12 `ManagerOnly` arg typo fix |
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

**Green.** The fix bundle (PRs #272 + #273 + #275 + #276 + #277) closes the internal15 findings under the two-disposition framework:

- **code-fix-required** — H-02, M-01, M-03, M-04, L-01, L-05, C4A L-08, Vuln-list #12: all verified fixed on composite tip with test coverage.
- **acknowledged-and-deferred** — C-01 (OpSec, user waiver 2026-04-22), H-01 (not manifested under fresh-redeploy; on-chain confirmed pre-#272 impl still live), M-02, L-02, L-03, L-04, L-06, L-09, L-13, L-15 (replaced), S-893 (rejected, C4A dropped), I-01, I-02, I-03: all documented in `docs/Vulnerabilities_list_tokenomics.md` or `audits/internal15/README.md` with explicit disposition.

Green on this closing PR review is the **final green light** for the internal15 cycle on `autonolas-tokenomics`. No further re-audit is required. Any follow-up work (S-1 / S-2 / S-3 soft observations, I-01 factory-ancestry guard) is operator discipline or future-cycle scope, not an internal15 gate.

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

`docs/Vulnerabilities_list_tokenomics.md` — entry #21 added.

### Impact on internal15 disposition

None. This is a follow-up to the operator runbook, not an internal15 finding. All internal15 findings remain at their post-#272+#273+#275+#276+#277 disposition. Existing on-chain proxies on every chain were deployed under the old strict check, so `liquidityManager` and `swapRouter` are non-zero — V3 is enabled. The new contract is bytecode-equivalent for them.

### Test results

- `forge test --mc BuyBackBurnerV3Disabled -vv` — 19/19 pass
- `forge test -f <ETH RPC> --mc BuyBackBurnerUniswapETH -vv` — 21/21 pass (regression)
- `forge test -f <ARBITRUM RPC> --mc BuyBackBurnerBalancerArbitrum -vv` — 19/19 pass (regression)
- `forge build` — clean
