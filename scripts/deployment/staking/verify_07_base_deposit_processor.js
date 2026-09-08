const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.baseL1StandardBridgeProxyAddress,
    parsedData.baseL1CrossDomainMessengerProxyAddress,
    parsedData.baseL2TargetChainId,
    parsedData.baseOLASAddress
];