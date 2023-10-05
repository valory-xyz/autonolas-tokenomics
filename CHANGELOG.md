# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.0.3]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/valory-xyz/autonolas-tokenomics/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-tokenomics/releases/tag/v1.0.0

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