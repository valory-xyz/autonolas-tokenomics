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
        version: "0.8.2",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000,
            },
        },
    },
};
