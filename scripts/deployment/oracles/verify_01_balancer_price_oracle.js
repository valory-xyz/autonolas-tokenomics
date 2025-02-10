const fs = require("fs");
const globalsFile = "globals.json";
let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.olasAddress,
    parsedData.nativeTokenAddress,
    parsedData.maxOracleSlippage,
    parsedData.minUpdateTimePeriod,
    parsedData.balancerVaultAddress,
    parsedData.balancerPoolId
];