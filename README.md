# Autonolas Tokenomics

## Introduction

This repository contains the tokenomics part of onchain-protocol contracts.

A graphical overview is available here:

![architecture](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/On-chain_architecture_v2.png?raw=true)

An overview of the design is provided [here](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/Audit_Tokenomics.pdf?raw=true).

The Depository and Treasury contracts borrow concepts from OlympusDAO. The Tokenomics contract implements the brunt of the reward logic for component and agent owners as well as veOLA stakers.

- [Depository](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Depository.sol)
- [Dispenser](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Dispenser.sol)
- [Tokenomics](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Tokenomics.sol)
- [Treasury](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Treasury.sol)

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity `0.8.17`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.10` and npx/npm `6.14.11` and node `v12.22.0`).

### Install the dependencies
The dependency list is managed by the `package.json` file,
and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the follwing command to install the project:
```
yarn install
```

### Core components
The contracts, deploy scripts, regular scripts and tests are located in the following folders respectively:
```
contracts
test
```
The tests are logically separated into unit and integration ones.

### Compile the code and run
Compile the code:
```
npm run compile
```
Run the tests:
```
npx hardhat test
```

### Internal audit
The audit is provided internally as development matures. The latest audit report can be found here: [audit](https://github.com/valory-xyz/onchain-protocol/blob/main/audit).

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


### Github workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code installation
- running linters
- running tests

## Acknowledgements
The registries contracts were inspired and based on the following sources:
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).