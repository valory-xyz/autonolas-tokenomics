# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.3.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.4...v1.3.2
[1.2.4]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.3...v1.2.2
[1.0.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-tokenomics/releases/tag/v1.0.0


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