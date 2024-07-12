const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.wormholeL1TokenRelayerAddress,
    parsedData.wormholeL1MessageRelayerAddress,
    parsedData.celoL2TargetChainId,
    parsedData.wormholeL1CoreAddress,
    parsedData.celoWormholeL2TargetChainId
];