require("hardhat-deploy");
//require("@nomiclabs/hardhat-ganache");
require("@nomiclabs/hardhat-waffle");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    networks: {
        ganache: {
            url: "http://localhost:8545",
        },
    },
    solidity: "0.8.0",
};
