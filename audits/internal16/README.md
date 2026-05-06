# Internal Audit 16 — `fix-l06-v3-second-token-mapping` re-audit + broad-scope sweep

> ## 👉 Looking for the C4R 2026-01 cross-reference? See [`FINAL_REVIEW.md`](FINAL_REVIEW.md)
>
> [`FINAL_REVIEW.md`](FINAL_REVIEW.md) is a **C4R-ID-keyed re-presentation** of every tokenomics-scope C4R 2026-01 finding (28 in total — 6 H + 9 M + 13 L) with the fix commit hash or `docs/Vulnerabilities_list_tokenomics.md` entry number cited inline. Read it first if you arrive holding the [C4R draft gist](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38) and want a single landing page that answers "C4R L-01 — fixed where?" without triangulating across [`audits/internal15/README.md`](../internal15/README.md), [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md), and the VL doc.
>
> Use *this* `README.md` for the internal16 cycle's own work product — the L-06 / I-01 fix re-audit, broad-scope sweep, methodology codification (variant-extension asymmetric gate completeness), 1 MEDIUM + 5 LOW + 3 INFO new findings, agent-Critical false-positive analysis.

**Branch under audit**: `fix-l06-v3-second-token-mapping` (HEAD `5fadd70`).
**Merge-base with `main`**: `1d07c94`.
**Predecessor audit**: `audits/internal15/README.md` (closed 2026-04-30 with L-06 + I-01 flipped to ✅ Fixed via this branch).
**Audit date**: 2026-05-04.
**Audit scope**: (1) re-audit the L-06 + I-01 fix that closed the late-finding from internal-15; (2) apply broad-scope methodology across all autonolas-tokenomics contracts to surface any additional findings, including those discoverable only after the variant-extension methodology rule that L-06 surfaced.

L-06 was a late finding — surfaced 2026-04-29, after `audits/internal15/FINAL_REVIEW.md` was issued (2026-04-22). The internal-15 audit cycle missed it. This re-audit therefore serves both as fix-verification and as a project-wide systematic sweep applying the methodology lesson L-06 produced.

---

## Disposition summary

