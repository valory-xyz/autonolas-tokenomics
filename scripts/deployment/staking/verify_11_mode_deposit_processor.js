const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserProxyAddress,
    parsedData.modeL1StandardBridgeProxyAddress,
    parsedData.modeL1CrossDomainMessengerProxyAddress,
    parsedData.modeL2TargetChainId,
    parsedData.modeOLASAddress
];