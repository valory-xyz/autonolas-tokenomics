# Withheld-credit inflation conservation test

`test/DispenserInflationConservation.t.sol` follows original issuance, L2 withholding,
L2-to-L1 synchronization, reuse, refund, and the eventual spending of the restored
allowance. It uses real Tokenomics and Dispenser proxies, Treasury, and both Gnosis
processor contracts. The existing CI command `forge test --mc Dispenser` includes it.

## Accounting checked

At each settled checkpoint, claim, message delivery, and synchronization step:

```text
cumulative fresh minting <= cumulative fresh scheduled staking budgets
cumulative fresh minting + remaining allowance = cumulative fresh scheduled staking budgets
```

Fresh minting comes from the token's zero-address `Transfer` events, checked against
total supply. Remaining allowance comes from the current refund pot plus unclaimed
epoch pots starting at the actual nominee claim cursor. Historical pots below that
cursor are not counted again. Fresh budgets are calculated independently from fixed
annual amounts and elapsed seconds, splitting at year boundaries and flooring the
per-second rate before multiplication. Refunded `stakingIncentive` values never
enter the fresh-budget oracle. All assertions use exact integer arithmetic.

The basic three-epoch scenario mints `B1`, then `B2 - W`, then `B3 + W`. The third
claim spends the restored allowance and leaves total minting equal to `B1 + B2 + B3`.
Each longer sequence ends by consuming all credit and spending all remaining
allowance; the recipient must then hold exactly the cumulative fresh budgets.

## Cases

- Three-epoch partial reuse through both single and batch entry points.
- Credit greater than the next claim: zero fresh minting with residual credit.
- Credit equal to the next claim, with the reused tokens withheld and synchronized again.
- Delayed sync delivery, replay of both message directions, and repeated epoch claim rejection.
- Credit created before the year-index 2-to-3 inflation decrease and reused across it.
- 12-step randomized sequences varying full/partial/no acceptance, settlement delay,
  synchronization timing, and single/batch entry point, followed by complete spending.

## Run

Install the repository's normal Foundry/submodule and Node dependencies first.
The offline flag requires Solidity 0.8.30 to be installed locally.

```sh
forge test --match-contract DispenserInflationConservationTest --offline --fuzz-seed 0x402 --fuzz-runs 256 -vv
python3 scripts/check_dispenser_inflation_mutations.py
```

The mutation script first requires an unmodified passing baseline, then independently
duplicates the refund, omits it, and restores the gross mint amount despite reused
credit. Each mutation must fail the conservation assertion in both single and batch
claims. Compile failures and unrelated reverts do not count as successful detection.
It uses a temporary copy and leaves the checkout's contracts unchanged. Use
`--forge /absolute/path/to/forge` when Forge is not on PATH.

## Scope

This isolates staking-budget conservation with zero opening entitlements, one
full-weight nominee, 100% staking allocation after activation, nonbinding L1 caps,
18-decimal bridging, no burns, and no other issuance. Batch coverage uses one chain
and one target; it does not establish multi-chain/multi-target conservation or
rounding behavior. The annual reference schedule covers year indices 0 through 3
from a fresh Tokenomics initialization; live deployment history and administrative
inflation resets are not modeled.

Voting and the staking factory/recipient are controlled test doubles. Bridge transport
moves the same token rather than minting a separate L2 representation, queues messages,
and supplies their original sender to the real receiver. Tokens arrive before each
L1-to-L2 message. Missing-token delivery, bridge custody/security, migration, governance
maintenance credit injection, zero staking fractions, and other OLAS minting paths are
outside this fixture. The token deliberately has no supply cap so an accounting error
cannot be concealed by a separate token-level mint refusal.

The randomized test is a bounded sequence test, not exhaustive verification or a
Foundry invariant handler covering arbitrary protocol actions.

## Local verification (2026-10-06)

Base: tokenomics `main` at `f15bedf9427138331cedc55ade6e3883dc719503`.
Solidity 0.8.30; Forge 1.6.0-nightly, commit
`e0d4aab210b1386d8dcf212c12646e465738d20b` (local toolchain; CI pins 1.7.1).

```sh
forge test --match-contract Dispenser --offline --fuzz-seed 0x402 --fuzz-runs 256 -vv
```

Result: 29 tests passed, zero failures or skips, including all seven new tests and
256 randomized recycling sequences. The mutation script passed its baseline and
rejected all three mutations in both single and batch claims via the conservation
assertion. No production contract changes are part of this addition.
