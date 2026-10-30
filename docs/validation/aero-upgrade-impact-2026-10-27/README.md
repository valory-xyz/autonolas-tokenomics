# Velodrome / Aerodrome upgrade impact

Reviewed 27 October 2026. Tokenomics `origin/main` commit:
`20810f73c865e7961698ce1caf1cc5abed899973`.
Analysis branch: `codex/aero-upgrade-impact`.
Official Aero Slipstream source commit:
`f99f2095918cab69eafeffa2c3d0a8762de737b7`.

## File layout

This review adds five files: two Solidity test files and these three analysis
files: `README.md`, `reproduce.py`, and `evidence.json`. It also modifies the
existing `test/LiquidityManagerBase.t.sol` fixture as described below.

`evidence.json` bundles snapshot, interface, build-record,
and test-log files as exact UTF-8 text with SHA-256 hashes. Evidence filenames
mentioned below identify entries in that bundle, not additional files on disk.
Use `reproduce.py show NAME` to read or extract any original verbatim.
`reproduce.py verify` checks bundle integrity, local contract/test source hashes,
and agreement between build records and saved logs; it does not rerun tests.
The same two test files include Base/Optimism subclasses for lifecycle, startup,
fee-policy, transaction-boundary, withdrawal, and multi-LP accounting cases.
Earlier logs and their exact test-source versions remain archived in the bundle. Use
`reproduce.py show --source SHA256` to extract a historical source version;
the hashes are listed in its original build record. Verification distinguishes
historical runs from runs against current workspace sources.

## Result

The upgrade affects the Base and Optimism Slipstream integration in
`LiquidityManagerBalancerSlipstream` and `BuyBackBurnerBalancer`. Both deployed
integrations still reference legacy contracts. Adoption of Aero requires new
implementation deployments and coordinated configuration; it is not automatic.
The five transaction tuples checked have identical ABI layouts in the published
Aero source. Fork verification on both Base and Optimism passes the lifecycle
suite with the new addresses and simulates upgrading each existing LM proxy.
No production Solidity change was needed for these tests. This is not a general
security certification or a validation of live market depth.

Current-source verification:

| Chain | Block | Aero lifecycle/upgrade | Legacy control | Dynamic startup lifecycle | Fee/withdrawal/policy | Transaction boundary | Total passed / failed |
|---|---:|---:|---:|---:|---:|---:|---:|
| Base | 53153049 | 10 | 9 | 10 | 13 | 1 | 43 / 0 |
| Optimism | 158748334 | 10 | 9 | 10 | 13 | 1 | 43 / 0 |

Each lifecycle/control suite includes two fuzz tests with 256 runs each, using
seed `0xa3e0`, including the inherited dynamic-startup suites. Current logs are
`fork-base-extended.txt` and `fork-optimism-extended.txt`; their build records are
`fork-base-extended-build-record.json` and `fork-optimism-extended-build-record.json`.
The preceding 50-test runs remain archived as historical evidence. All 86 current
tests passed without changing production contracts or weakening existing assertions.

The inspected live state does not demonstrate an immediate V3 failure: both
liquidity-manager proxies held zero NFTs in their configured legacy NPM and in
the Aero NPM, and both burners had WETH and USDC V3 routes unset. This does not
inventory all treasury holdings, other NPM generations, or every token route.
No legacy positions need migration for the checked LM deployments at those blocks.
No direct Velodrome/Aerodrome-specific dependency was identified in the core
Tokenomics, Treasury, Depository, or Dispenser contracts by the source searches.
Indirect liquidity and market effects remain possible.

## Which update?

Two reasonable interpretations were checked:

