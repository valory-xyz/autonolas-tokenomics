# Deployment scripts
This folder contains the scripts to deploy Autonolas tokenomics. These scripts correspond to the steps in the full deployment procedure (as described in [deployment.md](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/deployment.md)).

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_goerli.json gobals.json`.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```
command and compiled with the
```
npm run compile
```
command as described in the [main readme](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/README.md).


Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_goerli.json` for the goerli testnet).

Make sure to export the required API keys in the following variables: `ALCHEMY_API_KEY` and `ETHERSCAN_API_KEY`.

Parameters of the `globals.json` file:
- `contractVerification`: flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: string with the derivation path;
- `providerName`: network type (see `hardhat.config.js` for the network configurations);
- `olasAddress`: OLAS contract address deployed during the `autonolas-governance` deployment.
- `timelockAddress`: Timelock contract address deployed during the `autonolas-governance` deployment.
- `veOLASAddress`: veOLAS contract address deployed during the `autonolas-governance` deployment.
- `componentRegistryAddress`: ComponentRegistry contract address deployed during the `autonolas-registries` deployment.
- `agentRegistryAddress`: AgentRegistry contract address deployed during the `autonolas-registries` deployment.
- `serviceRegistryAddress`: ServiceRegistry contract address deployed during the `autonolas-registries` deployment.

Other values in the `JSON` file are related to the tokenomics. The deployed contract addresses will be added / updated during the scripts run.

The script file name identifies the number of deployment steps taken from / to the number in the file name. For example:
- `deploy_01_donator_blacklist.js` will complete step 1 from [deployment.md](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/deployment.md).
- `deploy_10_14_change_ownerships.js` will complete steps 10 to 14.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `deploy_01_donator_blacklist.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.





