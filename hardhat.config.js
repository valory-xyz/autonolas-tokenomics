/*global process*/

//require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("hardhat-tracer");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");
// storage layout tool
// require('hardhat-storage-layout');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const accounts = {
    mnemonic: "test test test test test test test test test test test junk",
    accountsBalance: "100000000000000000000000000000",
};

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;
let GOERLI_MNEMONIC = process.env.GOERLI_MNEMONIC;
if (!GOERLI_MNEMONIC) {
    GOERLI_MNEMONIC = accounts.mnemonic;
}
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

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
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY,
            chainId: 1,
        },
        goerli: {
            url: "https://eth-goerli.alchemyapi.io/v2/" + ALCHEMY_API_KEY,
            chainId: 5,
            accounts: {
                mnemonic: GOERLI_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
                passphrase: "",
            },
        },
        local: {
            url: "http://localhost:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: true,
            accounts
        },
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY
    },
    gasReporter: {
        enabled: true
    }
};