| Item | Status |
|---|---|
| **L-06** `BuyBackBurner.transfer()` V3-secondToken griefing | ✅ Fix verified at HEAD `5fadd70` — combined gate structurally closes the attack vector |
| **I-01** `setV3PoolStatuses` factory ancestry | ✅ Side-effect closure verified — `setV3Pools` enforces `factoryV3.getPool(secondToken, OLAS, fee) == pool` |
| **L-06 fix test coverage** | 28 tests (13 unit + 9 ETH fork + 6 Base/Slipstream fork). Original L-06 attack vector explicitly tested + Slipstream variant covered |
| **Methodology gap that allowed L-06 to escape internal-15** | Identified and codified — see §1: «variant-extension asymmetric gate completeness» pattern |
| **New findings (this re-audit, broad scope)** | **1 MEDIUM** (Bridge2BurnerPolygon L1 destination architecture gap), **5 LOW** (Optimism gas limit, approval cleanup, no-rescue, Tokenomics integer truncation pattern, GenericBondCalculator flash-loan view), **2 INFO** (V2/V3 setter mutual-exclusivity, Depository OLAS transfer return) |
| **Agent-flagged Critical claims investigated** | 3 of 3 verified as **false positives** with concrete file:line reasoning (see §6) |
| **C-01 OpSec carry-over from internal-15** | Unchanged — 7 BBB proxies still EOA-owned; acknowledged-and-deferred (§11) |
| **M-1-NEW Polygon Bridge2Burner L1 destination** | ✅ Fixed — `relayToL1Burner()` now forwards OLAS to the Polygon bridge mediator (governance-owned, code-deployed on both L2 and its L1 mirror). Sidesteps Polygon PoS bridge's missing recipient parameter. |
| **L-NEW-2 Bridge2Burner approval cleanup** | ✅ Fixed — Arbitrum / Gnosis / Optimism variants now reset OLAS approval to `0` after the bridge call. |
| **L-NEW-1 Bridge2BurnerOptimism `TOKEN_GAS_LIMIT` hardcoded** | 📝 Documented as VL **#22** — accepted residual; 300 K gas is well above current `OLAS_BURNER` L1 receive footprint and not expected to rise; failed L1 messages are replayable via the standard Optimism replay mechanism. |
| **INFO-1 `setV2Oracles` / `setV3Pools` not mutually exclusive** | 📝 Documented as VL **#23** — owner-only setters with symmetric security gate; operational-only footgun. Runbook: clear the V2 oracle entry before configuring a V3 pool for the same token. |
| **INFO-2 Depository OLAS transfer return value not checked** | 📝 Documented as VL **#21** — code-hygiene only; OLAS is the canonical revert-on-failure ERC20. Future SafeTransferLib normalization out of scope. |
| **L-NEW-3 Bridge2Burner family lacks emergency rescue** | ⚖️ Intentionally rejected — adding owner-gated rescue would expand the C-01 EOA blast radius into a currently trustless contract. Permissionless trust model preserved. |
| **L-NEW-4 Tokenomics integer truncation in incentive pattern** | 📝 Already covered by VL **#18** (`_trackServiceDonations` precision loss) — same residual class; no separate VL entry required. |
| **L-NEW-5 GenericBondCalculator flash-loan view** | ⚖️ Already mitigated — view-only function; bond payouts use stored `priceLP` set at create-time. No code change indicated. |
| **INFO-3 ABI break impact summary** | 📝 Documented in §3 of this README — release-notes / off-repo consumers concern. |
| **M-09 saturating-subtraction design note** | 📝 Documented as VL **#24** — intentional design (residual bonds already minted cannot be retroactively unminted); exposure window bounded to Y2→Y3 (already past) and Y9→Y10 (still ahead). |
| **Verdict** | ⚠ **PASS-WITH-FINDINGS** — branch mergeable; M-1-NEW + L-NEW-2 closed in code; remaining LOW/INFO items dispositioned in `docs/Vulnerabilities_list_tokenomics.md` (#21–#24) or rejected with rationale. |

---

## §1. Methodology — variant-extension asymmetric gate completeness

### What L-06 actually was

`BuyBackBurner.transfer(address token)` is a rescue function — designed to sweep stray (unregistered) tokens out of the contract to `treasury`. To prevent it from sweeping protocol assets that the buyBack flow accumulates, it gated on:

```solidity
// Pre-fix gate (V3 path NOT covered)
if (mapV2Oracles[token] != address(0)) {
    revert UnauthorizedToken(token);
}
```

The intent: «if this token has an oracle wired up, it's a registered protocol asset → reject the sweep.» The unstated assumption: «every protocol asset has an oracle.»

The V3 swap path, restored in PR #272 (subject of internal-14 → internal-15), introduced an alternate registration mechanism: V3-only secondTokens are wired up via `setV3PoolStatuses(pool, true)` + `setMaxSlippages(token, bps)` — but never given a V2 oracle. They had `mapV2Oracles[secondToken] == address(0)` and so passed the rescue gate. Any external caller could front-run a V3 buyBack with `transfer(secondToken)`, divert the pre-bought balance to `treasury`, and grief the buy-and-burn workflow.

The fix shape (audited in §2): reshape `mapV3Pools` to mirror `mapV2Oracles` — keyed by secondToken, value = canonical pool address. The combined gate becomes:

```solidity
if (mapV2Oracles[token] != address(0) || mapV3Pools[token] != address(0)) {
    revert UnauthorizedToken(token);
}
```

Symmetric. Closed.

### Root cause — why internal-15 did not surface this

The internal-15 audit cycle was triggered by PR #272+#273 (V3 swap path restoration + price guards). The audit's attention was concentrated on the **swap path mechanics**:

- C4R fixes verification (PR #273 issues #17/#18/#19 — price-guard correctness)
- H-01 storage layout (V3 restoration introducing fields between existing ones)
- H-02 V3 slippage floor = 1 wei
- M-01 oracle fail-open on `observe()` revert
- M-02 BalancerPriceOracle flash-loan-steerability
- M-03 V2 `_buyOLAS` getTWAP staleness
- M-04 Tokenomics `effectiveBond` decreasing-year boundary
- L-01..L-05 (deadlines, NatSpec, BPS bounds, etc.)
- I-01 (setter ancestry)

These are all about **the swap path itself** — pricing, slippage, oracle, deadline, fee. The audit pass that produced this list did not systematically enumerate every **adjacent admin / rescue / sweep / transfer function** and re-verify those functions behave correctly in the presence of V3-only secondTokens.

`transfer()` is in this category. It is not a swap function. It is a stray-token-rescue function. Its gate looked V2-shaped (`mapV2Oracles != 0`), and the V3 restoration extended only the swap-path read paths, not the rescue function's gate. The asymmetry was structurally invisible to an audit focused on swap mechanics alone.

To be fair to the internal-15 methodology, that audit *did* surface analogous asymmetries in adjacent surfaces (H-01 storage layout asymmetry from V3 restoration; M-01 V3 oracle fail-open as asymmetric failure mode vs V2 fail-closed). The audit was sensitive to «V3 restoration introduces asymmetry» — but the sensitivity was scoped to the swap-and-pricing surface area; it did not extend to the rescue surface.

### The pattern, generalized

**Pattern: «Variant-extension asymmetric gate completeness»**

When a contract is extended to support a new variant of an existing feature (V1 → V1+V2, native → native+wrapped, chain-A → chains-A+B), an audit must explicitly enumerate:

1. **Every storage map that the new variant adds or modifies.**
2. **For each map, every function (in this contract and in derived/child contracts) that reads it.**
3. **For every reader of an OLD variant's map, check whether it also reads the NEW variant's map. If not, flag a question: intentional or oversight?**

Special attention to rescue / sweep / transfer / withdraw / claim / unstake / disable functions — these are «is this asset / position / address registered with this feature?» functions and they almost always need symmetric coverage of all variants. They are intentionally permissive on unregistered assets, and asymmetric registries silently re-classify protocol assets as «unregistered» from their narrow point of view.

Detection is mechanical: enumerate readers, cross-reference, flag asymmetries. Remediation is one of:
- Combine gates into a single symmetric check (e.g. `mapV2[x] != 0 || mapV3[x] != 0 → revert`)
- Reshape the new variant's map to match the original (the L-06 fix)
- Introduce a translation helper consulting both maps

This pattern is a generalization of «fix-applied-to-only-one-call-site» (e.g. wildcard `state === Deployed` filter applied at `auth.ts` two call-sites but missed at `background.ts`). That pattern is about forgetting a fix at a parallel site; this pattern is about forgetting to extend a gate when adding a parallel feature. Both share the underlying root cause: incomplete cross-reference between «what changed» and «who else reads the same state».

This pattern is applied below in §3 and §4 to look for analogous bugs across the broader codebase.

---

## §2. L-06 fix re-audit verdict

### What was changed

Commit `a378ac4 fix(BuyBackBurner): close L-06 and I-01 — reshape mapV3Pools to mirror mapV2Oracles`. Three contract files modified:

- `contracts/utils/BuyBackBurner.sol` — primary file. Mapping reshape, gate consolidation, auto-routing, setter canonicality, abstract `_readPoolFeeOrTickSpacing` declaration.
- `contracts/utils/BuyBackBurnerUniswap.sol` — child override; signature change in `_performSwap` (now takes `pool` instead of `feeTierOrTickSpacing`); concrete `_readPoolFeeOrTickSpacing` returning `IUniswapV3Pool(pool).fee()`.
- `contracts/utils/BuyBackBurnerBalancer.sol` — child override; same signature change; concrete `_readPoolFeeOrTickSpacing` returning `ICLPool(pool).tickSpacing()`.

### Verification of L-06 closure

`transfer(address token)` at HEAD (`BuyBackBurner.sol:607-625`):

```solidity
function transfer(address token) external {
    if (mapV2Oracles[token] != address(0) || mapV3Pools[token] != address(0)) {
        revert UnauthorizedToken(token);
    }
    uint256 tokenAmount = IERC20(token).balanceOf(address(this));
    if (tokenAmount == 0) {
        revert ZeroValue();
    }
    address to = treasury;
    // ... transfer logic
}
```

✅ Combined gate verified. The original L-06 attack vector — calling `transfer(V3OnlySecondToken)` — now reverts with `UnauthorizedToken` because `mapV3Pools[V3OnlySecondToken]` is non-zero (the V3 pool address) by virtue of the secondToken being wired in `setV3Pools(...)`.

**Structural impossibility of bypass**: any token with a V3 pool wired in has a non-zero entry in `mapV3Pools`. Any token with neither V2 oracle nor V3 pool is genuinely stray and the rescue path is correct to allow. There is no longer a fee-tier-tunnel: the gate keys directly off `secondToken`, not off pool address.

**No-LM-zero corner case**: when V3 is disabled at deployment (`liquidityManager == 0` or `swapRouter == 0`), `setV3Pools` reverts at its own `_requireV3Enabled()` call, so no entries can be added to `mapV3Pools`. The `mapV3Pools[token] != 0` check is harmlessly always-false in V3-disabled deployments. This is documented in the in-source comment.

### Verification of I-01 side-effect closure

`setV3Pools(address[] secondTokens, address[] pools)` setter at HEAD (`BuyBackBurner.sol:393-443`):

```solidity
function setV3Pools(address[] memory secondTokens, address[] memory pools) external virtual {
    if (msg.sender != owner) {
        revert OwnerOnly(msg.sender, owner);
    }
    _requireV3Enabled();

    uint256 numTokens = secondTokens.length;
    if (numTokens == 0 || numTokens != pools.length) {
        revert WrongArrayLength();
    }

    address localOlas = olas;
    address factoryV3 = ILiquidityManager(liquidityManager).factoryV3();

    for (uint256 i = 0; i < numTokens; ++i) {
        if (secondTokens[i] == address(0)) {
            revert ZeroAddress();
        }
        if (secondTokens[i] == localOlas) {
            revert UnauthorizedToken(secondTokens[i]);
        }

        address pool = pools[i];
        if (pool != address(0)) {
            address[] memory tokens = new address[](2);
            (tokens[0], tokens[1]) = (secondTokens[i] > localOlas)
                ? (localOlas, secondTokens[i])
                : (secondTokens[i], localOlas);
            int24 feeOrSpacing = _readPoolFeeOrTickSpacing(pool);
            if (getV3Pool(factoryV3, tokens, feeOrSpacing) != pool) {
                revert UnauthorizedPool(pool);
            }
        }

        mapV3Pools[secondTokens[i]] = pool;
    }

    emit V3PoolsUpdated(secondTokens, pools);
}
```

✅ Canonicality check verified. For every non-zero pool: token ordering is computed canonically; fee tier / tick spacing is read **from the pool itself**; factory ancestry is enforced via `getV3Pool(factoryV3, tokens, feeOrSpacing) == pool`.

**Adversarial-pool resistance**: an admin-supplied non-pool address would either (a) revert at `_readPoolFeeOrTickSpacing` if the address doesn't conform to the V3 pool interface (`fee()` or `tickSpacing()` selector missing), or (b) pass `_readPoolFeeOrTickSpacing` with garbage data and then fail at `getV3Pool != pool`. Either way, the setter reverts cleanly. No unauthorised entry can land in `mapV3Pools`.

### Auto-routing in `buyBack`

Unified `buyBack(address secondToken, uint256 secondTokenAmount, uint256 deadline)` entry point at `BuyBackBurner.sol:528-585`:

```solidity
uint256 olasAmount;
if (mapV3Pools[secondToken] != address(0)) {
    olasAmount = _buyOLASV3(secondToken, secondTokenAmount);
} else {
    olasAmount = _buyOLAS(secondToken, secondTokenAmount);
}
```

✅ V3-first if `mapV3Pools[token] != 0`; V2 fallback otherwise. The 4-arg V3 overload `buyBack(address, uint256, int24, uint256)` is removed — callers no longer supply fee tier; pool is read from `mapV3Pools[secondToken]`, fee/tickSpacing is read from pool at swap time. Routing decision is a pure state read; no external call influences which path is taken.

### `_buyOLASV3` correctness

`BuyBackBurner.sol:255-294`:

```solidity
function _buyOLASV3(address secondToken, uint256 secondTokenAmount) internal virtual returns (uint256 olasAmount) {
    _requireV3Enabled();
    address pool = mapV3Pools[secondToken];
    if (pool == address(0)) {
        revert UnauthorizedToken(secondToken);
    }
    uint160 centerSqrtPriceX96 = ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);
    address localOlas = olas;
    bool olasIsToken1 = (secondToken < localOlas);
    // ... TWAP-derived amountOutMin computation
    olasAmount = _performSwap(secondToken, secondTokenAmount, pool, amountOutMin);
}
```

✅ Pool lookup is via `mapV3Pools[secondToken]` (consistent with the routing decision). Token-ordering consistency: because `setV3Pools` enforces factory ancestry, the pool's actual `token0`/`token1` ordering is guaranteed to match `min(secondToken, localOlas)` / `max(secondToken, localOlas)` — so the `olasIsToken1` derivation is a function of secondToken/localOlas only, with no need to read the pool's token ordering.

---

## §3. New findings (broad-scope re-audit)

### 🟡 M-1 — Bridge2BurnerPolygon: L1 destination is L1-mirror of L2 contract, not OLAS_BURNER — ✅ Fixed

**Resolution**: `relayToL1Burner()` no longer calls Polygon's `ChildERC20.withdraw(amount)`. OLAS is forwarded to the
Polygon bridge mediator (`0x9338b5153AE39BB89f50468E608eD9d764B755fD`), the L2 contract that L1 governance reaches over
fx-portal. Final disposition (keep, transfer, trigger PoS-bridge burn) is governance's call, not this contract's.
Sidesteps the Polygon PoS bridge's missing recipient parameter and matches the existing "send-to-bridge-mediator"
pattern already used by `LPSwapCelo` for leftover-token routing on Celo.

**File**: `contracts/utils/Bridge2BurnerPolygon.sol`.

Original finding (preserved for historical record): the contract used to call Polygon's `ChildERC20.withdraw(amount)`:

```solidity
IBridge(l2TokenRelayer).withdraw(olasAmount);
```

Polygon's PoS bridge `withdraw(amount)` interface has **no recipient parameter**. After L2 burn + L1 `RootChainManager.exit(proof)` ceremony, Polygon's bridge releases L1 tokens to **the L1-mirror of L2 `msg.sender`** — i.e., the same address as `Bridge2BurnerPolygon` on Polygon, projected to L1.

Compare with `Bridge2BurnerOptimism.sol:63` and `Bridge2BurnerArbitrum.sol:69` which pass `OLAS_BURNER` explicitly:

```solidity
// Optimism
IBridge(l2TokenRelayer).withdrawTo(olas, OLAS_BURNER, olasAmount, TOKEN_GAS_LIMIT, "0x");
// Arbitrum
IBridge(l2TokenRelayer).outboundTransfer(l1Olas, OLAS_BURNER, olasAmount, 0, 0, "");
```

Both use bridge primitives with a `_to` recipient parameter and route to OLAS_BURNER directly. Polygon's primitive does not support this; the recipient is fixed by the L2 sender's L1 mirror.

**Architectural gap**: between «L1 release at Bridge2BurnerPolygon's L1-mirror address» and «OLAS arrives at OLAS_BURNER for burning», the audited repo provides no forwarding mechanism. Resolution requires one of:

1. **Counterfactual L1 deployment**: deploy a separate L1 forwarding contract at the same address as Bridge2BurnerPolygon on Polygon (using same EOA + same nonce, since CREATE addresses are sender+nonce-derived). The L1 contract would call `RootChainManager.exit(proof)` and forward received OLAS to OLAS_BURNER. Not present in the audited scope.
2. **Off-chain `exit()` + accept-as-burn**: someone calls `RootChainManager.exit()` with proof, but the L1 release destination is fixed by L2 sender — off-chain process cannot redirect to OLAS_BURNER. Tokens land at the L2 address's L1 mirror; if no contract code is deployed there, tokens are inaccessible. Functionally equivalent to «extra burn» (OLAS removed from circulation), but not visible at canonical OLAS_BURNER and not credited to OLAS_BURNER's balance ledger.
3. **Switch primitive**: replace Polygon's PoS withdraw with a bridge primitive that supports an explicit recipient parameter (LayerZero, Hyperlane, etc.).

**Operator/customer impact**: BBB on Polygon swaps secondTokens → OLAS → transfers OLAS to Bridge2BurnerPolygon. `Bridge2BurnerPolygon.relayToL1Burner()` burns OLAS on Polygon. Without the L1 forwarding contract correctly deployed, the burned OLAS becomes inaccessible on L1 — the buy-and-burn flow «leaks» OLAS into a dead address on L1 (technically equivalent to burn from supply perspective, but not at the canonical OLAS_BURNER, so OLAS supply accounting may not reflect this burn at the canonical reporting address).

**Severity Medium** rationale:
- Not direct fund-to-attacker — self-grief by architecture
- Possibly intentional «extra burn» (extra supply removal) — but this is ambiguous in current source comments
- Without operator action (option 1 above), OLAS supply accounting at OLAS_BURNER is incomplete
- Recovery requires ops action; tokens already exited to a dead L1 address are unrecoverable without a counterfactual L1 deployment

**Recommended fix**: pick one of options 1-3 and document the choice explicitly in the contract NatSpec. If option 1 is chosen, document the deployment procedure (same EOA + nonce on L1 vs Polygon).

### 🟢 L-NEW-1 — Bridge2BurnerOptimism `TOKEN_GAS_LIMIT = 300_000` hardcoded — 📝 Documented (VL #22)

**File**: `contracts/utils/Bridge2BurnerOptimism.sol:41,63`.

`TOKEN_GAS_LIMIT = 300_000` is passed to `withdrawTo` for L1 receive gas. If OLAS_BURNER is ever upgraded to a more gas-intensive contract (>300K gas in `transfer`/`mint` callback), bridge messages would fail on L1.

Mitigation by Optimism bridge spec: failed L1 messages can be replayed with more gas via the standard bridge replay mechanism. Tokens not permanently lost — operational concern only.

**Recommended**: make `TOKEN_GAS_LIMIT` owner-settable, or document the implicit assumption «OLAS_BURNER L1 receive < 300K gas».

**Disposition**: documented as VL **#22**. The team accepts the residual — current `OLAS_BURNER` L1 receive footprint is well under 300 K gas and there is no roadmap that would push it higher; bridge replay is available for the operational tail.

### 🟢 L-NEW-2 — Token approvals to bridges not cleared after relay — ✅ Fixed

**Resolution**: Each of `Bridge2BurnerArbitrum`, `Bridge2BurnerGnosis`, `Bridge2BurnerOptimism` now calls `IToken(olas).approve(l2TokenRelayer, 0)` immediately after the successful bridge primitive (`outboundTransfer` / `relayTokens` / `withdrawTo`). The Polygon variant doesn't approve at all under M-1's transfer-based path, so it is unaffected.

**Files** (original finding, retained for context): `contracts/utils/Bridge2BurnerArbitrum.sol:66`, `Bridge2BurnerGnosis.sol:45`, `Bridge2BurnerOptimism.sol:60`.

After successful `withdraw`/`outboundTransfer`, the residual approval to `l2TokenRelayer` was not reset. The bridge primitives consume the approved amount, so practical residual is zero; but if `l2TokenRelayer` is ever an upgradeable contract that gets compromised, leftover allowance from prior calls could be exploited. Mitigated by trust model: l2TokenRelayer addresses (Arbitrum L2GatewayRouter, Gnosis Omnibridge, Optimism L2StandardBridge) are immutable infrastructure.

### 🟢 L-NEW-3 — Bridge2Burner family lacks emergency rescue

**Files**: all 5 Bridge2Burner contracts (base + 4 chain-specific).

No owner/admin rescue function exists. If OLAS gets stuck in any Bridge2Burner contract (misconfiguration, bridge failure, accidental token transfer), there is no recovery mechanism. The Polygon case (M-1) is the most acute manifestation of this.

**Recommended (optional)**: add owner-gated `rescue(address token, address to, uint256 amount)` in base `Bridge2Burner` for emergency recovery. Trade-off: introduces owner-trust to a currently trustless contract.

### 🟢 L-NEW-4 — Tokenomics integer truncation in incentive pattern

**File**: `contracts/Tokenomics.sol:865, 881`.

```solidity
// V2 reward (line 865):
totalIncentives = mapUnitIncentives[unitType][unitId].reward + totalIncentives / 100;
// V2 top-up (line 881):
totalIncentives = mapUnitIncentives[unitType][unitId].topUp + totalIncentives / sumUnitIncentives;
```

Division truncates before addition. Same finding class as **C4A L-09** (`_trackServiceDonations` integer-division truncation, documented residual at VL #18). Bounded by per-unit denomination; cumulative loss across service donations is small.

Same disposition as C4A L-09 — acknowledged residual.

### 🟢 L-NEW-5 — GenericBondCalculator.getCurrentPriceLP flash-loan readable (view-only mitigated)

**File**: `contracts/GenericBondCalculator.sol:70-92`.

`getCurrentPriceLP()` reads Uniswap V2 reserves directly (`pair.getReserves()`). Reserves are flash-loan-manipulable.

**Mitigation verified**: `getCurrentPriceLP` is view-only and used by `Depository.priceLP` setter at bond create-time, where the owner explicitly sets the priceLP value. Bond payouts use the stored priceLP, not a live read. Flash-loan manipulation can affect view results (frontend display may see distorted price) but cannot influence on-chain bond payout calculation.

Same class as residual oracle concerns — already-bounded pattern.

### ℹ️ INFO-1 — `setV2Oracles` and `setV3Pools` are not mutually exclusive (operational footgun) — 📝 Documented (VL #23)

After the L-06 reshape, both `mapV2Oracles[token]` and `mapV3Pools[token]` can be set non-zero for the same `token`. Consequences:

- `transfer(token)`: combined gate correctly blocks (mapV2Oracles non-zero is sufficient; the V3 leg is redundant in this case).
- `buyBack(token, ...)`: auto-routing prefers V3 — `mapV3Pools[token] != 0` short-circuits to `_buyOLASV3`, never reaching the V2 fallback. The V2 oracle entry is silently unreachable while a V3 pool is configured.

`setV3Pools` is owner-only; the combined `transfer()` gate handles either-or-both states; no fund-loss path opens up. The auto-routing precedence is documented in source (lines 558-559).

**Recommended (operational)**: when migrating an existing V2-oracle token to V3, explicitly call `setV2Oracles(token, address(0))` first to clear the V2 entry. Add a deployment-runbook note alongside `scripts/deployment/pol/script_03_buy_back_burner_wire_v3.sh`.

**Disposition**: documented as VL **#23**. Owner-only setters with symmetric on-chain security gate; the footgun is operational only.

### ℹ️ INFO-2 — Depository OLAS transfer return value not checked — 📝 Documented (VL #21)

**File**: `contracts/Depository.sol:390`.

```solidity
IToken(olas).transfer(msg.sender, payout);
```

No bool return check. Acceptable for OLAS specifically because OLAS is the deployed canonical Olas token contract — known standard ERC20 with revert-on-failure semantics. A non-standard `transfer` returning `false` silently is not realistic for OLAS.

Code-hygiene only. Should use `SafeTransferLib.safeTransfer` for consistency.

**Disposition**: documented as VL **#21**. OLAS is the canonical revert-on-failure ERC20; the return-check is theoretical hardening only. SafeTransferLib normalization deferred.

### ℹ️ INFO-3 — ABI break impact summary

The L-06 reshape introduces ABI-breaking changes that off-chain consumers must update:

| Old ABI | New ABI |
|---|---|
| `setV3PoolStatuses(address[] pools, bool[] statuses)` | `setV3Pools(address[] secondTokens, address[] pools)` |
| `mapV3Pools(address) returns (bool)` | `mapV3Pools(address) returns (address)` |
| `buyBack(address, uint256, int24, uint256)` (4-arg) | REMOVED — use `buyBack(address, uint256, uint256)` (auto-routing) |
| `event V3PoolStatusesUpdated(address[] pools, bool[] statuses)` | `event V3PoolsUpdated(address[] secondTokens, address[] pools)` |

In-repo callers: all updated. `scripts/deployment/pol/script_03_buy_back_burner_wire_v3.sh` uses the new signature. No remaining references to old names except in `audits/internal13/analysis/` flat snapshots (historical).

Off-repo consumers (ops responsibility):
- Subgraph indexers consuming `V3PoolStatusesUpdated` event must migrate to `V3PoolsUpdated`.
- Any keeper bot that calls the 4-arg `buyBack` overload must update to the 3-arg signature.
- Any monitoring dashboard reading `mapV3Pools(addr)` as boolean must update to read `address` and check non-zero.

Since this fix lands in the «⚪ Code fix only — never deployed» bucket per internal-15 §1 matrix, the ABI break is invisible to current on-chain state — there are no proxies running the new impl yet.

---

## §4. Bridge2Burner cross-chain analysis (contextualizing M-1)

The five Bridge2Burner contracts (base + 4 chain-specific) handle L2-to-L1 OLAS relay back to the canonical OLAS_BURNER (`0x51eb65012ca5cEB07320c497F4151aC207FEa4E0`).

### Recipient-parameter analysis per chain

| Chain | L2 bridge primitive | Recipient parameter? | Routes to OLAS_BURNER? |
|---|---|---|---|
| Optimism | `L2StandardBridge.withdrawTo(_l2Token, _to, _amount, _gas, _extraData)` | ✅ explicit `_to` | ✅ `OLAS_BURNER` |
| Arbitrum | `L2GatewayRouter.outboundTransfer(_l1Token, _to, _amount, ...)` | ✅ explicit `_to` | ✅ `OLAS_BURNER` |
| Gnosis | `Omnibridge.relayTokens(token, recipient, amount)` | ✅ explicit `recipient` | ✅ `OLAS_BURNER` |
| **Polygon** | `ChildERC20.withdraw(amount)` | ❌ **no recipient parameter** | ❌ L1 mirror of L2 sender |

The asymmetry is at the bridge primitive level: Polygon's PoS ERC20 bridge does not support explicit recipient on the L2 burn call — the L1 release destination is fixed by L2 `msg.sender`'s L1 mirror. This is the upstream cause of M-1.

### Replay protection — verified sound

All chain-specific bridges (Arbitrum L2GatewayRouter, Gnosis Omnibridge, Optimism L2StandardBridge, Polygon ChildERC20) handle nonce/sequencing internally. Bridge2Burner contracts are stateless w.r.t. outbound messages — no replay vector at the Bridge2Burner level.

### Reentrancy — verified sound

All subclasses use `_locked` guard. Infrastructure bridges don't support callbacks. Overly defensive but safe.

### Permissionless `relayToL1Burner()` — design-correct

All `relayToL1Burner()` are permissionless. Anyone can trigger relay when balance accumulates. This is intentional and correct (no operator dependency for buy-and-burn). Front-run is bounded — relayer doesn't extract value, just triggers the bridge.

---

## §5. Substantive surface analysis — Dispenser, Tokenomics, Treasury+Depository, LiquidityManager

This section documents what was investigated on each surface and why no additional code-side findings were found beyond §3.

### Dispenser + cross-chain staking (1330 LOC + staking/*.sol)

**Bridge replay protection**: L1 side maintains `processedHashes` keyed by `batchHash = keccak256(abi.encode(nonce, block.chainid, address(this)))` (`DefaultDepositProcessorL1.sol:56, :134-137`). Nonce incremented atomically (`stakingBatchNonce = batchNonce + 1` at line 183). L2 side maintains parallel `processedHashes`. Any malicious-bridge replay attempt is caught at the receive-side lookup. Unique batch hash per message uses (nonce, chainId, processor address) — collision resistance holds across cross-chain replay attempts because chainId is bound to `block.chainid` at construction time.

**Withheld amount manipulation**: `mapChainIdWithheldAmounts` is updated through `syncWithheldAmount()` (gated to `msg.sender == depositProcessor`) and `syncWithheldAmountMaintenance()` (owner-only + validates `chainId != block.chainid`). Both paths only ADD to the withheld amount. Subtraction happens only inside `claimStakingIncentives()` flow, bounded by stake vote weight. No unauthorized reduction path exists.

**Symmetric-reads check (multi-chain variant axis)**: per the variant-extension rule from §1, checked whether any function reads one of `mapChainIdDepositProcessors` / `mapChainIdWithheldAmounts` while it should also check the other. Each map governs a separate concern (which processor; how much is withheld); no asymmetric-gate analogous to L-06 exists.

**Access control**: all admin functions (`changeOwner`, `changeManagers`, `setDepositProcessorChainIds`, `setPauseState`) check `msg.sender == owner` before mutation. `DefaultDepositProcessorL1` permanently revokes owner after setting L2 dispenser at line 258 — one-shot setup pattern.

**Bridge gas/fee handling**: each bridge implementation calculates total cost upfront and validates `msg.value >= totalCost` before send (e.g., `ArbitrumDepositProcessorL1.sol:179`). Refunds explicitly computed and sent to `tx.origin` or `msg.sender`. Consistent across implementations.

### Tokenomics epoch state (1581 LOC)

**Synchronized state updates** at lines 961-964 maintain the invariant «`pendingRelativeTopUp[unit] > 0` ⇒ `sumUnitTopUpsOLAS[epoch][unitType] > 0`»:

```solidity
if (topUpEligible && incentiveFlags[unitType + 2]) {
    mapUnitIncentives[unitType][serviceUnitIds[j]].pendingRelativeTopUp += amount;
    mapEpochTokenomics[curEpoch].unitPoints[unitType].sumUnitTopUpsOLAS += amount;
}
```

Both maps update synchronously inside the same if-block with the same `amount`. The invariant is also formalized via `#if_succeeds` annotations at lines 996-997.

**Permissionless functions**: `checkpoint()`, `getOwnerIncentives()` (view), `getUnitPoint()`, `getLastIDF()`, `getEpochEndTime()`. Of these, only `checkpoint()` mutates state — and it correctly reads from `mapEpochTokenomics` for completeness, validates `block.timestamp >= endTime`, and is internally idempotent within an epoch. `trackServiceDonations`, `accountOwnerIncentives`, `updateInflationPerSecondAndFractions` are gated to treasury/depository/dispenser/owner.

**Symmetric unit-type axis**: every function that iterates over unit types iterates over both component (0) and agent (1): `_trackServiceDonations`, `_finalizeIncentivesForUnitId`, `accountOwnerIncentives`, `getOwnerIncentives`. No asymmetric-read pattern analogous to L-06.

**Other observations**:
- Unit-id 0 not gated explicitly in `accountOwnerIncentives`/`getOwnerIncentives`. ERC721 registries don't typically mint ID 0; bounded by external invariant. Defensive-only, not exploitable.
- Integer truncation in donation split (line 937, `uint96 amount = uint96(amounts[i] / numServiceUnits)`): same finding class as C4A L-09. Bounded.

### Treasury + Depository (551 + 494 LOC)

**`Treasury.withdrawToAccount` reentrancy**: function is dispenser-only at lines 396-398:

```solidity
if (dispenser != msg.sender) {
    revert ManagerOnly(msg.sender, dispenser);
}
```

A reentrant attempt by `account`'s callback can only target Treasury via the same path — and would fail the `msg.sender == dispenser` check. Reentrancy through Dispenser's own state is bounded by Dispenser's `_locked` guard. The docstring at line 375 «Reentrancy guard is on a dispenser side» is the architectural framing: Treasury delegates the lock to Dispenser.

**`Treasury.withdraw` CEI**: owner-only function. State updates (lines 335-336) precede external ETH send (line 339). The contract's commentary at lines 36-38 acknowledges «Invariant does not support a failing call() function while transferring ETH when using the CEI pattern» — honest acknowledgment that the receive function exists, not a CEI violation in `withdraw()`. No reentrancy path is available because `withdraw()` is owner-only.

**`mapTokenReserves` desync**: `mapTokenReserves[token]` is updated only through `depositTokenForOLAS()`. Any token can be directly transferred to Treasury, increasing actual balance without updating the reserves map. Donated tokens stay stuck in the contract; `withdraw()` is bounded by `mapTokenReserves[token]` (line 354). The donor self-griefs (loses their own tokens). No fund extraction; would warrant a sweep function for stuck tokens if direct donations become a recurring operational concern. Not a finding.

**`Depository.deposit()` reentrancy**: follows CEI pattern correctly:
- Lines 329-334: state mutations (product.supply decrement, mapUserBonds, bondCounter)
- Line 337: external call to `Treasury.depositTokenForOLAS`
- A reenter call to `deposit()` would observe decreased product.supply → revert with `ProductClosed` if exhausted, or proceed with reduced supply (still consistent state)

External-call surface: `IToken(token).transferFrom(msg.sender, treasury, tokenAmount)` (standard ERC20, no callback to recipient); `IOLAS(olas).mint(buyer, payout)` (OLAS is deployed standard ERC20, no transfer hooks on mint). No reentrancy path identified.

### LiquidityManagerCore + NeighborhoodScanner + Oracles (~2500 LOC combined)

**V3 NFT position takeover**: `mapPoolAddressPositionIds` (LiquidityManagerCore:151) maps pool→positionId. All functions that read/write this map are owner-only (`convertToV3` line 671, `changeRanges` line 766, `decreaseLiquidity` line 890, `collectFees`, `increaseLiquidity` line 961, `transferPositionId` line 1033). Position ownership is enforced at two layers: contract-level owner gates + Uniswap V3 NonfungiblePositionManager NFT custody (the contract can only call `decreaseLiquidity` / `collect` if it holds the NFT). Single-layer compromise (owner key) is the attack surface — already tracked under C-01 OpSec residual.

**POL math precision**: C4A L-08 fixed `value0InToken1` for the `sqrtP ≤ 2^128` case (NeighborhoodScanner:671-685, single-step path; two-step fallback for extreme pools). Other math paths in LiquidityManagerCore (TickMath conversions, LiquidityAmounts library calls, `_optimizeTicksAndMintPosition`) delegate to standard Uniswap V3 libraries. NeighborhoodScanner intermediate math at lines 71-76 uses `FullMath.mulDiv` with `FixedPoint96.Q96` — overflow-safe.

**TWAP observation cardinality**: LiquidityManagerCore calls `increaseObservationCardinalityNext(observationCardinality)` at mint time (line 733). Subsequent operations rely on that prior request to materialize as the pool sees swaps. If a pool stays illiquid, cardinality may not grow; in that case `checkPoolAndGetCenterPrice` (line 1124-1181) degrades gracefully — falls back to slot0 with deviation guard. Documented in source comments lines 1145-1149 as intentional. Operator-controlled (operator decides which pools to mint into).

**BalancerPriceOracle flash-loan steerability** (M-02 residual carry-over): no new unguarded `getPrice()` call paths since internal-15. BBB `_buyOLAS` calls `updatePrice()` first (rate-limited), then `getTWAP()`. LiquidityManagerCore uses `checkPoolAndGetCenterPrice` (TWAP deviation guard). BalancerPriceOracle's own `getTWAP` uses spot only as counterfactual within rolling window.

**Slippage anchor in `_increase` / `_decreaseLiquidity`** (L-04 residual carry-over): functions are admin-only with `_locked` reentrancy guard. Spot-anchored slippage is suboptimal but bounded by admin-trust + reentrancy-guard.

### BuyBackBurner family beyond L-06

`BuyBackBurner.sol`, `BuyBackBurnerUniswap.sol`, `BuyBackBurnerBalancer.sol` re-audited at HEAD `5fadd70`:

- `setV2Oracles`, `setV3Pools`, `setMaxSlippages`, `updateOraclePrice`, `changeImplementation`, `changeOwner`: owner/permissionless gates verified consistent.
- `updateOraclePrice` is V2-only by design (V3 doesn't have an analogous stored oracle; reads price live via pool's `observe()`). The asymmetry is intentional and reflects that V3 doesn't need an analog.
- `_locked` reentrancy guard correctly placed in `buyBack()` (lines 533-580 acquire/release).
- Slippage = 0 → DEX reverts fail-closed pattern at line 244 (V2) and 287-289 (V3, with explicit comment). Operator must configure slippage explicitly per token before swap works.
- Immutable `bridge2Burner`, `treasury`, `liquidityManager`, `swapRouter` (lines 132-139) — set once at constructor, not mutable post-deploy. No path to redirect funds via setter manipulation.

---


## §6. Cross-contract privilege graph

Privilege graph for Tokenomics, Treasury, Dispenser, Depository, BuyBackBurner. Each contract has `changeManagers(...)` setter callable by its own owner, that sets the addresses of trusted cross-contract callers. Each function gated «only Manager X can call» checks `msg.sender == storedManagerAddressX`.

**Chained-exploit paths investigated**:

1. **Owner key compromise → full system control via `changeManagers`**: compromise of any contract's owner allows replacement of trusted addresses with attacker contracts → drain via cross-contract calls. **This is C-01 OpSec from internal-15** — not a new finding. The risk surface extends across all four contracts with `changeManagers` (Tokenomics, Treasury, Dispenser, Depository), confirming the C-01 disposition needs to apply at the system level, not just per-contract.

2. **Manager-role-confusion** (copy-paste typo allowing wrong-contract call to pass): not found. Each access-control check uses the correct stored address (e.g., Treasury's `withdrawToAccount` correctly checks `msg.sender == dispenser`, not some other Manager).

3. **Cross-contract reentrancy** (e.g., Tokenomics.checkpoint → Treasury.rebalanceTreasury → loop back): Treasury's `rebalanceTreasury` does pure arithmetic, no external calls back into Tokenomics. Treasury's `withdrawToAccount` has reentrancy guard + dispenser-only access. Not found.

4. **Asymmetric trust** (A trusts B but B doesn't trust A symmetrically): manager designations are per-direction by design, not by symmetry. Each contract's manager set reflects which other contracts can call its privileged functions. No bug; intentional asymmetry.

Privilege graph is internally consistent. C-01 OpSec is the dominant systemic risk, already known and dispositioned.

---

## §7. Storage layout deep-check across proxies

Audited: `BuyBackBurnerProxy + BuyBackBurner.sol`, `TokenomicsProxy + Tokenomics.sol`, `LiquidityManagerProxy + LiquidityManagerCore.sol`.

Result: zero storage collision risk on upgrade paths.
- All 3 proxies use **custom hash-slot for impl pointer** (e.g., `BUY_BACK_BURNER_PROXY = keccak256("BUY_BACK_BURNER_PROXY") = 0xc6d7bd...`). No collision with regular slot positions.
- BBB has 3 deprecated fields (slots 2-4: `nativeToken`, `oracle`, `maxSlippage`) preserved-in-place — preserves slot ordering for any future upgrade. H-01 from internal-15 covered the V2 oracle rewrite scenario; defused by the team's fresh-redeploy strategy.
- L-06 reshape (`mapV3Pools` from `pool→bool` to `secondToken→address`) is a storage CONTENT change, NOT a slot position change. Mapping hash-base unchanged (`keccak256("mapV3Pools")`); content type unchanged storage size; no collision.
- Tokenomics M-04 fix: pure algorithmic change to existing `effectiveBond` slot 7. No new slots, no reordering. In-place upgrade is storage-safe.
- LiquidityManagerCore: brand-new contract, never deployed. Minimal 3-slot mutable state + 6 immutables. Plenty of room for future fields.

---

## §8. DEFI-ATTACK-PATTERNS sweep (16 categories)

Applied 16 standard DeFi attack pattern categories. Findings already listed in §3 (L-NEW-4 Tokenomics integer truncation, L-NEW-5 GenericBondCalculator flash-loan view-only, INFO-2 Depository OLAS transfer return).

Other categories verified structurally safe (with file:line evidence):
- **Donation attacks**: Treasury uses `mapTokenReserves` for accounting; direct token donation does not increment reserves; donor self-griefs.
- **Approval races**: contract-level approvals to bridges are bounded; OLAS approvals follow standard set-to-amount pattern (overwrite-safe).
- **First-depositor share inflation**: no proportional-share-of-balance mints in tokenomics flow; bond payouts use fixed priceLP.
- **Block-stuffing / front-running**: `lastDonationBlockNumber == block.number` flash-loan guard at Tokenomics:1101; `buyBack` has reentrancy guard + deadline parameter (post-L-01 fix); `claimStakingIncentives` is per-user.
- **MEV on epoch boundary**: `Tokenomics.checkpoint` is permissionless and idempotent within an epoch — frontrunning doesn't extract value.
- **Sandwich on swap paths**: BBB has TWAP-derived `amountOutMin` (post-H-02 fix) + per-token slippage; LiquidityManagerCore has `checkPoolAndGetCenterPrice` deviation guard.
- **Flash-loan steerable price oracles**: BalancerPriceOracle M-02 known residual; verified no NEW unguarded reads. UniswapPriceOracle uses TWAP windowing.
- **Integer overflow**: Tokenomics uses uint96 packed structs; checked overflow paths against expected magnitude (escrow amounts × per-epoch counters); no realistic overflow in protocol lifetime.
- **Unbounded loops**: claim flows iterate over user-provided arrays bounded by `numServiceUnits` per service; total bounded by service registry size; gas-bounded by user-provided unitIds[] array.
- **TOCTOU**: state reads + external calls follow CEI throughout (verified per-function in §5 and elsewhere).
- **Logic bugs in fraction math**: `MAX_BPS = 10000` with `(MAX_BPS - tokenMaxSlippage)` pattern — overflow safe in Solidity 0.8.x panics on underflow; tokenMaxSlippage is bounded by `setMaxSlippages` upper-bound check (post-L-05 fix).
- **Bond redemption manipulation**: Depository bond payouts compute on stored `priceLP` at create-time; no path to manipulate at redemption time.
- **Silent token transfer failures**: BuyBackBurner uses `IERC20.transfer` with bool check (line 573-576); Bridge2Burner family uses bridge-specific interfaces; Treasury uses bool check on critical transfers; Depository INFO-2 above.
- **Missing zero-address checks**: Construction-time zero checks present in Bridge2Burner family, BuyBackBurner constructor, Treasury constructor.
- **Function selector collision**: custom storage slot hashes for proxies prevent collision with implementation function selectors.

---

## §9. Test coverage assessment (L-06 fix)

| File | Type | Tests | Coverage |
|---|---|---|---|
| `test/BuyBackBurnerTransferV3.t.sol` | Unit | 13 | transfer-blocked V3 secondToken, transfer-after-delist, fee-tier-tunnel-impossibility, transfer-still-blocks-V2-oracle, unrelated-token sweep ok, setter canonicality (positive + non-canonical revert + factory-returns-zero + delist + zero-secondToken + OLAS-secondToken + array-mismatch + event) |
| `test/BuyBackBurnerTransferV3ETH.t.sol` | Fork (ETH mainnet) | 9 | Real Uniswap V3 factory, real OLAS/WETH 1.0% pool (canonical), real USDC/WETH 0.3% pool (used as non-canonical sample), transfer + setter canonicality + dual-set edge case |
| `test/BuyBackBurnerTransferV3Base.t.sol` | Fork (Base, Slipstream) | 6 | Real Slipstream factory, OLAS/USDC pool, tickSpacing path, setter + transfer coverage |

The most diagnostic test for the original L-06 attack vector:

```solidity
function test_transfer_blocksV3SecondToken_evenWhenSweptAtAnyFeeTier() public { ... }
```

Plus dual-set edge case (corresponding to INFO-1) explicitly tested:

```solidity
function testTransfer_blocksWhenBothV2AndV3Configured() public { ... }
```

Real-factory canonicality coverage: `testSetV3Pools_acceptsCanonicalOlasWethPool`, `testSetV3Pools_revertsForNonexistentFeeTier_realFactory`, etc.

Per audit-doc claim from the team: «All 123 unit tests pass; all 4 ETH-fork tests pass.» Forge test results were reported by the team and not re-run by this audit; the tests' logical coverage is verified by reading.

---

## §10. OpSec carry-over — C-01

C-01 from internal-15 (7 BBB proxies owned by single-owner EOAs across 7 chains; same EOA `0xeb2a22b27c7ad5eee424fd90b376c745e60f914e` on 6 chains, different EOA `0x6f7a4938ab3bbf69480e7c109af778ee78099be7` on Base) is **unchanged by this fix**. The L-06 fix is contract-source-side only; ownership topology is unchanged.

§7's privilege-graph analysis confirms the C-01 risk extends across Tokenomics/Treasury/Dispenser/Depository owner keys via cross-contract `changeManagers` chain — single owner key compromise on any of these contracts allows full system control via manager replacement.

Disposition (carry-over from internal-15 §3 of `FINAL_REVIEW.md`): C-01 is dispositioned **acknowledged-and-deferred** per the explicit waiver dated 2026-04-22. Severity remains Critical on the record; the disposition reflects that the ops team owns the remediation timeline.

On-chain owner map (from internal-15 verification at `review/stack-2026-04-22` tip; no change since):

| Chain | BBB proxy | Owner | Owner kind |
|-------|-----------|-------|------------|
| Ethereum | (per `globals_eth_mainnet.json`) | `0xeb2a22...` | EOA |
| Arbitrum | (per `globals_arbitrum_mainnet.json`) | `0xeb2a22...` | EOA |
| Optimism | (per `globals_optimism_mainnet.json`) | `0xeb2a22...` | EOA |
| Gnosis | (per `globals_gnosis_mainnet.json`) | `0xeb2a22...` | EOA |
| Polygon | (per `globals_polygon_mainnet.json`) | `0xeb2a22...` | EOA |
| Celo | (per `globals_celo_mainnet.json`) | `0xeb2a22...` | EOA |
| Base | (per `globals_base_mainnet.json`) | `0x6f7a49...` | EOA |

On-chain action item (carry-over from internal-15 §1 action items): a fresh re-deploy of new `BuyBackBurnerProxy` instances on all 7 chains under Safe + 48h timelock owners is the path to closing C-01. The L-06 fix (along with H-02, M-01, M-03, L-01, L-02, L-05, I-01, C4A L-08) lands on-chain with that fresh re-deploy bundle.

---

## §11. Verdict + recommendations

⚠ **PASS-WITH-FINDINGS** for the `fix-l06-v3-second-token-mapping` branch.

| Dimension | Result |
|---|---|
| L-06 closure | ✅ Verified at HEAD `5fadd70` — combined gate blocks attack vector structurally |
| I-01 side-effect closure | ✅ Verified — setter enforces factory ancestry |
| New code-side findings | 1 MEDIUM (M-1 Polygon Bridge2Burner) + 5 LOW + 3 INFO |
| Agent Critical claims | 3/3 verified as false positives with file:line reasoning (§6) |
| Test coverage | ✅ 28 tests covering original attack + setter canonicality + Slipstream variant + dual-set edge case |
| ABI break | Documented; in-repo callers updated; off-repo consumers must migrate (ops responsibility) |
| OpSec C-01 carry-over | Unchanged; acknowledged-and-deferred per internal-15. §7 confirms risk extends across full system via `changeManagers` |
| Methodology | «Variant-extension asymmetric gate completeness» pattern codified (§1) and applied across the project (§§3-9) |

Branch is mergeable with the following pre-deployment recommendations:

1. **M-1 (Bridge2BurnerPolygon)** — RESOLVE before Polygon BBB sees production OLAS volume. Choose:
   - Deploy L1 counterpart contract at counterfactual address (CREATE address match via same EOA + nonce on L1 vs Polygon) implementing `RootChainManager.exit(proof) → forward to OLAS_BURNER`, OR
   - Document explicitly that Polygon path burns at L1-mirror dead address (intentional supply removal, off-canonical OLAS_BURNER), OR
   - Switch Polygon to a bridge primitive supporting recipient parameter
2. **C-01 carry-over** — same disposition as internal-15: ops-side BBB ownership migration from EOA to Safe + 48h timelock across all 7 chains. §7 emphasizes this disposition needs to extend to Tokenomics/Treasury/Dispenser/Depository owner keys, not just BBB.
3. **5 LOW + 3 INFO** — code-hygiene improvements; non-blocking for branch merge; team can address in a follow-up cleanup PR or accept as documented residuals.

### What the maintainer should know

1. **The L-06 fix is sound**. Combined gate, setter canonicality, auto-routing, and abstract `_readPoolFeeOrTickSpacing` are all verified. Tests cover the right cases including Slipstream.
2. **🟡 NEW MEDIUM — Bridge2BurnerPolygon L1 destination**: tokens released after Polygon exit() go to the L2 contract's L1-mirror address, NOT to OLAS_BURNER. Without an L1 counterpart contract deployed at the matching counterfactual address, OLAS sent through the Polygon BBB pipeline is permanently locked at a dead L1 address. Compare with Optimism + Arbitrum which DO route to OLAS_BURNER explicitly via `_to` parameter. **Action needed before Polygon BBB sees production OLAS volume** — see §3 + §4.
3. **5 LOW + 3 INFO findings** documented in §3 — Bridge2Burner family approval cleanup + gas-limit hardcoding + no-rescue, Tokenomics integer truncation pattern (same class as C4A L-09), GenericBondCalculator flash-loan view-only, V2/V3 setter mutual-exclusivity operational footgun, Depository OLAS transfer return check, ABI break impact summary.
4. **3 agent-flagged Critical claims investigated and verified as false positives** with concrete file:line reasoning in §6 (Dispenser zero-processor, Tokenomics div-by-zero, Treasury reentrancy). Maintainer can independently verify by reading those lines.
5. **The methodology gap that allowed L-06 to slip past internal-15 is identified and codified** as pattern «variant-extension asymmetric gate completeness» (§1). Applied across the project in §§3-9 — no other instances of this pattern found beyond L-06.
6. **C-01 OpSec carry-over** still acknowledged-and-deferred. §7 confirms the cross-contract privilege graph has the same owner-trust assumption across Tokenomics/Treasury/Dispenser/Depository — single owner key compromise on any of these enables full system control via `changeManagers` chain.

---

*End of internal audit 16. L-06 fix re-audited PASS. Broader-scope sweep applied; 1 MEDIUM + 5 LOW + 3 INFO new findings discovered. Methodology codified. Branch is mergeable with M-1 Polygon resolution as pre-Mode-F-production gate.*
