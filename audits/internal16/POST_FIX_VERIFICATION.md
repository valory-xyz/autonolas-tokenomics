# Internal Audit 16 — Post-Fix Verification

> **Date**: 2026-05-06
> **Branch under review**: `fix-internal16-bridge2burner-and-vl-followups` (HEAD `7255ba5`)
> **Companion documents in this slot**: [`README.md`](README.md) (internal16 cycle's own work product), [`FINAL_REVIEW.md`](FINAL_REVIEW.md) (C4R 2026-01 cross-reference)
> **VL doc**: [`docs/Vulnerabilities_list_tokenomics.md`](../../docs/Vulnerabilities_list_tokenomics.md)
>
> **Scope of this file**: independent post-fix verification — for each finding tracked in [`README.md`](README.md) and [`FINAL_REVIEW.md`](FINAL_REVIEW.md), confirm the disposition claimed there matches the code at the branch HEAD, and surface any new mismatches that the fixes themselves introduce. Intended for downstream auditors who arrive holding both prior documents and want a single-page check on whether the closure story holds at the post-fix tip.
>
> **Not in scope**: re-derivation of the original findings, alternative remediation strategies, or re-verification of prior already-CLOSED items not touched by this branch.

---

## §1. Verification of disposition claims

The two preceding files in this slot make explicit closure claims. This section walks each one against the branch HEAD code and records the verification outcome.

### 1.1 M-1 — Bridge2BurnerPolygon L1 destination ✅ Fixed (verified)

**Claim** ([README.md §3 M-1](README.md), commit [`ec4bc9a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ec4bc9a)): replace recipient-less `IBridge.withdraw(amount)` with `IToken(olas).transfer(l2TokenRelayer, olasAmount)` where the inherited `l2TokenRelayer` immutable now holds the L2 bridge mediator address (governance-controlled via fx-portal).

**Code at HEAD** (`contracts/utils/Bridge2BurnerPolygon.sol:47-64`):

```solidity
function relayToL1Burner() external virtual override {
    if (_locked > 1) {
        revert ReentrancyGuard();
    }
    _locked = 2;

    uint256 olasAmount = _getBalance();

    bool success = IToken(olas).transfer(l2TokenRelayer, olasAmount);
    if (!success) {
        revert TransferFailed(olas, l2TokenRelayer, olasAmount);
    }

    _locked = 1;
}
```

**Verification:**
- ✅ Polygon PoS bridge `withdraw(uint256)` call removed
- ✅ ERC20 `transfer(...)` to inherited `l2TokenRelayer` substituted
- ✅ Transfer return checked + reverts on failure (`TransferFailed` error declared at lines 18-22)
- ✅ Reentrancy guard correctly placed (acquire before balance read; release after transfer)
- ✅ Constructor (line 44) takes `_bridgeMediator` and forwards to base `Bridge2Burner(_olas, _bridgeMediator)` — the base's `_l2TokenRelayer` parameter is reused for the mediator address
- ✅ NatSpec at lines 24-38 documents the recipient-parameter asymmetry vs Optimism/Arbitrum/Gnosis variants and the reuse of the inherited `l2TokenRelayer` field

**Disposition**: original M-1 attack vector (OLAS released to a dead L1-mirror address) is structurally closed in code. The claim in the closing-summary is accurate.

### 1.2 L-NEW-2 — Bridge2Burner approval cleanup ✅ Fixed (verified)

**Claim** ([README.md §3 L-NEW-2](README.md), commit [`ec4bc9a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ec4bc9a)): `Bridge2BurnerArbitrum`, `Bridge2BurnerGnosis`, and `Bridge2BurnerOptimism` reset OLAS approval to 0 immediately after the bridge primitive call.

**Code at HEAD:**

| File | Line | Code |
|---|---|---|
| `contracts/utils/Bridge2BurnerArbitrum.sol` | 72 | `IToken(olas).approve(l2TokenRelayer, 0);` (after `outboundTransfer`) |
| `contracts/utils/Bridge2BurnerGnosis.sol` | 51 | `IToken(olas).approve(l2TokenRelayer, 0);` (after `relayTokens`) |
| `contracts/utils/Bridge2BurnerOptimism.sol` | 66 | `IToken(olas).approve(l2TokenRelayer, 0);` (after `withdrawTo`) |

**Verification:**
- ✅ All three subclass implementations have the explicit zero-approval reset
- ✅ Each sits inside the reentrancy-locked block (between `_locked = 2` acquire and `_locked = 1` release)
- ✅ Comment style consistent across the three files: «defensive — bridge consumes the exact approved amount, but explicit zero is hygiene»
- ✅ Polygon variant (no approval flow under M-1's transfer-based design) — correctly N/A; no unnecessary approve added

**Disposition**: claim accurate.

### 1.3 M-09 saturating subtraction at year-boundary downward inflation ✅ Fixed in code, 🟡 redeploy pending (verified)

**Claim** ([FINAL_REVIEW.md §2 M-09](FINAL_REVIEW.md), VL #24, commit [`9447968`](https://github.com/valory-xyz/autonolas-tokenomics/commit/9447968) on PR #276): a new `else if (incentives[4] < curMaxBond)` branch in `Tokenomics.checkpoint()` reduces `effectiveBond` by `(curMaxBond - incentives[4])`, flooring at zero when bonders have already consumed more than the post-correction inflation cap allows.

**Code at HEAD** (`contracts/Tokenomics.sol:1178-1188`):

```solidity
if (incentives[4] > curMaxBond) {
    // Adjust the effectiveBond upward
    incentives[4] = effectiveBond + incentives[4] - curMaxBond;
    effectiveBond = uint96(incentives[4]);
} else if (incentives[4] < curMaxBond) {
    // Adjust the effectiveBond downward, flooring at zero for the edge case where bonders have
    // already consumed more than the new cap allows. The reset direction stays conservative —
    // it under-counts remaining bond capacity, never over-counts, so no OLAS can be over-minted.
    uint256 overCredited = curMaxBond - incentives[4];
    effectiveBond = (effectiveBond > overCredited) ? uint96(effectiveBond - overCredited) : 0;
}
```

**Verification:**
- ✅ The branch is added (downward-correction path now exists where it didn't pre-fix)
- ✅ Saturating subtraction is correct — guards against the underflow case `effectiveBond < overCredited`
- ✅ Conservative direction — under-counts remaining capacity, never over-counts; cannot over-mint OLAS
- ✅ Comment cites C4A 2026-01 S-1030 / Internal audit 15 M-04 — provenance is recorded
- ✅ VL #24 entry tracks the «accepted residual» framing for already-realized over-issuance under the pre-fix code (Y2→Y3 boundary already past)

**Disposition**: code claim accurate. On-chain status (🟡) carried forward unchanged from internal-15 — see §4 below for the deployment-side note.

### 1.4 VL doc — four new accepted-residual entries (verified)

**Claim** (commits [`ec4bc9a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ec4bc9a), [`7255ba5`](https://github.com/valory-xyz/autonolas-tokenomics/commit/7255ba5)): four new VL entries land in `docs/Vulnerabilities_list_tokenomics.md`:

| VL # | Title | Disposition tracked |
|---|---|---|
| 21 | Depository OLAS transfer return value not checked | Accepted residual — OLAS is canonical revert-on-failure ERC20 |
| 22 | Bridge2BurnerOptimism `TOKEN_GAS_LIMIT` hardcoded | Accepted residual — bridge replay available for operational tail |
| 23 | `setV2Oracles` and `setV3Pools` not mutually exclusive | Operational footgun — owner-only setters with symmetric on-chain gate |
| 24 | Tokenomics M-09 `effectiveBond` saturating subtraction at year boundaries | Intentional design — alternative carry-forward debt would penalize future periods |

**Verification:**
- ✅ All four entries exist in `docs/Vulnerabilities_list_tokenomics.md` (lines 359-427)
- ✅ Each entry cross-references its source (C4R submission ID where applicable, internal-16 finding label, internal-audit cycle origin)
- ✅ Each entry's disposition language is consistent with the claim in [`README.md`](README.md) (no overstatement, no understatement)
- ✅ Numbering picks up cleanly from the prior VL state (#1-20) without renumbering or removing existing entries

**Disposition**: claim accurate.

### 1.5 Internal-16 LOW/INFO items — accepted residuals or rejected (verified)

| ID | Disposition | Verification |
|---|---|---|
| L-NEW-1 (Optimism `TOKEN_GAS_LIMIT` hardcoded) | 📝 VL #22 | ✅ Entry present in VL doc; `Bridge2BurnerOptimism.sol:41` retains `uint32 public constant TOKEN_GAS_LIMIT = 300_000;` (no setter introduced — consistent with «accept residual» disposition) |
| L-NEW-3 (Bridge2Burner family lacks emergency rescue) | ⚖️ Rejected | ✅ No rescue function added to base or any subclass; rejection rationale «preserves trustless model; would expand C-01 EOA blast radius» preserved in [README §3](README.md) |
| L-NEW-4 (Tokenomics integer truncation in incentive pattern) | 📝 Already covered by VL #18 | ✅ VL #18 (`_trackServiceDonations` precision loss) covers same finding class; no new entry needed |
| L-NEW-5 (GenericBondCalculator flash-loan view) | ⚖️ Already mitigated | ✅ Function remains `view`; bond payout uses stored `priceLP` set at create-time per `Depository.sol`; no code change indicated |
| INFO-1 (`setV2Oracles` / `setV3Pools` not mutually exclusive) | 📝 VL #23 | ✅ Entry present; both setters remain owner-only; combined transfer gate handles either-or-both |
| INFO-2 (Depository OLAS transfer return) | 📝 VL #21 | ✅ Entry present; `IToken(olas).transfer(...)` at `Depository.sol:390` unchanged (consistent with «accept residual» disposition) |
| INFO-3 (ABI break impact summary) | doc-only in [README §3](README.md) | ✅ ABI table preserved; in-repo callers verified updated (`scripts/deployment/pol/script_03_buy_back_burner_wire_v3.sh` uses new signature) |

**Disposition**: every internal-16 item has a closure or accepted-residual entry that matches what the code does (or does not do).

### 1.6 C4R 2026-01 tokenomics-scope findings — sampled spot-checks

[`FINAL_REVIEW.md`](FINAL_REVIEW.md) tabulates 28 tokenomics-scope C4R findings with dispositions: 20 ✅ Fixed in code, 6 📝 Documented in VL, 2 🔄 Resolved by replacement, 0 open. This file does not re-verify each one in code (that work is the substance of [`FINAL_REVIEW.md`](FINAL_REVIEW.md) itself). Three high-leverage spot-checks were performed to sanity-check the surrounding closure claim:

| C4R | Sampled file:line | Spot-check outcome |
|-----|---------------------|---------------------|
| **M-09** | `contracts/Tokenomics.sol:1182-1188` | ✅ Saturating subtraction branch present and correct (covered above in §1.3) |
| **L-08** (NeighborhoodScanner precision) | `contracts/pol/NeighborhoodScanner.sol:671-685` | ✅ Single-step `amount · sqrtP² / 2^192` formulation present for `sqrtP ≤ 2^128`; two-step `mulDiv` fallback retained. Matches FINAL_REVIEW.md L-08 row claim. |
| **L-14** (`changeMaxSlippage` no upper BPS) | `contracts/pol/LiquidityManagerCore.sol:638-640` | ✅ `revert Overflow(newMaxSlippage, MAX_BPS)` guard present. Matches FINAL_REVIEW.md L-14 row claim. |

The spot-check is intentionally narrow. A full re-derivation of [`FINAL_REVIEW.md`](FINAL_REVIEW.md)'s 28-row matrix is out of scope for this verification pass — that document's authority for the broader closure story stands. The three spot-checks indicate the document's specific code-line citations are accurate where checked; full re-derivation would only repeat that.

---

## §2. Potential mismatches introduced by the fixes themselves

The closing-PR fixes are correct in code. Below are five auditor-facing concerns the fix architecture invites — none are protocol-breaking; each is a pre-emptive doc / runbook addition candidate that closes off the most likely third-party-auditor follow-up question after they verify the fix mechanics and look for «what changed and what could surprise me».

### 2.1 Polygon `l2TokenRelayer` field semantically repurposed — name vs purpose mismatch

**What the fix did**: reused the inherited `Bridge2Burner.l2TokenRelayer` immutable to hold the Polygon bridge mediator address (a governance-controlled L2 contract reached via fx-portal). The base contract's field semantic is «L2 token relayer» — i.e., the L2 endpoint of the L2-to-L1 bridge. The Polygon variant's actual content is conceptually different: it is not a bridge endpoint at all, just an ERC20 recipient on L2.

**What an auditor could flag**:
- A reader of base `Bridge2Burner.sol` learns `l2TokenRelayer` means «the L2 address that talks to the bridge primitive». A reader of `Bridge2BurnerPolygon.sol` who skims the inherited field name (without reading the rewritten NatSpec) might assume the same.
- Off-repo consumers (subgraph indexers, monitoring scripts, deploy verifiers) that read `bridge2Burner.l2TokenRelayer()` from the contract ABI will get the bridge mediator address on Polygon and the actual bridge endpoint on the other three chains — semantically heterogeneous results from the same getter.
- A future contributor adding a new chain variant could mistakenly read the Polygon implementation, copy the «store mediator in `l2TokenRelayer`» pattern, and apply it where the actual bridge primitive needs the field.

**Mitigation candidates** (all doc-only, no code change required):
1. Add a one-line warning in base `Bridge2Burner.sol` NatSpec that the `l2TokenRelayer` field's interpretation is per-subclass and Polygon's is non-standard.
2. Or: add a per-chain getter alias (e.g., `bridgeMediator()` on Polygon that returns `l2TokenRelayer`) for off-repo consumers that prefer semantic naming. Pure code-readability addition; no security change.
3. Or: document the heterogeneity explicitly in the deploy runbook for off-repo monitoring tools.

**Auditor concern level**: low — documentation hygiene only; no security impact.

### 2.2 Polygon path semantic shift: automatic burn → governance-mediated disposition

**What the fix did**: M-1 closed the «OLAS goes to dead L1-mirror» bug by routing OLAS to the L2 bridge mediator instead. The fix does not perform the burn — final disposition (keep, transfer, trigger PoS-bridge burn) is governance's call once the OLAS is sitting on the mediator.

**What an auditor could flag**:
- The other three Bridge2Burner variants (Arbitrum / Gnosis / Optimism) deliver OLAS directly to `OLAS_BURNER` on L1. The buy-and-burn flow on those chains is automatic at the contract level — once `relayToL1Burner()` succeeds, OLAS is in the canonical burn address.
- The Polygon variant ends at the mediator. The buy-and-burn promise on Polygon now requires a separate governance action to complete.
- Without an explicit committed governance process (timing, mechanism, who triggers, when), a third-party reader cannot verify that the buy-and-burn flow on Polygon actually completes. The OLAS could in principle sit on the mediator indefinitely.
- The NatSpec at `Bridge2BurnerPolygon.sol:32-36` says «final disposition is governance's call» but does not commit to a process.

**Realized impact considerations**:
- The current `MIN_OLAS_BALANCE = 100 ether` floor in the base means `relayToL1Burner()` only fires above 100 OLAS — Polygon's buy-back cadence is bounded.
- OLAS at the bridge mediator is not at-risk (mediator is governance-controlled); it is just not yet at the canonical burn address.
- If governance never acts, the supply-reduction effect of buy-and-burn on Polygon is delayed but not abandoned.

**Mitigation candidates** (mostly doc-side):
1. Add an operator runbook entry: «Polygon-side OLAS accumulating at the mediator address requires a governance proposal to forward to L1 burn. Trigger when accumulated balance exceeds [threshold].»
2. Add a public dashboard / monitoring alert on `bridgeMediator OLAS balance > X` so downstream observers see when governance action is due.
3. Optional code addition (out of this PR's scope): a permissionless `triggerMediatorBurn()` function on the mediator that calls `RootChainManager.exit(...)` once accumulated and then burns at L1. Adds operational complexity; «governance-mediated» disposition explicitly avoids this.

**Auditor concern level**: medium — completeness of the buy-and-burn flow on Polygon, not a code bug. Most likely follow-up question from a third-party reviewer who maps the Polygon flow against the Optimism/Arbitrum/Gnosis flows and asks «where is the burn step on Polygon?»

### 2.3 Polygon deploy-time bridge mediator address verification

**What the fix did**: deploy script `scripts/deployment/pol/deploy_00c_bridge2burner_polygon.sh` reads `bridgeMediatorAddress` from globals and passes it as the second constructor argument. The constructor inherits the base's zero-address check (`_l2TokenRelayer != address(0)`) but does not verify the address is actually a governance-controlled mediator.

**What an auditor could flag**:
- If `globals_polygon_mainnet.json` is corrupted, or the deploy operator pastes a wrong address, OLAS released by `relayToL1Burner()` flows to whatever address was supplied. The contract has no on-chain way to verify the supplied address is the canonical mediator.
- This is a generic deploy-script trust assumption that applies to many addresses in this codebase, but here the scope is specifically the destination of OLAS that the buy-back flow has already accumulated.

**Mitigation candidates**:
1. Pre-flight verifier script (paralleling the post-deploy verifier suite mentioned in [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md)) that checks the configured `l2TokenRelayer` address against an expected canonical mediator address.
2. Or: document in the deploy runbook that the mediator address must be confirmed against the canonical Olas governance registry before the deploy tx is signed.
3. Or: switch the Polygon variant to a setter pattern (`setBridgeMediator(address)` ownership-gated post-deploy) so an initial deploy can be corrected. Trade-off: introduces ownership-trust to a currently constructor-immutable field.

**Auditor concern level**: low — operational; trust placed in deploy process and globals integrity. Mitigated by the existing post-deploy verifier discipline carried over from internal-15.

### 2.4 M-09 Y2→Y3 phantom capacity already realized — no quantification provided

**What the fix did**: the saturating-subtraction branch (verified §1.3) prevents future drift at year-boundary downward inflation transitions. VL #24 explicitly notes that the Y2→Y3 boundary (2025-06-30) is already past at 2026-05-06; phantom bond capacity from that boundary may have already been realized on the live `0xc096…ce300` proxy under the pre-fix code.

**What an auditor could flag**:
- VL #24 frames the realized impact as «small — a one-time minor over-issuance bounded by the difference between old- and new-inflation rates over the transition epoch — and not exploitable for ongoing extraction». No numerical quantification is provided.
- A third-party auditor verifying supply integrity of OLAS may want a concrete number: how much extra OLAS could have been minted into bonds during Y2→Y3 due to this issue, and how much actually was?
- The fix prevents future drift at Y9→Y10 (2032-06-30 approx) but only if the Tokenomics impl is redeployed before that boundary.

**Mitigation candidates** (mostly transparency / runbook):
1. Compute and publish: difference between (effective bond capacity actually consumed during the Y2→Y3 transition epoch under the pre-fix code) and (the post-fix correct capacity). Numbers can be derived from on-chain `effectiveBond` slot reads + known epoch timestamps + `getInflationForYear` constants.
2. Document the Y9→Y10 redeploy commitment timeline explicitly — the [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) §1 action items mention the redeploy is pending; an explicit «before [date]» commitment would close the auditor concern.

**Auditor concern level**: medium — DAO transparency. The fix is correct; the gap is in publicly-available impact quantification.

### 2.5 M-09 fix lands in code but redeploy pending — operational tail

**What the fix did**: the M-09 code change is in `contracts/Tokenomics.sol` on the merge-target branch. Tokenomics is a proxied contract (`TokenomicsProxy + Tokenomics.sol`); the deployed implementation behind `0xc096…ce300` is the prior Tokenomics impl without this fix. A new Tokenomics impl deployment + Timelock `changeImplementation` is required to make the fix live on-chain.

**What an auditor could flag**:
- A reader of «✅ Fixed in code» without reading internal-15's deployment matrix would assume the fix is live on mainnet. It is not.
- The Y9→Y10 boundary, while still ahead, is binding on the deployed code path — if the redeploy doesn't land before that boundary, the same phantom-capacity issue would repeat.
- The internal-16 closing-PR carries the «🟡 redeploy required to be live on-chain» disposition forward unchanged from internal-15, but does not commit to a redeploy date.

**Mitigation candidates**:
1. Add a row to [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md)'s Code/Deployment matrix specifically tracking «when is the M-09 redeploy committed to land?»
2. Or: add a pre-deployment runbook checklist item that gates the Y9→Y10 boundary on redeploy completion (e.g., «if M-09 is not live on `0xc096…ce300` by [date], flag as P0 ops escalation»).

**Auditor concern level**: low — operational; no code finding. The disposition is honest in [`audits/internal15/FINAL_REVIEW.md`](../internal15/FINAL_REVIEW.md) — this row just makes the open commitment explicit.

---

## §3. Bridge2Burner base abstract-virtual refactor — clean

The closing-PR also declares `Bridge2Burner.relayToL1Burner()` as `external virtual` (abstract) so that all four subclasses use `override`. Verified at `contracts/utils/Bridge2Burner.sol:70` — the base function has no implementation; signature `function relayToL1Burner() external virtual;`. Each of the four subclasses (`Arbitrum`, `Gnosis`, `Optimism`, `Polygon`) declares the function as `external virtual override`.

This is a clean refactor — no on-chain behavior change (the existing deployed concrete subclasses had their own implementation regardless), no storage layout change, no constructor ABI change. No auditor concern.

---

## §4. Verdict

**Status of claims in [`README.md`](README.md) and [`FINAL_REVIEW.md`](FINAL_REVIEW.md) at branch HEAD `7255ba5`**:

| Claim | Verification |
|---|---|
| M-1 Polygon Bridge2Burner ✅ Fixed | ✅ Verified in code (§1.1) |
| L-NEW-2 approval cleanup ✅ Fixed | ✅ Verified in code (§1.2) |
| M-09 saturating subtraction ✅ Fixed in code (🟡 redeploy pending) | ✅ Verified in code (§1.3); deployment status unchanged from internal-15 |
| VL doc #21–#24 added with correct dispositions | ✅ Verified in `docs/Vulnerabilities_list_tokenomics.md` (§1.4) |
| L-NEW-1, L-NEW-3, L-NEW-4, L-NEW-5, INFO-1, INFO-2, INFO-3 dispositions | ✅ Verified in code or VL doc (§1.5) |
| C4R 2026-01 tokenomics-scope full closure (28 findings) | Sampled (§1.6); document authority for the broader matrix stands |

**Net**: every disposition claimed in the two preceding files matches the code at the branch HEAD. No claim is overstated; no claim is understated.

**Mismatches introduced by the fixes themselves** (§2): five pre-emptive auditor-facing concerns, none protocol-breaking. The most likely third-party follow-up after a fix-mechanics review:

| # | Concern | Severity | Mitigation |
|---|---|---|---|
| 2.1 | `l2TokenRelayer` field semantically repurposed for Polygon mediator | low (doc) | NatSpec note in base; deploy runbook hygiene |
| 2.2 | Polygon path: automatic burn → governance-mediated disposition | medium (completeness) | Operator runbook for mediator-balance threshold + governance trigger |
| 2.3 | Polygon deploy-time bridge mediator address verification | low (op) | Pre-flight verifier in deploy runbook |
| 2.4 | M-09 Y2→Y3 phantom capacity already realized — no quantification | medium (transparency) | Compute and publish realized over-issuance; commit to Y9→Y10 redeploy date |
| 2.5 | M-09 fix lands in code but redeploy pending | low (op) | Track redeploy commitment in Code/Deployment matrix |

**Recommendation**: branch is mergeable. The five concerns above are pre-emptive doc additions — not blocking the merge, but worth landing before the next external audit cycle so the fix story arrives at third-party reviewers with the most-likely follow-up questions already addressed in writing.

The verdict carry-over from [`README.md`](README.md) ⚠ **PASS-WITH-FINDINGS** is preserved; this verification adds **PASS** for the fix-and-disposition claims at the post-fix HEAD plus five doc/runbook recommendations to be addressed in a later pass.

---

### Doc metadata

- **Branch under review**: `fix-internal16-bridge2burner-and-vl-followups`
- **HEAD reviewed**: `7255ba5`
- **Companion documents in this slot**: [`README.md`](README.md), [`FINAL_REVIEW.md`](FINAL_REVIEW.md)
- **Related commits**: [`ec4bc9a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ec4bc9a) (M-1 + L-NEW-2 + VL #21–#24 added), [`7255ba5`](https://github.com/valory-xyz/autonolas-tokenomics/commit/7255ba5) (README dispositions doc-only update)
