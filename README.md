# Autonolas Tokenomics

## Introduction

This repository contains the tokenomics part of Autonolas onchain-protocol contracts.

A graphical overview is available [here](docs/flowchart.md).

For reference purposes only, an older version of the general Autonolas architecture is available [here](docs/On-chain_architecture_v5.png).

An overview of the Autonolas tokenomics model is provided [here](docs/Autonolas_tokenomics_audit.pdf). A description of the tokenomics contracts related to Olas staking is provided [here](docs/StakingSmartContracts.pdf).

Details on tokenomics model and Olas Staking can be found [here](https://olas.network/documents/whitepaper/Autonolas_Tokenomics_Core_Technical_Document.pdf) and [here](https://staking.olas.network/poaa-whitepaper.pdf).

The Depository and Treasury contracts are inspired by OlympusDAO concepts. The Tokenomics contract implements the brunt of the reward logic
for component and agent owners, the logic that regulates the discount factor for bonds, and Olas staking emissions.
The Tokenomics contract is deployed via the proxy contract, such that it is possible to update the current Tokenomics implementation.

- Core contracts:
  - [Depository](contracts/Depository.sol)
  - [Dispenser](contracts/Dispenser.sol)
  - [Tokenomics](contracts/Tokenomics.sol)
  - [TokenomicsProxy](contracts/TokenomicsProxy.sol)
  - [Treasury](contracts/Treasury.sol)

- Staking related contracts:
  - [DefaultDepositProcessorL1](contracts/staking/DefaultDepositProcessorL1.sol)
  - [DefaultTargetDispenserL2](contracts/staking/DefaultTargetDispenserL2.sol)
  - [EthereumDepositProcessor.sol](contracts/staking/EthereumDepositProcessor.sol.sol)
  - [ArbitrumDepositProcessorL1](contracts/staking/ArbitrumDepositProcessorL1.sol)
  - [ArbitrumTargetDispenserL2](contracts/staking/ArbitrumTargetDispenserL2.sol)
  - [GnosisDepositProcessorL1](contracts/staking/GnosisDepositProcessorL1.sol)
  - [GnosisTargetDispenserL2](contracts/staking/GnosisTargetDispenserL2.sol)
  - [OptimismDepositProcessorL1](contracts/staking/OptimismDepositProcessorL1.sol)
  - [OptimismTargetDispenserL2](contracts/staking/OptimismTargetDispenserL2.sol)
  - [PolygonDepositProcessorL1](contracts/staking/PolygonDepositProcessorL1.sol)
  - [PolygonTargetDispenserL2](contracts/staking/PolygonTargetDispenserL2.sol)
  - [WormholeDepositProcessorL1](contracts/staking/WormholeDepositProcessorL1.sol)
  - [WormholeTargetDispenserL2](contracts/staking/WormholeTargetDispenserL2.sol)

- Auxiliary contracts:
  - [DonatorBlacklist](contracts/DonatorBlacklist.sol)
  - [GenericBondCalculator](contracts/GenericBondCalculator.sol)
  - [TokenomicsConstants](contracts/TokenomicsConstants.sol)

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity starting from version `0.8.18`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.19` and npm `10.1.0` and node `v18.6.0`);
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
#### Hardhat
Compile the code with Hardhat:
```
yarn compile
```
Run tests with Hardhat:
```
yarn test
```
Run coverage with Hardhat:
```
yarn coverage
```

#### Forge
Compile the code with Forge:
```
forge build
```
Run unit tests with Forge (no fork required):
```
forge test --mc Depository -vvv
forge test --mc Dispenser -vvv
forge test --mc Treasury -vvv

# Oracle unit tests
forge test --mc UniswapPriceOracleConstructorTest -vvv
forge test --mc UniswapPriceOracleGetPriceTest -vvv
forge test --mc UniswapPriceOracleUpdatePriceTest -vvv
forge test --mc UniswapPriceOracleGetTWAPTest -vvv
forge test --mc BalancerPriceOracleConstructorTest -vvv
forge test --mc BalancerPriceOracleGetPriceTest -vvv
forge test --mc BalancerPriceOracleUpdatePriceTest -vvv
forge test --mc BalancerPriceOracleGetTWAPTest -vvv

# LPSwapCelo unit tests
forge test --mc LPSwapCeloConstructorTest -vvv
forge test --mc LPSwapCeloSwapTest -vvv
forge test --mc LPSwapCeloSlippageTest -vvv
```
Run fork tests with Forge (require RPC node URL for the target chain):
```
# Fork tests (ETH mainnet)
forge test -f $FORK_ETH_NODE_URL --mc LiquidityManagerETH -vvv
forge test -f $FORK_ETH_NODE_URL --mc UniswapPriceOracleETH -vvv
forge test -f $FORK_ETH_NODE_URL --mc BuyBackBurnerUniswapETH -vvv

# Fork tests (Base)
forge test -f $FORK_BASE_NODE_URL --mc LiquidityManagerBase -vvv
forge test -f $FORK_BASE_NODE_URL --mc BalancerPriceOracleBase -vvv
forge test -f $FORK_BASE_NODE_URL --mc BuyBackBurnerBalancerBase -vvv

# Fork tests (Polygon)
forge test -f $FORK_POLYGON_NODE_URL --mc BuyBackBurnerBalancerPolygon -vvv

# Fork tests (Arbitrum)
forge test -f $FORK_ARBITRUM_NODE_URL --mc BuyBackBurnerBalancerArbitrum -vvv

# Fork tests (Celo)
forge test -f https://forno.celo.org --mc LPSwapCeloForkTest -vvv
```

### Audits
- The audit is provided as development matures. The latest audit reports can be found here: [audits](audits).
- A list of known vulnerabilities can be found here: [Vulnerabilities list tokenomics](docs/Vulnerabilities_list_tokenomics.md).

#### Static audit
The static audit checks all the deployed contracts on-chain info correctness and can be run using the following script:
```
node scripts/audit_chains/audit_contracts_setup.js
```

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
The description of deployment procedure can be found here: [deployment](scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here: [ABIs](abis).

For testing purposes, the hardhat node deployment script is located [here](deploy).

## Deployed Protocol
The list of contract addresses for different chains and their full contract configuration can be found [here](docs/configuration.json).

In order to test the protocol setup on all the deployed chains, the audit script is implemented. Make sure to export
required API keys for corresponding chains (see the script for more information). The audit script can be run as follows:
```
node scripts/audit_chains/audit_contracts_setup.js
```

## LP Token Guide
It is advised to check the following [list of instructions](docs/lp_token_guide.md) before enabling OLAS-based LP tokens. 

## LP Token List
OLAS-based LP tokens eligible for bonding come from various chains. At a minimum, after [OLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/olas_bridging.md)
has been bridged to a specific chain, the `OLAS-XCHAIN_TOKEN` LP token is created to provide the liquidity on that chain.

In order to participate in bonding with LPs from different chains, the LP owner needs to transfer LP tokens to the ETH mainnet
and deposit via a [Depository](contracts/Depository.sol) contract
directly, or by using the [Bonding UI](https://tokenomics.olas.network/bonding-products).

For more information about bonding enabled LP tokens and bridging see [here](docs/lp_token_bridging.md).


## Tokenomics inflation update
Several reviews of tokenomics inflation have been performed. The up-to-date tokenomics inflation update documentation
can be found [here](docs/Update_tokenomics_inflation.pdf).


## Acknowledgements
The tokenomics contracts were inspired and based on the following sources:
- [Uniswap Labs](https://github.com/Uniswap/v2-core);
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts);
- [PaulRBerg](https://github.com/paulrberg/prb-math);
- [Jeiwan](https://github.com/Jeiwan/zuniswapv2);
- [Safe Ecosystem](https://github.com/safe-global/safe-contracts).
