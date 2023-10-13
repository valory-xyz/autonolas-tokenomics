/*global process*/

//require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("hardhat-tracer");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");
// require('hardhat-storage-layout');

const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
let TESTNET_MNEMONIC = process.env.TESTNET_MNEMONIC;

const accounts = {
    mnemonic: TESTNET_MNEMONIC,
    path: "m/44'/60'/0'/0",
    initialIndex: 0,
    count: 20,
};

if (!TESTNET_MNEMONIC) {
    accounts.mnemonic = "test test test test test test test test test test test junk";
    accounts.accountsBalance = "100000000000000000000000000000";
}

module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.20",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 4000,
                    },
                },
            },
            {
                version: "0.5.16", // uniswap
            },
            {
                version: "0.6.6", // uniswap
            }
        ]
    },
    networks: {
        mainnet: {
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET,
            accounts,
            chainId: 1,
        },
        goerli: {
            url: "https://eth-goerli.alchemyapi.io/v2/" + ALCHEMY_API_KEY_GOERLI,
            accounts,
            chainId: 5,
        },
        gnosis: {
            url: "https://rpc.gnosischain.com",
            accounts: accounts,
            chainId: 100,
        },
        local: {
            url: "http://localhost:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: true,
            accounts,
        },
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY
    },
    gasReporter: {
        enabled: true
    }
};
