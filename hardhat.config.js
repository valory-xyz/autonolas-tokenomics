require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");
require("hardhat-tracer");
/* storage layout tooling */
require('hardhat-storage-layout');


/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const accounts = {
    mnemonic: "test test test test test test test test test test test junk",
    accountsBalance: "100000000000000000000000000000",
};

module.exports = {
    gasReporter: {
        enabled: true
    },
    networks: {
        local: {
            url: "http://localhost:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: true,
            accounts
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
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
    }
};
