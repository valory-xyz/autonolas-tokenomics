const fs = require("fs");
const globalsFile = "globals.json";
let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const nativeTokenAddress = parsedData.nativeTokenAddress;

module.exports = [
    nativeTokenAddress,
    parsedData.maxOracleSlippage,
    parsedData.pairAddress
];