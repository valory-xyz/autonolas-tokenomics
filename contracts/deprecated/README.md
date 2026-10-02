# deprecated

Contracts that **were deployed and whose source is no longer the current build** — either replaced on-chain,
or still live but superseded in source.

They are kept here rather than deleted because the code is (or was) live on-chain and needs a source of
record. They are not part of the active deployment set.

- `WormholeDepositProcessorL1`, `WormholeTargetDispenserL2` — the Celo staking path, used until Celo
  became an OP-stack chain and moved to the Optimism processor in February 2026.
- `BuyBackBurnerProxyV1` — **still the live Base `BuyBackBurnerProxy`**; superseded in source by the current
  `BuyBackBurnerProxy`. Its artifact is in `abis/deployed/`.

Distinct from `stale/` in other repos, which holds contracts that were never deployed at all.
