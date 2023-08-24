# Autonolas Tokenomics

## Introduction

This repository contains the tokenomics part of Autonolas onchain-protocol contracts.

A graphical overview is available here:

![architecture](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/On-chain_architecture_v5.png?raw=true)

An overview of the Autonolas tokenomics model, a high-level description of smart contacts, and a full set of smart contract
specifications are provided [here](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/Autonolas_tokenomics_audit.pdf?raw=true).

The Depository and Treasury contracts are inspired by OlympusDAO concepts. The Tokenomics contract implements the brunt of the reward logic
for component and agent owners, and the logic that regulates the discount factor for bonds.
The Tokenomics contract is deployed via the proxy contract, such that it is possible to update the current Tokenomics implementation.

- Core contracts:
  - [Depository](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Depository.sol)
  - [Dispenser](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Dispenser.sol)
  - [Tokenomics](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Tokenomics.sol)
  - [TokenomicsProxy](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/TokenomicsProxy.sol)
  - [Treasury](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/Treasury.sol)
- Auxiliary contracts:
  - [DonatorBlacklist](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/DonatorBlacklist.sol)
  - [GenericBondCalculator](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/GenericBondCalculator.sol)
  - [TokenomicsConstants](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/contracts/TokenomicsConstants.sol)

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity `0.8.18`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.19` and npm `8.13.2` and node `v18.6.0`);
- [`Foundry`](https://book.getfoundry.sh/) is required to run the foundry tests.

### Install the dependencies
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```

### Core components
The contracts, deploy scripts, regular scripts and tests are located in the following folders respectively:
```
contracts
scripts
test
```

### Compile the code and run
Compile the code:
```
npm run compile
```
Run tests with Hardhat:
```
npx hardhat test
```
Run tests with Foundry:
```
forge test --hh -vv
```

### Audits
The audit is provided as development matures. The latest audit reports can be found here: [audits](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits).
A list of known vulnerabilities can be found here: [Vulnerabilities list tokenomics](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/Vulnerabilities_list_tokenomics.pdf?raw=true).

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.

### Github workflows
The PR process is managed by github workflows, where the code undergoes several steps in order to be verified. Those include:
- code installation;
- running linters;
- running tests.

## Deployment
The deployment of contracts to the test- and main-net is split into step-by-step series of scripts for more control and checkpoint convenience.
The description of deployment procedure can be found here: [deployment](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here: [ABIs](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/abis).

For testing purposes, the hardhat node deployment script is located [here](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/deploy).

## Deployed Protocol
The list of contract addresses for different chains and their full contract configuration can be found [here](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/configuration.json).

In order to test the protocol setup on all the deployed chains, the audit script is implemented. Make sure to export
required API keys for corresponding chains (see the script for more information). The audit script can be run as follows:
```
node scripts/audit_chains/audit_contracts_setup.js
```

## LP Token Guide
It is advised to check the following [list of instructions](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/LP_token_guide.md) before enabling OLAS-based LP tokens. 

## Acknowledgements
The tokenomics contracts were inspired and based on the following sources:
- [Uniswap Labs](https://github.com/Uniswap/v2-core);
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts);
- [PaulRBerg](https://github.com/paulrberg/prb-math);
- [Jeiwan](https://github.com/Jeiwan/zuniswapv2);
- [Safe Ecosystem](https://github.com/safe-global/safe-contracts).
