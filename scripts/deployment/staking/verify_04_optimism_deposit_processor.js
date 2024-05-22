const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.optimisticL1StandardBridgeProxyAddress,
    parsedData.optimisticL1CrossDomainMessengerProxyAddress,
    parsedData.optimisticL2TargetChainId,
    parsedData.optimisticOLASAddress
];