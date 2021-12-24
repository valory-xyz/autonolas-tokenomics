//require("hardhat-deploy");
require("@nomiclabs/hardhat-ganache");
require("@nomiclabs/hardhat-waffle");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
//    defaultNetwork: "ganache",
    networks: {
        ganache: {
            url: "http://localhost:8545",
            gasLimit: 6000000000,
            defaultBalanceEther: 10,
        },
    },
    solidity: "0.8.0",
};
