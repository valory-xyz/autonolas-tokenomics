const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.arbitrumL1ERC20GatewayAddress,
    parsedData.arbitrumInboxAddress,
    parsedData.arbitrumL2TargetChainId,
    parsedData.arbitrumOutboxAddress
];