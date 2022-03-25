require("hardhat-deploy");
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
//require("@nomiclabs/hardhat-ganache");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    networks: {
        ganache: {
            url: "http://localhost:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: true
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.4",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
            {
                version: "0.7.5",  // FixedPoint math from OlympusDAO, not compatible with 8.x
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
