const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.polygonRootChainProxyAddress,
    parsedData.polygonFXRootAddress,
    parsedData.polygonL2TargetChainId,
    parsedData.polygonRootChainProxyAddress,
    parsedData.polygonERC20PredicateAddress
];