1. **Slipstream pool/gauge generations.** Aerodrome publishes separate initial,
   Gauge Caps, and Gauges V3 deployments. The Base globals select the initial
   Aerodrome NPM/router, while Optimism selects Velodrome Gauges V2 NPM/router.
   A newer deployment does not redirect an integration bound to an older factory.
   Sources: [Aerodrome deployment list](https://github.com/aerodrome-finance/slipstream/blob/main/README.md),
   [Velodrome deployment list](https://github.com/velodrome-finance/slipstream/blob/main/README.md).
2. **The migration to Aero.** The official hub specifies launch at
   22 October 2026, 00:00 UTC, with replacement token and liquidity infrastructure.
   It explicitly says legacy pools remain live but stop receiving emissions, and
   that some LP deposits require manual withdrawal if no matching destination exists.
   These are published protocol statements, not pool-by-pool transaction tests.
   Source: [Aero upgrade hub, including partner guidance](https://aero.xyz/aero-upgrade/).

## Contracts and mechanisms

| Component | Evidence in tokenomics | Consequence |
|---|---|---|
| `LiquidityManagerBalancerSlipstream` / `LiquidityManagerTargetSlipstream` | `contracts/pol/LiquidityManagerTargetSlipstream.sol`: tick-spacing `mint` and factory `getPool`. `LiquidityManagerCore.sol:153`: immutable NPM and factory; factory is derived from the NPM in the constructor. | Existing implementation continues to target its legacy factory. A new implementation with the replacement NPM is needed to target Aero. |
| `BuyBackBurnerBalancer` | `contracts/utils/BuyBackBurnerBalancer.sol:148`: swap through immutable `swapRouter`, using the selected pool's tick spacing. `BuyBackBurner.sol:393`: whitelist checks pools against the liquidity manager's factory. | Reconfigure NPM/factory, router, and pool whitelist together. A new-factory pool normally fails the old factory's whitelist check. Changing only the manager can instead leave price validation and swap execution using different factories. |
| `LiquidityManagerCore` price guard | Low-level `slot0` reader at line 237; `observations` and `observe` in the oracle path. `SECONDS_AGO = 1800`. | Published Aero interfaces retain the values used by this reader. New or inactive pools can still fail the history guard. ABI similarity alone does not establish adequate liquidity or oracle history. |
| Position bookkeeping | `mapPoolAddressPositionIds` is keyed by pool; operations use the implementation's NPM. Owner can transfer a tracked NFT with `transferPositionId` before upgrading. | Switching NPM does not migrate NFTs or rebuild the pool-to-position mapping. Any legacy positions must be handled before rebinding an existing proxy. |
| VELO/AERO tokens and gauges | No direct VELO/AERO token address, veNFT, or protocol gauge call was found in the integration source. | No direct token-conversion or gauge-staking adaptation was identified here. This does not establish that protocol-controlled wallets hold none of these assets. |

The additional fee tests below reconcile both tokens and reproduce a buyback
reverting at its output floor after a controlled increase in the dynamic fee.
The burner derives that floor from a TWAP quote and configured slippage. Its
protection remains effective, but fee changes affect output and execution.

## Recorded deployment state

`snapshot.json` records raw read-only RPC responses, addresses, code lengths,
chain IDs, block numbers and block hashes. Collection finished at
2026-10-27 10:04:13 UTC (11:04:13 Europe/Rome).

| Chain | Pinned block | Deployed manager factory | Published Aero factory, also returned by new NPM/router |
|---|---:|---|---|
| Base (8453) | 53153049 | `0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A` | `0x9CB220581b91b0C83223012FE69688b92aD07a76` |
| Optimism (10) | 158748334 | `0xe13Dd1fbA721Aa81a1826D9523AC9BC7d260c879` | `0xfeaB42D90055db3a0616249f76B6002D72266778` |

The manager NPM and burner router getters agree with repository globals on both
chains. In each chain, both the legacy NPM/router and the Aero NPM/router agree
on their respective factories. Code exists at the queried integration addresses.
Zero NFT balances and unset WETH/USDC V3 mappings are recorded in `calls`.

Replacement addresses are taken from the pinned official manifests:
[Base](https://github.com/Dromos-Labs/metadex-slipstream-public/blob/f99f2095918cab69eafeffa2c3d0a8762de737b7/deployment-addresses/cl-base.json),
[Optimism](https://github.com/Dromos-Labs/metadex-slipstream-public/blob/f99f2095918cab69eafeffa2c3d0a8762de737b7/deployment-addresses/cl-optimism.json).

## Interface checks and limits

`interfaces.json` records matching field types and order for `MintParams`,
`ExactInputSingleParams`, `IncreaseLiquidityParams`, `DecreaseLiquidityParams`,
and `CollectParams`, plus SHA-256 hashes of the inspected upstream interfaces.
Manual source inspection also checked factory lookup, `observations`, `observe`,
and the leading `slot0` words. Aero `slot0` returns six words while the generic
Uniswap interface declares seven; the manager already reads only the first and
third words with a low-level call. The NPM `positions` spacing field is signed
in Slipstream but unsigned in the generic local interface; positive supported
tick spacings share the same ABI word encoding. These checks do not validate
all behavior or all output decoding cases.

No production transaction, production Solidity change, deployment-address update,
or upgrade proposal was made. The fork verification covers replacement
Aero contracts on both Base and Optimism.

## Original Base fork verification

`test/LiquidityManagerAeroBase.t.sol` inherits the Base lifecycle suite and changes
only the fixture's NPM, factory, and router addresses. It executes the existing
LM, burner, and bridge implementation source against the deployed Aero contracts
at Base block **53153049**. Both suites run with the same fixed fuzz seed.

| Suite | Test functions passed | Failures | Fuzz runs per fuzz test |
|---|---:|---:|---:|
| Aero Base | 10 | 0 | 256 |
| Legacy Base control | 9 | 0 | 256 |

The raw output is `fork-base-comparison.txt`; build settings and source hashes
are in `fork-build-record.json`. The passing tests cover factory pool creation
and initialization during setup, NPM seed minting and withdrawals, oracle
warm-up, Balancer-to-Slipstream conversion with and without tick optimization,
liquidity increases/decreases, range changes, fee collection after real swaps,
buybacks through the upgraded existing BBB proxy, position transfers, and bridge
relay. The stale-history refusal also passes. The two inherited fuzz tests each
run 256 generated cases in each suite; these are test inputs, not exhaustive
coverage of all ranges or pool conditions.

The additional Aero test upgrades the existing deployed LM proxy
`0x2ACD313B892C9922E470e4950e907d5EAa70fC2a` on the local fork, without
reinitialization. It checks preservation of owner, max slippage, treasury,
OLAS balance, and WETH balance; verifies the replacement NPM/factory getters;
and successfully mints an Aero position owned by that same proxy.

### Test conditions and scope

- Test fixtures use Foundry `deal`, account impersonation, and timestamp warps.
  They create and seed a new OLAS/WETH tick-spacing-100 pool on the fork. They do
  not assert that such a pool exists or is sufficiently liquid on the live chain.
- The inherited warm-up uses 20 WETH and 500,000 OLAS as desired seed amounts.
  The buyback depth fixture uses 400 WETH and 10,000,000 OLAS as desired amounts.
  These fixed fixture inputs are not estimates of available treasury capital or
  market liquidity. The additional existing-proxy test stages 1 WETH and 10,000 OLAS.
- The inherited assertions and slippage tolerances were retained. Passing them
  establishes functionality under those conditions, not suitability of those
  tolerances for production. Gas output was not used as a performance estimate.
- Both address sets initially failed at the same shared setup call with
  `Overflow(902, 900)`; see `fork-legacy-base-initial.txt` and
  `fork-aero-base-initial.txt`. The fixture updated its Balancer oracle before a
  round trip that advanced time two more seconds, exceeding the window-start
  freshness bound. The test fix schedules the round trip to finish at the next
  update and then updates the oracle. No contract limit or assertion was relaxed.
- Compilation used Solc **0.8.34**, optimizer runs **200**, via IR, EVM **Prague**,
  following the repository's auto-detected Foundry configuration. These results
  do not establish byte-for-byte equivalence with deployed 0.8.30 artifacts.
- Production governance execution, chains other than Base and Optimism, staking rewards, and
  adversarial analysis of the external Aero contracts are outside this test.

### Deployment implications

The tested source supports reusing the LM proxy:

1. Deploy `LiquidityManagerBalancerSlipstream` with Aero NPM
   `0x4857DB576eE0e45F10525eC59527BfD10beeC60b`, keeping the other intended
   constructor dependencies. Its constructor derives Aero factory
   `0x9CB220581b91b0C83223012FE69688b92aD07a76`.
2. Have the existing LM owner call `changeImplementation(newImplementation)`
   on the existing proxy. Do not reinitialize it. No legacy-position migration
   is needed for the checked deployment state: the snapshot found none in the
   configured legacy NPMs.
3. Deploy the burner implementation with that LM proxy and Aero router
   `0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418`; upgrade its existing proxy.
   Configure matching Aero pools and explicitly chosen slippage settings.
4. Create/initialize the target pool if absent, supply liquidity, establish
   verifiable oracle history, and validate the intended live parameters before
   moving protocol liquidity.

The repository globals still describe the live legacy deployment. They were not
changed to undeployed replacement implementations.

## Exact fee reconciliation and dynamic-fee execution

The original version of `test/LiquidityManagerAeroFeesBase.t.sol` added **5 passing tests, 0 failures**
against the same Base block **53153049**. Raw output is `fork-aero-fees.txt`;
the command, source hashes, upstream revisions, and build settings are recorded
in `fork-fee-build-record.json`. The next version retained these five cases
and added full external withdrawal, for six cases on each chain. The extension
below adds seven policy/accounting cases and a separate transaction-boundary case. No production
Solidity changes were required.

### What is reconciled

Each accounting case swaps WETH into OLAS and OLAS into WETH. The assertions
check the fee-adjusted square-root price using exact integer math, input and
output pool-balance changes, the rounded-up unstaked-LP deduction credited to
`gaugeFees`, LP fee-growth increments, NPM collectable amounts after integer
rounding, and the final recipient balance changes. WETH goes to the treasury;
OLAS goes to `Bridge2Burner`. The test checks that the other token does not go
to either recipient, that the LP liquidity stays unchanged, and that a second
collection with no intervening swaps reverts with `ZeroValue`.

One case reverses the token-array order. All collection cases stage an additional
7 WETH and 11 OLAS at the LM before permissionless collection and check that
these balances are preserved exactly. Assertions use no numerical tolerance.

The pool initially has no gauge and its effective unstaked deduction is zero.
The additional gauge case creates and activates a real gauge through the
deployed governance creation module, impersonating its governor only on the
fork. The pinned factory has no custom unstaked-fee module and its default
deduction is **50,000 pips (5% of swap fees)**. For the stress case, the authorized
fee manager is impersonated to set the deduction to **333,333 pips (33.3333%)**;
the LP stays unstaked. This is a test setting, not a recommended or live change.

With the controlled elevated swap fee of **19,000 pips (1.9% of swap input)**,
the exact stress-case reconciliation is:

| Token | Gross swap fee, atoms | Gauge deduction, atoms | LM collection / recipient receipt, atoms | Rounding remainder, atoms |
|---|---:|---:|---:|---:|
| WETH | 190000003 | 63333271 | 126666731 | 1 |
| OLAS | 1900000000007 | 633332700003 | 1266667300003 | 1 |

An atom is the token's smallest unit. In each row, gross fee equals deduction
plus collection plus remainder. The remainder stays in the pool. Gauge-fee
distribution beyond the pool's accrued `gaugeFees` is outside this test.

### Dynamic-fee impact

The pinned hook reports default scaling factor **0** and default cap **50,000
pips (5%)**. The newly created tick-spacing-100 fixture pool charges **10,000
pips (1%)** under those defaults. These observations describe this block and
fixture, not every live pool's custom configuration.

To exercise an active dynamic component, the test sets this pool's scaling
factor to **1,000,000,000** and cap to **50,000 pips** through the deployed hook's
fee-manager methods on the fork. It moves the price with an input equal to the
integer virtual WETH reserve divided by 2000, then advances one block. The LM
price guard still passes. The fee changes from cached **11,000 pips (1.1%)** to
recomputed **19,000 pips (1.9%)**.

For the same **10000000000 WETH atoms** input, snapshots give the same starting
pool price/liquidity for both swaps:

| Case | OLAS output, atoms | Buyback with 120 bps tolerance |
|---|---:|---|
| Cached 1.1% fee | 395631405621410 | Passes |
| Recomputed 1.9% fee | 392431151605143 | Reverts: `Too little received` |

The 120 bps boundary is calculated from the measured outputs and exact TWAP
quotes. The failed buyback leaves pool balances, price and fee growth, burner
input balance, and bridge-burner OLAS balance unchanged. A subsequent test-only
1000 bps tolerance allows execution and delivers exactly the measured high-fee
output. This wider setting is not a production recommendation.

Dynamic fees therefore affect LP fee amounts and buyback execution. The tested
LM collection implementation already uses the actual NPM amounts correctly.
The burner can refuse a trade whose fees and price impact exceed its output
floor; operational quoting and tolerance choices must account for this.

### Scope and reproducibility

- The tests stage fixed initial capital of **1 WETH and 40,000 OLAS** at the LM
  before conversion. The inherited historical V2 holder has only residual funds
  at the pinned block; using those alone caused the initial probes to exhaust
  liquidity. The test was corrected by explicitly funding the fixture, without
  weakening the swap-boundary assertions.
- Reconciliation uses a single active, unstaked LP and swaps confined to one
  bitmap word with constant active liquidity. Inputs are **10000000123 WETH
  atoms** and **100000000000321 OLAS atoms**. It covers integer rounding in both
  directions, but not multi-position sharing, initialized-tick crossings,
  staked-position accounting, or staking emissions.
- Gas price equals base fee to isolate the dynamic swap-fee behavior from
  priority-fee MEV taxation. Other hooks and positive priority-fee scenarios are
  outside this test. There is no output-side hook deduction in the tested swaps.
- Gauge creation, fee changes, proxy upgrades, balances, blocks, and timestamps
  are local fork fixtures. No live governance action or transaction was sent.
- Published source was inspected at Slipstream commit
  `f99f2095918cab69eafeffa2c3d0a8762de737b7` and metadex core commit
  `8b506b450aaa9d4a9f1a77e264f2d9dd508e9ddf`. Primary implementation references:
  [pool accounting](https://github.com/Dromos-Labs/metadex-slipstream-public/blob/f99f2095918cab69eafeffa2c3d0a8762de737b7/contracts/core/CLPool.sol),
  [unstaked-fee eligibility](https://github.com/Dromos-Labs/metadex-slipstream-public/blob/f99f2095918cab69eafeffa2c3d0a8762de737b7/contracts/core/CLFactory.sol),
  [dynamic fee hook](https://github.com/Dromos-Labs/metadex-public/blob/8b506b450aaa9d4a9f1a77e264f2d9dd508e9ddf/V3/src/hooks/dynamic/DynamicSwapFeeHook.sol).

## Earlier Optimism verification and Base regression

The Optimism subclasses inherit the same lifecycle, upgrade, fee, and withdrawal
assertions used for Base. They are kept in the existing two added Solidity files,
so the review still adds five files in total. Chain-ID assertions reject a run
against the wrong chain.

Optimism-specific fixture configuration comes from repository globals and the
pinned official manifests:

- OLAS: `0xFC2E6e6BCbd49ccf3A5f029c79984372DcBFE527`.
- Existing LM proxy: `0x1f84F8F70dE0651C2d51Bf8850FE9D0289Ba3B3A`.
- Existing burner proxy: `0x4891f5894634DcD6d11644fe8E56756EF2681582`.
- Treasury is read from the existing LM at the pinned block:
  `0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c`.
- Balancer source pool ID:
  `0x5bb3e58887264b667f915130fd04bbb56116c27800020000000000000000012a`.
  The pool address is derived from its leading 20 bytes. The fixture funds
  `floor(totalSupply / 100)` BPT at the test LM with Foundry `deal`. This is
  explicit simulated capital, not a measurement of treasury ownership.
- Aero factory: `0xfeaB42D90055db3a0616249f76B6002D72266778`; the published NPM,
  router and CL gauge-factory addresses match Base's addresses on their
  respective chains. The governance creation module differs:
  `0x97aBFe52c819AB175F6426eC30BBF2dF29f9E94b`.

The 25 passing Optimism tests cover fresh pool creation/initialization, seed
minting and seed withdrawal, oracle warm-up, migration, liquidity maintenance,
position transfer, existing LM and burner proxy upgrades on the fork, fee
collection, buyback execution, bridge submission, and the stale-history guard.
They include the same exact two-token accounting, reversed-order collection,
preserved staged balances, and locally activated gauge deduction scenarios.
Bridge submission does not establish completion of the cross-chain L1 message.

The standalone full-withdrawal case first accrues fees in both tokens, then calls
the LM's external `decreaseLiquidity` with `decreaseRate = 10000` and
`olasBurnRate = 0`. It verifies that all NFT liquidity was removed, active pool
liquidity is zero, both returned amounts are positive, and the pool debits and
treasury receipts equal those returned amounts exactly. The LM ends with zero
WETH and OLAS balances. This closes the previously identified standalone
100% withdrawal coverage gap; it does not assert that the NFT is burned.

Optimism's pinned default scaling factor is 0 and cap is 50,000 pips. With the
same controlled dynamic-fee settings and price-move fixture as Base, the fee
changes from 11,000 to 19,000 pips. For 10000000000 WETH atoms of input:

| Optimism case | OLAS output, atoms | Buyback with 120 bps tolerance |
|---|---:|---|
| Cached 1.1% fee | 398058182662598 | Passes |
| Recomputed 1.9% fee | 394838298495754 | Reverts: `Too little received` |

The revert preserves the checked balances, pool price, and fee growth. The
test-only wider 1000 bps tolerance permits the high-fee trade and gives exactly
the measured output. The stressed gauge-deduction reconciliation matches the
two-token table above, including one atom of rounding remainder per token.
These fee settings and gauge activation exist only on the fork.

After sharing the fixture and adding full withdrawal, Base was rerun and also
passed all 25 cases. Original Base assertions and tolerances were retained.
Both current runs use Solc 0.8.34, optimizer 200, via IR, EVM Prague, and the
recorded Foundry version. Production contract files remain unchanged. The
single-active-unstaked-position and zero-priority-fee limits above apply to
both chains' exact fee tests.

## Extended Aero integration verification

The three previously listed integration gaps are now covered on both chains.
This extension changes the existing two Aero test files, makes the shared
fixture's warm-up method overridable, and updates this report and its existing
evidence bundle. It adds no repository files and leaves `reproduce.py` unchanged.

### Dynamic startup and history transitions

The startup subclasses run all ten Aero lifecycle/upgrade cases after a separate
seed-preparation path. This path configures a 50,000-pip cap and 1,000,000,000
scaling factor before seed minting or any swap, then seeds the existing fixture's
20 WETH / 500,000 OLAS desired amounts. These are simulated amounts.

Assertions distinguish the hook's 600-second history from the LM's 1800-second
history. Fresh pools reject the LM price guard both before and after seeding;
new-block swaps at 1 and 599 seconds use the base fee. At 600 seconds a controlled
price move produces a nonzero dynamic component, while the LM guard still rejects
the pool. The LM guard still rejects at 1799 seconds, and accepts after the final
round trip reaches 1800 seconds. Time and block numbers advance explicitly.
Seed withdrawal succeeds, and the inherited tests then exercise migration,
liquidity maintenance, collection, buyback, L2 submission, and proxy upgrade.
The existing stale-history rejection also runs with this startup configuration.
No production seed or LM implementation change was required by these scenarios.

### Fee policies and LM/BBB behavior

Each policy case reconciles both-token fees and recipients, including staged
funds; checks a BBB trade reverting at a 1-bps output tolerance with unchanged
pool/BBB/bridge balances and pool accounting; verifies exact successful BBB output
at a test-only 2000-bps tolerance; then exercises LM increase, partial decrease,
range change, and full withdrawal. The wide tolerance is for stress testing,
not a production recommendation. Migration with dynamics is covered separately
by the startup lifecycle suite; this is not every possible policy combination.

| Scenario | Assertions |
|---|---|
| Dynamic cap | A nonzero price deviation with scaling `1e18` reaches exactly 50,000 pips. |
| Initial-transaction override | Swaps in the initial transaction use 40,000 pips, while the stored block fee is 10,000. |
| Override selectors | Initial fee `0` selects the configured 20,000-pip base; `uint24.max` selects the 10,000-pip spacing fee; disabling the override restores the normal calculation. |
| Router discount | A 500,000-pip discount reduces the 10,000-pip fee to 5,000 for swaps through the actual router, including BBB. |
| Global fallback / fixed spacing | Zero per-pool scaling inherits a nonzero global factor; the custom-base sentinel `uint24.max` pins the spacing fee even with dynamics globally enabled. This is a nonzero swap fee. |
| Priority-fee tax | At the configured threshold the tax is zero; one wei above it gives the exact rounded tax; a larger priority fee reaches the module's 100,000-pip cap and the pool's 100,000-pip total-fee ceiling. Gauge deductions and both-token receipts are reconciled at that ceiling. |

The separate transaction-boundary fixture performs the first swap in `setUp`,
then the test executes as another top-level transaction at the same block.
It verifies that the 40,000-pip transient override expires, the router discount
then applies to the 10,000-pip block cache (giving 5,000), and the next block
starts another initial transaction. `vm.roll` alone is not treated as a new
transaction. The override bypasses the discount in the first transaction.

The inspected MEV module multiplier is zero on both pinned forks. The test
activates the deployed module locally using its owner: multiplier `1e12`,
minimum threshold 100 wei, base-fee factor zero. It does not claim that production
swaps currently pay this tax. All discounts, overrides, caps, global settings,
and module changes use authorized account impersonation only on the local fork.

### Multiple LPs and initialized tick crossings

An additional unstaked LP has a narrower range inside the LM's range. A WETH
swap crosses that LP's lower initialized boundary, reducing active liquidity;
an OLAS swap crosses back and restores it. Both swaps stay in one bitmap word,
so each has exactly two independently calculated price segments. Dynamic fees
and a 333,333-pip unstaked gauge deduction are active.

The test derives each segment's principal input/output, rounded swap fee, gauge
deduction and fee growth from integer price/liquidity math. It checks exact pool
balance changes, fee growth, changed active liquidity, LM and other-LP entitlements,
collection receipts, preserved staged LM funds, and residual rounding dust.
Assertions use no numerical tolerance. It covers one initialized boundary in
both directions and two unstaked LPs, not arbitrary multi-tick paths or staked LPs.

## Scope retained for release preparation

If we decide to adopt Aero, update the liquidity-migration runbook, deployment
scripts, deployment globals/addresses, and pool-preparation instructions before
deployment. These updates must specify the intended NPM/factory/router, LM and
BBB implementation upgrades, pool creation/seeding and oracle warm-up, and the
chosen fee and slippage configuration. This PR validates compatibility; those
operational updates remain follow-up work conditional on the adoption decision.

The LM does not stake positions; full staking and downstream gauge reward
distribution are outside this integration's scope. Validation covers Aero
buybacks, OLAS receipt by Bridge2Burner, and L2 bridge submission. Existing
cross-chain finalization and L1 burning are unchanged and outside this review's
scope. Simulation of the final production artifacts and governance payload is
deferred to release preparation; existing-proxy upgrade tests are complete.

## Reproduction

From the tokenomics repository root, with Python 3 and Foundry `cast` installed:

```sh
python3 docs/validation/aero-upgrade-impact-2026-10-27/reproduce.py verify
python3 docs/validation/aero-upgrade-impact-2026-10-27/reproduce.py show fork-aero-fees.txt
python3 docs/validation/aero-upgrade-impact-2026-10-27/reproduce.py snapshot --blocks 53153049 158748334 > /tmp/aero-snapshot-replay.json
git clone https://github.com/Dromos-Labs/metadex-slipstream-public.git /tmp/aero-source-replay
git -C /tmp/aero-source-replay checkout f99f2095918cab69eafeffa2c3d0a8762de737b7
python3 docs/validation/aero-upgrade-impact-2026-10-27/reproduce.py interfaces /tmp/aero-source-replay > /tmp/aero-interfaces-replay.json
rg -n -i 'velodrome|aerodrome|slipstream|940181a94|9560e827|veaero|vevelo' contracts scripts/deployment
forge test --match-contract '^LiquidityManager(Base|AeroBase|AeroFeesBase|AeroStartupBase|AeroInitialTxBase)Test$' --fork-url https://base.gateway.tenderly.co --fork-block-number 53153049 --compute-units-per-second 20 -j 1 --fuzz-seed 0xa3e0 -vv
forge test --match-contract '^LiquidityManager(Aero|AeroFees|AeroStartup|AeroInitialTx|Legacy)OptimismTest$' --fork-url https://optimism.gateway.tenderly.co --fork-block-number 158748334 --compute-units-per-second 20 -j 1 --fuzz-seed 0xa3e0 -vv
```

RPC availability and historical-state access depend on the chosen provider;
`--base-rpc` and `--optimism-rpc` can replace the defaults. RPC errors are
recorded as errors, not interpreted as zero balances. The final saved snapshot
has no RPC errors. Earlier Base endpoints rejected Python's default User-Agent;
the final probe uses an explicit User-Agent. Python syntax, tuple comparisons,
and both chains' fork suites were checked. Fork tests require the test fixture changes
on the analysis branch; the source hashes in the build record identify them.
