const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.polygonRootChainManagerProxyAddress,
    parsedData.polygonFXRootAddress,
    parsedData.polygonL2TargetChainId,
    parsedData.polygonCheckpointManagerAddress,
    parsedData.polygonERC20PredicateAddress
];