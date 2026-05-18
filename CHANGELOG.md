# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.4.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.3.3...v1.4.3
[1.3.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.4...v1.3.2
[1.2.4]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.3...v1.2.2
[1.0.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-tokenomics/releases/tag/v1.0.0


## [Unreleased]

## [v1.4.3] - 2026-05-18

### Added

- Protocol-Owned Liquidity: `LiquidityManagerCore`, `LiquidityManagerETH`, `LiquidityManagerOptimism`, and `LiquidityManagerProxy` for managing Uniswap V3 protocol-owned positions with on-chain TWAP price guards ([#228](https://github.com/valory-xyz/autonolas-tokenomics/pull/228), [#229](https://github.com/valory-xyz/autonolas-tokenomics/pull/229), [#230](https://github.com/valory-xyz/autonolas-tokenomics/pull/230), [#231](https://github.com/valory-xyz/autonolas-tokenomics/pull/231), [#232](https://github.com/valory-xyz/autonolas-tokenomics/pull/232), [#233](https://github.com/valory-xyz/autonolas-tokenomics/pull/233))
- `Bridge2Burner` contracts (Gnosis, Optimism, Polygon, Arbitrum variants) with fork tests and deployment scripts ([#238](https://github.com/valory-xyz/autonolas-tokenomics/pull/238), [#240](https://github.com/valory-xyz/autonolas-tokenomics/pull/240))
- `LPSwapCelo` to migrate whOLAS-CELO Ubeswap V2 liquidity to OLAS-CELO with TWAP-based slippage protection; bridges leftover OLAS via OP-stack L2StandardBridge and whOLAS via Wormhole Token Bridge
- V3 swap path in `BuyBackBurnerUniswap` / `BuyBackBurnerBalancer`, optional per-chain, with V3 pool mapping and per-token max-slippage controls ([#243](https://github.com/valory-xyz/autonolas-tokenomics/pull/243), [#247](https://github.com/valory-xyz/autonolas-tokenomics/pull/247), [#278](https://github.com/valory-xyz/autonolas-tokenomics/pull/278))
- `WormholeDepositProcessorL1` / `WormholeTargetDispenserL2` deployment on Celo with OLAS bridging setup ([#253](https://github.com/valory-xyz/autonolas-tokenomics/pull/253), [#254](https://github.com/valory-xyz/autonolas-tokenomics/pull/254))
- `CONTRIBUTING.md` and Gitleaks configuration ([#248](https://github.com/valory-xyz/autonolas-tokenomics/pull/248))

### Changed

- `BalancerPriceOracle` / `UniswapPriceOracle` V2: two-observation rolling window (no TWAP blackout after `updatePrice`) and `maxStalenessSeconds` bound; require 2-call warmup ([#258](https://github.com/valory-xyz/autonolas-tokenomics/pull/258), [#262](https://github.com/valory-xyz/autonolas-tokenomics/pull/262), [#263](https://github.com/valory-xyz/autonolas-tokenomics/pull/263))
- `OptimismDepositProcessorL1`: cut 32 unused bits from input bridge data ([#252](https://github.com/valory-xyz/autonolas-tokenomics/pull/252))
- Vulnerabilities list migrated to Markdown (`docs/Vulnerabilities_list_tokenomics.md`) and folded in C4R findings ([#270](https://github.com/valory-xyz/autonolas-tokenomics/pull/270))
- LM deployment parameters tuned: cardinality re-anchored to mid-volume V3 precedent, deviation/slippage co-existence clarified ([#286](https://github.com/valory-xyz/autonolas-tokenomics/pull/286))
- Unified Balancer oracle `maxStalenessSeconds = 86400` across chains; dropped dead `maxBuyBackSlippage` from proxy init payloads ([#285](https://github.com/valory-xyz/autonolas-tokenomics/pull/285))
- Switched submodules to HTTPS ([#251](https://github.com/valory-xyz/autonolas-tokenomics/pull/251))
- Deployment of oracle and BuyBackBurner contracts across Ethereum, Arbitrum, Polygon, Base, Gnosis, and Celo ([#246](https://github.com/valory-xyz/autonolas-tokenomics/pull/246), [#287](https://github.com/valory-xyz/autonolas-tokenomics/pull/287))
- `slot0` reads converted to low-level assembly for forward compatibility across V3 pool variants ([#241](https://github.com/valory-xyz/autonolas-tokenomics/pull/241))

### Fixed

- `LiquidityManagerCore.checkPoolAndGetCenterPrice`: TWAP decoded into a separate local variable; `instantPrice` computed from the preserved slot0 value; deviation check compares real instantaneous price against TWAP, preventing flash-loan manipulation; revert on `observe()` failure (C4R 2026-01 #17/#18 S-347/S-471, internal audit 15 M-01) ([#272](https://github.com/valory-xyz/autonolas-tokenomics/pull/272), [#273](https://github.com/valory-xyz/autonolas-tokenomics/pull/273))
- `LiquidityManagerCore.changeRanges`: replaced silent single-sided skip with `revert ZeroValue()` (C4R 2026-01 #19 S-668) ([#272](https://github.com/valory-xyz/autonolas-tokenomics/pull/272))
- `Tokenomics.checkpoint`: correct `effectiveBond` at decreasing-year boundaries (internal audit 15 M-04)
- `BuyBackBurner._performSwap` (V3): honor `mapTokenMaxSlippages` (internal audit 15 H-02 / C4A M-11) ([#275](https://github.com/valory-xyz/autonolas-tokenomics/pull/275))
- `BuyBackBurner._buyOLAS` (V2): auto-refresh TWAP observation before swap (internal audit 15 M-03)
- `BuyBackBurner`: reshape `mapV3Pools` to mirror `mapV2Oracles` (audit 15 L-06 / I-01) ([#280](https://github.com/valory-xyz/autonolas-tokenomics/pull/280), [#281](https://github.com/valory-xyz/autonolas-tokenomics/pull/281))
- `Bridge2Burner`: close Polygon L1 destination (M-1) and approval cleanup on revert (L-NEW-2) (internal audit 16) ([#282](https://github.com/valory-xyz/autonolas-tokenomics/pull/282), [#283](https://github.com/valory-xyz/autonolas-tokenomics/pull/283))
- Static audit and ownership CSV refresh ([#255](https://github.com/valory-xyz/autonolas-tokenomics/pull/255), [#256](https://github.com/valory-xyz/autonolas-tokenomics/pull/256))
- Completed internal audits 10–16 and external Code4rena audit (C4R 2026-01) with corresponding fix bundles

## [v1.3.3] - 2025-07-16

### Changed

- Enhancements of `DefaultTargetDispenserL2` ([#213](https://github.com/valory-xyz/autonolas-tokenomics/pull/213))
- Deployment of `ArbitrumDepositProcessorL1`, `ArbitrumTargetDispenserL2`, `GnosisDepositProcessorL1` , `GnosisTargetDispenserL2`, `OptimismDepositProcessorL1` (for Optimism, Base, Mode), `OptimismTargetDispenserL2` (on Optimism, Base, Mode), `PolygonDepositProcessorL1`, `PolygonTargetDispenserL2`, `WormholeDepositProcessorL1` (for Celo), and `WormholeTargetDispenserL2` (on Celo) contracts ([#224](https://github.com/valory-xyz/autonolas-tokenomics/pull/224))

## [v1.3.2] - 2025-05-22

### Changed

- Update tokenomics inflation curve ([#200](https://github.com/valory-xyz/autonolas-tokenomics/pull/200))
- Deploy Tokenomcis implementation with a new inflation curve

## [v1.2.4] - 2025-03-25

### Changed

- Development of `BalancerPriceOracle`, `UniswapPriceOracle` and `BuyBackBurner` contracts
- Deployment of contracts on Gnosis and Base ([#203](https://github.com/valory-xyz/autonolas-tokenomics/pull/203))


## [v1.2.3] - 2024-11-01

_No bytecode changes_.

- Deploying `OptimismDepositProcessorL1` for Mode on Ethereum mainnet, `OptimismTargetDispenserL2` on Mode ([#189](https://github.com/valory-xyz/autonolas-tokenomics/pull/189))
- Adjusting static audit

## [1.2.2] - 2024-07-29

### Changed

- Introducing Service Staking according to [PoAA Whitepaper](https://staking.olas.network/poaa-whitepaper.pdf)
- Refactored  and re-deployed `Tokenomics` and `Dispenser` to address service staking inflation and claiming capability ([#156](https://github.com/valory-xyz/autonolas-tokenomics/pull/156)), with the subsequent internal audit ([#168](https://github.com/valory-xyz/autonolas-tokenomics/pull/168))
- Created and deployed `ArbitrumDepositProcessorL1`, `ArbitrumTargetDispenserL2`, `DefaultDepositProcessorL1`, `DefaultTargetDispenserL2`, `EthereumDepositProcessor`, `GnosisDepositProcessorL1` , `GnosisTargetDispenserL2`, `OptimismDepositProcessorL1`, `OptimismTargetDispenserL2`, `PolygonDepositProcessorL1`, `PolygonTargetDispenserL2`, `WormholeDepositProcessorL1`, and `WormholeTargetDispenserL2` contracts
- Participated in a complete [C4R audit competition](https://github.com/code-423n4/2024-05-olas-findings) and addressed findings

## [1.0.3] - 2023-10-05

_No bytecode changes_.

- Added the latest external audit.

## [1.0.2] - 2023-07-26

### Changed

- Updated and deployed `Depository` contract v1.0.1 that revises the behavior of bonding products ([#104](https://github.com/valory-xyz/autonolas-tokenomics/pull/104))
  with the subsequent internal audit ([audit3](https://github.com/valory-xyz/autonolas-tokenomics/tree/main/audits/internal3))
- Updated documentation
- Added tests
- Updated vulnerabilities list

## [1.0.1] - 2023-05-26

### Changed

- Updated and deployed `TokenomicsConstants` and `Tokenomics` contracts v1.0.1 that account for the donator veOLAS balance to enable OLAS top-ups ([#97](https://github.com/valory-xyz/autonolas-tokenomics/pull/69))
  with the subsequent internal audit ([audit2](https://github.com/valory-xyz/autonolas-tokenomics/tree/main/audits/internal2))
- Bump `prb-math` package dependency to v4.0.0
- Updated documentation
- Added tests

## [1.0.0] - 2022-03-22

### Added

- Initial release