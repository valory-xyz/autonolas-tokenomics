# Local allocation processing

For the route whose chain ID equals `block.chainid`, Dispenser reads the configured
processor's `stakingFactory()` and that factory's `mapInstanceParams(target)`.
A record with a zero deployer is unregistered: the target was never created by
that factory, or its record was removed. This check deliberately treats those two
cases alike.

At claim settlement, a positive allocation for an unregistered local target is
added to the normal inflation return and its payable amount becomes zero. The
claim cursor advances over the processed epochs. No tokens are minted for that
allocation and no withheld credit is consumed. Single and batch claims share
this behavior. `LocalAllocationReturned` reports the nominee hash, inclusive first
epoch, exclusive end epoch, and the additional amount returned by this check.
The ordinary claim event's return amount includes normal returns as well.

A registered but disabled target keeps its existing processor behavior: the
claim reverts and remains retryable after re-enabling. Registration checks do
not override emissions limits, verifier failures, or deposit failures. A failed
or malformed registration response reverts settlement; it is never treated as
an empty record. All claim effects, including returns and cursor updates, are
atomic with the rest of the transaction.

Registration is read at settlement. Creating an instance later does not revive
allocations already returned. Removing a registration can therefore cause
pending allocations to be returned when claimed. Operators should account for
this when removing factory records.

`calculateStakingIncentives` remains a view of the weight-based calculation. It
does not perform the settlement registration check. Voting weights, nomination,
remote routes, and already queued L2 payments are unchanged. Returning an
allocation does not remove its nominee's influence on relative voting weights.

## Validation

The local integration suite uses unmodified public StakingFactory, StakingProxy
and StakingVerifier sources from `valory-xyz/autonolas-registries` at commit
`0e065705af0ca8df84f75f7a19b814c21fa2d083`. Fault fixtures exercise failed and
malformed responses separately.

```sh
forge test --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol --mc DispenserLocalAllocationsTest -vv
forge test --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol --mc Dispenser -vv
npx hardhat test test/DispenserStakingIncentives.js
forge test --use 0.8.30 --skip UniswapFactory.sol --skip UniswapRouter.sol --fork-url https://ethereum-rpc.publicnode.com --fork-block-number 26327364 --mc StakingL1ProcessorForkETH -vv
```

When voting power limits the available budget, the existing calculation floors
the payable and returned portions separately. Their sum can be one wei below the
single-floor weighted budget. Recycling preserves the calculated payable-plus-return
sum; it does not change this existing residual. The low-voting-power tests check
both a deterministic one-wei case and fuzzed zero-or-one-wei residuals.

For accounting assertions, distinguish allocated payout `S`, ordinary return
`R`, reused withheld credit `W`, and newly minted tokens `M`. For an eligible
payout, `M = S - W` and total inflation return `F = R + W`, so `M + F = S + R`.
For a fully returned allocation, `M = 0`, `W = 0`, and `F = S + R`.

No storage fields or constructor parameters are added. The generated artifact is
`abis/0.8.30/Dispenser.json`. Deployment bytecode identity records and event
consumers must use the updated build. Historical deployment artifacts retain
their original meaning.

### Recorded validation (2026-11-02)

Base revision: `f051dd998bfa57c889d8e53ff54db8942a463d75`. Solidity 0.8.30,
optimizer 200 runs, via IR, Prague EVM. The recorded run explicitly used Foundry v1.7.1
(commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), matching CI. Check
`forge --version` before reproducing the commands; a different default binary
does not reproduce that toolchain. The Hardhat suite ran with Node v20.18.1.

- Dispenser Foundry suites: 102 passed, including 42 local allocation tests and five migration scenarios.
- Hardhat staking suite: 16 passed.
- Ethereum processor fork suite: 3 passed at block 26327364.
- Each Foundry fuzz test used 256 runs.
- All 12 storage entries retain their slot, offset and type relative to the base.
- Compiled runtime: 16,757 bytes (base: 16,090; EIP-170 limit: 24,576).
- Solhint on `contracts/Dispenser.sol`: zero errors, 154 warnings under the repository configuration.

The fork suite uses live Tokenomics, Treasury and OLAS with a real processor,
plus factory and staking fixtures that treat its targets as registered. It
checks the eligible deposit path, not live-factory recycling. The offline
integration suite separately uses the pinned real factory and verifier.
The resource-limit fixture verifies that a failed registration read reverts;
it does not measure the gas requirements of deployed factories.
The mixed local-credit boundary test seeds credit and previously issued token
backing explicitly; EthereumDepositProcessor has no outbound reserve-sync path.
These tests do not establish whether historical live allocations need reconciliation.
