const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.serviceStakingFactoryAddress,
    parsedData.wormholeL2MessageRelayer,
    parsedData.celoWormholeDepositProcessorL1Address,
    parsedData.wormholel1ChainId,
    parsedData.wormholeL2CoreAddress,
    parsedData.wormholeL2TokenRelayerAddress
];