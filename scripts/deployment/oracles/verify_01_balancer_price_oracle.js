const fs = require("fs");
const globalsFile = "globals.json";
let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.balancerVaultAddress,
    parsedData.balancerPoolId,
    parsedData.olasAddress,
    parsedData.minTwapWindowSeconds,
    parsedData.minUpdateIntervalSeconds,
    parsedData.maxStalenessSeconds
];