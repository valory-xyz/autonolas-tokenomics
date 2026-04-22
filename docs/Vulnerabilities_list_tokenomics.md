# Contracts vulnerabilities

## Vulnerabilities list

- [Involved contracts and level of the bugs](#involved-contracts-and-level-of-the-bugs)
- [Vulnerabilities](#vulnerabilities)
  - [1. depositServiceDonationsETH function (services state)](#1-depositservicedonationseth-function-services-state)
  - [2. depositServiceDonationsETH function (OLAS incentives)](#2-depositservicedonationseth-function-olas-incentives)
  - [3. deposit method](#3-deposit-method)
  - [4. checkpoint method - cross-year](#4-checkpoint-method---cross-year)
  - [5. Treasury Fund Token Management](#5-treasury-fund-token-management)
  - [6. Encoded inflation schedule](#6-encoded-inflation-schedule)
  - [7. Withheld tokens](#7-withheld-tokens)
  - [8. changeManagers function (specifically - voteWeighting)](#8-changemanagers-function-specifically---voteweighting)
  - [9. claimStakingIncentives / _calculateStakingIncentivesBatch functions](#9-claimstakingincentives--_calculatestakingincentivesbatch-functions)
  - [10. migrate function](#10-migrate-function)
  - [11. _sendMessage function](#11-_sendmessage-function)
  - [12. calculateStakingIncentives function (public state-mutating call bricks zero-weight epoch refund)](#12-calculatestakingincentives-function-public-state-mutating-call-bricks-zero-weight-epoch-refund)
  - [13. updateInflationPerSecondAndFractions function (effectiveBond reset)](#13-updateinflationpersecondandfractions-function-effectivebond-reset)
  - [14. BalancerPriceOracle.updatePrice flash-loan steerability within minUpdateInterval](#14-balancerpriceoracleupdateprice-flash-loan-steerability-within-minupdateinterval)
  - [15. LiquidityManagerCore.convertToV3 front-run via permissionless collectFees](#15-liquiditymanagercoreconverttov3-front-run-via-permissionless-collectfees)
  - [16. LiquidityManagerCore slippage derived from spot-derived amounts in _increaseLiquidity / _decreaseLiquidity](#16-liquiditymanagercore-slippage-derived-from-spot-derived-amounts-in-_increaseliquidity--_decreaseliquidity)
  - [17. changeRegistries can lock pending user incentives](#17-changeregistries-can-lock-pending-user-incentives)
  - [18. _trackServiceDonations precision loss via integer division](#18-_trackservicedonations-precision-loss-via-integer-division)
  - [19. checkpoint permanently unusable after MAX_EPOCH_LENGTH without a call](#19-checkpoint-permanently-unusable-after-max_epoch_length-without-a-call)
## Involved contracts and level of the bugs

The present document describes issues affecting Tokenomics contracts.

## Vulnerabilities

### 1. `depositServiceDonationsETH` function (services state)

**Severity**: Low

The following function is implemented in the Treasury contract:

```solidity
function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable
```

This service donating function calls another function from the Tokenomics contract that ultimately results in calling the internal function `_trackServiceDonations()`. The latter one checks whether agent and component Ids of each of the passed service Id exist, and if not, reverts with the `ServiceNeverDeployed()` error. The error arises from the fact that the service was never deployed, and its underlying component and agent Ids were not assigned (the assignment of underlying component and/or agent Ids to a service happens during the deployment of the service itself).

However, after a specific service is deployed at least once and then terminated, it can be updated and re-deployed again. In particular, the service can be updated with a different set of agent Ids, making the donation distribution setup invalid for the following reason. If this updated service receives a donation before it is re-deployed, the donation will be distributed between its old component and agent Ids owners and not the new ones.

Therefore, donating to an updated service before its redeployment can affect the correct distribution of rewards in the Tokenomics contract. We recommend not to donate when a service is not in the `Deployed` or `TerminatedBonded` state (e.g. any service with *serviceIds[i]* not in `Deployed` or `TerminatedBonded` state must not be passed as input parameters to the function **depositServiceDonationsETH**). The state of the service can be easily checked via the ServiceRegistry contract view function `getService(uint256 serviceId)`.

### 2. `depositServiceDonationsETH` function (OLAS incentives)

**Severity**: Informative

The following function is implemented in the Treasury contract:

```solidity
function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable
```

If a DAO member, holding the veOLAS threshold[^1], uses this method to donate ETH to a specific service, or if the service owner is a DAO member holding the veOLAS threshold[^2], the owners of the agents and components referenced in that service are entitled to receive a share of the donation and OLAS top-ups generated through inflation.

While the current approach encourages service registration and donations through the utilization of all available OLAS each epoch, this might be utilized in a counter-intended way by malicious donators or malicious service-owners. If a donator (or the service-owner) owns all the underlying components and agents, meets the sufficient veOLAS requirement, and makes only a small donation to their service, they could accrue a significant number of OLAS tokens through inflation top-ups at a low cost. This behavior may yield considerable gains initially but becomes less profitable as more major players utilize the protocol, leading to more donations being distributed among multiple services and stakeholders.

[^1]: Currently, the threshold for participation is set at 10000 veOLAS, and adjustments to this threshold can be made through a governance voting process.
[^2]: Currently, the threshold for participation is set at 10000 veOLAS, and adjustments to this threshold can be made through a governance voting process.

### 3. `deposit` method

**Severity**: High

In the depository contracts, the following method is implemented:

```solidity
function deposit(uint256 productId, uint256 tokenAmount) external
```

This method allows users to deposit tokens, acquiring OLAS tokens at a discounted rate. A potential concern can arise ten years after OLAS token launch in the case of an epoch crossing into year intervals. In this scenario, a portion of OLAS becomes mintable only in the eleventh year, as a result of the 1 billion fixed supply constraint for the initial ten years.

The creation of bonding programs with payouts leading to exceeding the total OLAS supply mintable before ten years and the bonder's depositing the full amount expecting these payouts lead to a silent return in the OLAS `mint()` method and not a revert. This results in successful product deposit and a consequent loss of OLAS payouts for bonders.

To address this, a more specific check for epoch crossing year intervals can be integrated into the tokenomics `checkpoint()` method. In the absence of redeploying a new contract, it is recommended to carefully propose the creation of bonding programs at the end of the tenth year. These programs should be structured ensuring that the payouts are designed to keep the total amount of OLAS minted below 1 billion OLAS before the ten-year mark. This precautionary measure prevents eventual lost OLAS payouts.

### 4. `checkpoint` method - cross-year

**Severity**: Informative

In the tokenomics contracts, the following method is implemented:

```solidity
function checkpoint() external
```

This method allows users to deposit tokens, acquiring OLAS tokens at a discounted rate. A potential concern may arise in the event of an epoch crossing into year intervals, where a portion of OLAS larger than the year inflation limit becomes mintable.

The creation of bonding programs with payouts leading to an excess of the total OLAS supply mintable before the specified year and the bonder depositing the full amount may result in an amount of minted OLAS exceeding the year inflation limit. It's crucial to note that, at most, only the amount reserved for the remaining time of the epoch from the following year can be minted.

To address this, a more specific check for epoch crossing year intervals can be integrated into the tokenomics `checkpoint()` method. In the absence of redeploying a new contract, it is recommended to carefully propose the creation of bonding programs for epoch-crossing years. These programs should be structured to ensure that the payouts are designed in a manner that keeps the total amount of OLAS minted below the year inflation limit.

### 5. Treasury Fund Token Management

**Severity**: Informative

By design, within the Treasury contract, there is currently no mechanism in place to facilitate the removal of tokens other than ETH that have not been added to the Treasury through the treasury *depositTokenForOLAS()* method.

Therefore, we strongly recommend refraining from transferring funds directly to the Treasury contract that does not adhere to the established tokenomics logic. This precautionary measure will help prevent potential freezing of funds within the Treasury contract.

### 6. Encoded inflation schedule

**Severity**: Informative

If donors in a given epoch fail to meet the veOLAS threshold for donating ETH to specific services within 10 years of OLAS token creation, the reserved OLAS inflation for top-ups remains inactive. Although accounted for in the inflation schedule of that epoch, that amount is essentially deducted from the inflation schedule. For instance, if x OLAS were accounted for in the inflation for top-ups during the inaugural tokenomics epoch but no donator meets the veOLAS threshold, these top-ups cannot be utilized for subsequent epochs encoded in the 10-year inflation schedule.

A similar scenario can occur when OLAS top-ups and staking incentives are distributed. Due to the natural rounding behavior of Solidity and the division involved in calculating top-ups and staking emissions, it's possible that the actual sum of OLAS allocated to owners of agents and components referenced in donated services and the calculated staking emissions might be slightly less than the exact amount that can be extracted from the encoded inflation schedule in the tokenomics contract. In such cases, the difference between the exact amount and the actually allocated amount for top-up and staking is implicitly deducted from the inflation schedule.

This deferred inflation isn't lost; rather, it's postponed, as the OLAS token ensures that no more than 1 billion tokens are minted within a decade, with no more than 2% of the supply cap being minted annually, starting from 1 billion.

### 7. Withheld tokens

**Severity**: Informative

The TargetStakingDispenser contract on L2 withholds some staking emissions sent by L1 (see the section "Verification on staking contract enabled by StakingVerifier" [here](https://staking.olas.network/poaa-whitepaper.pdf) for details on the tokens withheld by the TargetStakingDispenser).

To prevent L1 from sending new emissions while there are still withheld emissions on the TargetStakingDispenser, we need to ensure regular synchronizations between L1 and L2. Specifically, if there is demand for emissions for a specific contract on L2, and L1 is synchronized with the withheld amount on the TargetStakingDispenser, L1 will only send a message without minting or sending new emissions to the L2 target contract until the withheld amount is fully utilized and additional demand arises.

Additionally, if there is no new demand for emissions from the L2 target dispenser and a withheld amount remains, the DAO can initiate a new staking campaign to utilize the withheld amount.

Finally, the DAO can employ the combination of the functions **migrate()**, **syncWithheldAmount()**, **processDataMaintenance()**, **updateWithheldAmountMaintenance()** to transfer and update balance of the withheld tokens to a DAO-controlled account.

### 8. `changeManagers` function (specifically - voteWeighting)

**Severity**: Informative

The following function is implemented in the Dispenser contract:

```solidity
function changeManagers(address _tokenomics, address _treasury, address _voteWeighting) external
```

The purpose of this function is to change core tokenomics contract addresses. However, when the Vote Weighting contract address is changed, if not all the staking incentives are claimed, those can be lost. The idea is to force claim all the staking incentives before the voteWeighting is updated. More details [here](docs/deployment_v1.2.md).

### 9. `claimStakingIncentives` / `_calculateStakingIncentivesBatch` functions

**Severity**: Low

Following functions is implemented in the Dispenser contract:

```solidity
function claimStakingIncentives(uint256 numClaimedEpochs, uint256 chainId, bytes32 stakingTarget, bytes memory bridgePayload) external payable

function _calculateStakingIncentivesBatch(uint256 numClaimedEpochs, uint256[] memory chainIds, bytes32[][] memory stakingTargets) internal returns (uint256[] memory totalAmounts, uint256[][] memory stakingIncentives, uint256[] memory transferAmounts)
```

The purpose of these functions is to calculate staking incentives and returns according to the staking target provided. However, these functions do not account for the fact that the amount of OLAS previously sent to L2 and communicated as not used and available for re-usage (`withheldAmount`) should also be subtracted from the staking incentives amount in favor of amounts returned back to Tokenomics. This means that staking incentives amounts that are reused from withheld ones are calculated as subject to inflation used, whereas in fact that part of inflation is untouched. Ultimately it results in spending less inflation throughout the inflation period for the amount of funds that were minted but withheld on L2 target dispenser contracts as over-excessive.

Note that the inflation amount is not returned to Tokenomics due to `withheldAmount` reuse is never minted, meaning there is no loss of funds, just the inflation miscalculation lowering its yearly mint possibility. In the absence of redeploying a new contract, the DAO might act to adjust the inflation numbers in a distant timeline consolidating information about all the withheld amounts across chains.

### 10. `migrate` function

**Severity**: Low

The following function is implemented in the TargetDispenserL2 contract:

```solidity
function migrate(address newL2TargetDispenser) external
```

The purpose of this function is to migrate all the funds to a new L2TargetDispenser address. However, this function does not check if the current `withheldAmount` value is zero before migrating, essentially having the possibility to lose the inflation information for not sending additional funds to L2.

In order to avoid the loss of `withheldAmount`, the DAO is advised to update the value with the **updateWithheldAmountMaintenance()** function call right after the TargetDispenser migration procedure is complete.

### 11. `_sendMessage` function

**Severity**: Low

The following function is implemented in the OptimismDepositProcessorL1 contract:

```solidity
function _sendMessage(address[] memory targets, uint256[] memory stakingIncentives, bytes memory bridgePayload, uint256 transferAmount, bytes32 batchHash) internal override returns (uint256 sequence, uint256 leftovers)
```

This function forms required data to send tokens and messages to L2 in all the optimism deposit processor related contracts. A user-controlled gas limit is decoded as a uint256, which is later truncated to uint32 when passed to the CrossDomainMessenger. If a user supplies a payload with a value exceeding type(uint32).max, the truncation produces a much smaller gas limit than intended, bypassing the protocol's minimum gas check.

Although this action does not result in loss of funds (which are sent separately), it could deliberately pass a smaller amount of gas such that a corresponding function on L2 reverts. This can then be corrected via the **processDataMaintenance()** function. In the absence of contract re-deployment, users are advised to pass a sufficient amount of gas, or just have it set to zero, such that the fallback value takes care of it.

### 12. `calculateStakingIncentives` function (public state-mutating call bricks zero-weight epoch refund)

**Severity**: High
**Source**: Code4rena 2026-01 Olas audit (submission #S-907)

The following function is implemented in the Dispenser contract:

```solidity
function calculateStakingIncentives(uint256 numClaimedEpochs, uint256 chainId, bytes32 stakingTarget, uint256 bridgingDecimals) public returns (uint256 totalStakingIncentive, uint256 totalReturnAmount, uint256 lastClaimedEpoch, bytes32 nomineeHash)
```

The function is public and state-mutating. During iteration, if totalWeightSum == 0, it writes a one-way flag `mapZeroWeightEpochRefunded[j] = true`, but the function itself does not execute the actual refund (`Tokenomics.refundFromStaking`). Since future callers skip epochs where this flag is set, any external caller can permanently mark a zero-weight epoch as "refunded" without the refund ever being performed, effectively bricking the staking refund for that epoch.

In order not to re-deploy the contract, the protocol just needs to delegate a minimal (0.01%) vote for a specific staking contract, such that the totalWeight is never zero.

Source code: [Dispenser.sol](contracts/Dispenser.sol)

### 13. `updateInflationPerSecondAndFractions` function (effectiveBond reset)

**Severity**: Informative
**Source**: Internal audit 14

The following function is implemented in the Tokenomics contract:

```solidity
function updateInflationPerSecondAndFractions(uint256 _inflationPerSecond, uint256 _maxBondFraction, uint256 _topUpComponentFraction, uint256 _topUpAgentFraction, uint256 _stakingFraction) external
```

This owner-only function resets `effectiveBond` to just `curMaxBond` (the current epoch's bond allocation), discarding the accumulated leftover bond capacity from all prior epochs. In contrast, `checkpoint()` uses the additive pattern `curMaxBond += effectiveBond` before assigning. On the deployed contract, this would reduce effectiveBond from 5.66M OLAS to 484K OLAS (a 91% drop), temporarily limiting new bond product creation until capacity rebuilds via subsequent `checkpoint()` calls (~242K OLAS per epoch).

This is not externally exploitable: the function is restricted to the contract owner (Timelock = DAO governance). The reset direction is conservative -- it under-counts available bond capacity, never over-counts -- so no OLAS can be over-minted. The DAO must ensure that all bonding products are closed before calling `updateInflationPerSecondAndFractions()`, so that no outstanding product supply exceeds the reset effectiveBond. The effectiveBond rebuilds naturally through subsequent `checkpoint()` calls.

Source code: [Tokenomics.sol](contracts/Tokenomics.sol)

### 14. BalancerPriceOracle.updatePrice flash-loan steerability within `minUpdateInterval`

**Severity**: Medium — accepted residual
**Source**: Internal audit 15 (M-02) / C4A 2026-01 H-03 (partial)
**Status**: Acknowledged — no code change; track via monitoring

`BalancerPriceOracle.updatePrice()` reads spot balances from the Balancer Vault once per `minUpdateInterval` and commits them as the new observation. Within that window, a flash-loan move that happens to coincide with the update is committed to state — the commit-on-success pattern (which fixed the rejected-update corruption from C4A H-11) does not reject the adversarial sample because `getPrice()` returns non-zero on the manipulated balance.

Mitigations in place:
- `updatePrice()` is rate-limited via `minUpdateInterval`, so at most one spot sample per window can land.
- `getTWAP()` enforces `maxStaleness` on `lastObservation`, so obviously-old data is rejected downstream.
- `buyBack(...)` is the only on-chain consumer of the TWAP on the V2 path; V3 uses a separate TWAP source.

Residual risk: within any single `minUpdateInterval`, a well-timed flash-loan move into the Balancer pool can still commit a skewed sample. The fix would be architectural (swap oracle source to Vault-on-swap callbacks or a different TWAP primitive) rather than a small code edit — not planned for this PR.

Mitigation plan: off-chain monitoring of `ObservationUpdated` events against moving-average sanity bands, alert + pause on deviation beyond the configured `maxSlippage`. Escalates to High if `updatePrice` ever becomes permissionlessly callable with a tighter cadence, or if `buyBack` volumes scale to the point where flash-loan damage per window crosses a material threshold.

Source code: [BalancerPriceOracle.sol](contracts/oracles/BalancerPriceOracle.sol)

### 15. `LiquidityManagerCore.convertToV3` front-run via permissionless `collectFees`

**Severity**: Low
**Source**: Code4rena 2026-01 Olas audit (L-02) — tracked forward as internal audit 15 (L-03)

The following functions are implemented in the LiquidityManagerCore contract:

```solidity
function convertToV3(address[] memory tokens, bytes32 v2Pool, int24 feeTierOrTickSpacing, int24[] memory tickShifts, uint16 olasBurnRate, bool scan) external
function collectFees(address[] memory tokens, int24 feeTierOrTickSpacing) external
```

`convertToV3()` expects tokens to be transferred to the contract before the call and consumes the current balance. `collectFees()` is permissionless and, via `_manageUtilityAmounts(tokens, MAX_BPS, true)`, burns all OLAS held by the contract. A keeper that stages a direct OLAS transfer and then calls `convertToV3` in a separate transaction can be front-run by an attacker who calls `collectFees` between the two txs, burning the staged OLAS before it is paired into V3 liquidity.

Exposure: owner-gated conversion flow + permissionless fee collection. The realized risk is low when the operator avoids the "bare direct transfer → convertToV3" pattern; staging OLAS inside the same tx that calls `convertToV3` defuses the race. Document in the admin playbook; the preferred architectural fix (atomic transfer-and-convert path, or a conversion-in-flight flag that skips `collectFees` OLAS burn) is out of scope for internal audit 15's low bundle.

Source code: [LiquidityManagerCore.sol](contracts/pol/LiquidityManagerCore.sol)

### 16. LiquidityManagerCore slippage derived from spot-derived amounts in `_increaseLiquidity` / `_decreaseLiquidity`

**Severity**: Low
**Source**: Code4rena 2026-01 Olas audit (L-04) — tracked forward as internal audit 15 (L-04)

The following internal helpers are implemented in the LiquidityManagerCore contract:

```solidity
function _increaseLiquidity(address pool, uint256 positionId, uint256[] memory inputAmounts) internal
function _decreaseLiquidity(address pool, uint256 positionId, uint16 decreaseRate) internal
```

Both helpers compute `amountsMin[i] = amounts[i] * (MAX_BPS - maxSlippage) / MAX_BPS` using amounts derived from slot0 (`_getPriceAndObservationIndexFromSlot0`), not from the TWAP-derived sqrt price. Even though `changeRanges` / `convertToV3` apply the TWAP deviation guard via `checkPoolAndGetCenterPrice` separately, the slippage math here is anchored to the instantaneous price. Realized worst-case slippage in an admin-initiated op can therefore stack up to `maxSlippage + ±MAX_ALLOWED_DEVIATION` (the deviation band).

Exposure: admin-only surface (`onlyOwner` via `convertToV3` / `changeRanges` / `increaseLiquidity` / `decreaseLiquidity`). The realized risk is low in normal DAO-paced operations, but increases the MEV window on owner-initiated liquidity operations. The architectural fix — use the TWAP-derived center price as the anchor for `amountsMin`, then apply `maxSlippage` — is out of scope for internal audit 15's low bundle.

Source code: [LiquidityManagerCore.sol](contracts/pol/LiquidityManagerCore.sol)

### 17. `changeRegistries` can lock pending user incentives

**Severity**: Low
**Source**: Code4rena 2026-01 Olas audit (L-06)

The following function is implemented in the Tokenomics contract:

```solidity
function changeRegistries(address _componentRegistry, address _agentRegistry, address _serviceRegistry) external
```

`changeRegistries()` updates registry pointers without a pre-condition that pending owner incentives have been claimed. `accountOwnerIncentives()` verifies unit ownership against the *current* registry addresses, so component/agent owners that accrued incentives under the previous registry can lose access to those incentives if a registry swap happens before they claim.

**Disposition:** not planned. The function is owner-gated (Timelock / DAO governance), and the operational workflow is to ensure all outstanding incentives have been claimed before registries are rotated. A migration-preserving implementation is out of scope for this cycle — documented here so the DAO operations playbook tracks it.

Source code: [Tokenomics.sol](contracts/Tokenomics.sol)

### 18. `_trackServiceDonations` precision loss via integer division

**Severity**: Low
**Source**: Code4rena 2026-01 Olas audit (L-09)

The following internal function is implemented in the Tokenomics contract:

```solidity
function _trackServiceDonations(address donator, uint256[] memory serviceIds, uint256[] memory amounts, uint256 donationETH) internal
```

Per-service donation is split across the service's `numServiceUnits` component/agent owners via integer division:

```solidity
uint96 amount = uint96(amounts[i] / numServiceUnits);
```

When `amounts[i] % numServiceUnits != 0`, the remainder is truncated. Aggregated across every donation event each service ever receives, owners collectively receive a few wei less than the donated amount; the lost dust is not credited anywhere and does not inflate `effectiveBond`.

**Disposition:** not planned. The loss per event is bounded by `numServiceUnits − 1` wei (single-digit wei for realistic service sizes), does not accumulate into any exploitable protocol state, and the distribution codepath is on the fading-out Tokenomics donation surface. Documented for completeness; no code change.

Source code: [Tokenomics.sol](contracts/Tokenomics.sol)

### 19. `checkpoint` permanently unusable after `MAX_EPOCH_LENGTH` without a call

**Severity**: Low
**Source**: Code4rena 2026-01 Olas audit (L-13)

The following function is implemented in the Tokenomics contract:

```solidity
function checkpoint() external returns (bool)
```

If `checkpoint()` is not called for a duration that exceeds `MAX_EPOCH_LENGTH` from the last settled checkpoint, subsequent calls can land in a state where arithmetic based on `block.timestamp - prevEpochTime` exceeds the limits embedded in the epoch accounting, permanently wedging the checkpoint advancement path on the live proxy. Recovery would require a Tokenomics implementation upgrade.

**Disposition:** not planned for this audit cycle — the code path is entangled with enough of the `checkpoint()` accounting that landing a surgical fix here without broader refactor risk was deemed not worth the effort. Operationally mitigated by: (a) the DAO's existing keeper cadence, which calls `checkpoint()` well within `MAX_EPOCH_LENGTH`; (b) monitoring alerts on missed checkpoint windows. Documented so a future Tokenomics refactor that opens this code path can bundle the fix.

Source code: [Tokenomics.sol](contracts/Tokenomics.sol)

---

### 21. BuyBackBurner V3 path is per-chain optional (post-internal15 follow-up)

**Severity**: Notes / operational
**Source**: Internal follow-up to PR #272 (`restore-v3-bbb`) deployment audit

The `BuyBackBurner` constructor (`contracts/utils/BuyBackBurner.sol`) takes four addresses: `_liquidityManager`, `_bridge2Burner`, `_treasury`, `_swapRouter`. Prior to this change, all four were checked non-zero. That blocked V2-only chain deployments (gnosis, polygon, arbitrum) where no Uniswap V3 / Slipstream router exists, and forced operators to deploy a `LiquidityManager` upfront on every chain even if V3 was not in scope.

**Resolution.** `_liquidityManager` and `_swapRouter` are now optional — pass `address(0)` to deploy an implementation with the V3 path disabled. `_bridge2Burner` and `_treasury` remain required. A new error `V3PathDisabled()` is reverted by every V3-touching surface when either V3 immutable is unset:

- `buyBack(address, uint256, int24, uint256)` (V3 4-arg overload)
- `_buyOLAS(address, uint256, int24)` (V3 internal — defense in depth)
- `setV3PoolStatuses(address[], bool[])` — pool whitelisting is meaningless without a swap path
- `checkPoolPrices(...)` — gates on `_requireLiquidityManager()` (LM-only) since `swapRouter` is not on its read path

The V2 path (`buyBack(address, uint256, uint256)`) and admin setters (`setV2Oracles`, `setMaxSlippages`, `changeOwner`, `transferToken`, `updateOraclePrice`, `changeImplementation`) are unaffected. `setMaxSlippages` is intentionally ungated because `mapTokenMaxSlippages` is read by both V2 and V3 paths.

**To enable V3 on a chain that initially deployed without it:** deploy a new `BuyBackBurnerUniswap` / `BuyBackBurnerBalancer` implementation with non-zero `_liquidityManager` and `_swapRouter`, then call `changeImplementation` on the proxy. Immutables are encoded in bytecode, so the new impl swap atomically enables the V3 path. Storage maps `mapV3Pools` and `mapTokenMaxSlippages` survive the upgrade.

Source code: [BuyBackBurner.sol](contracts/utils/BuyBackBurner.sol)
Tests: [BuyBackBurnerV3Disabled.t.sol](test/BuyBackBurnerV3Disabled.t.sol) — 19 unit tests covering constructor relaxation, all four guarded surfaces, and V2/admin sanity.

