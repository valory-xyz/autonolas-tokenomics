const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const olasAddress = parsedData.olasAddress;
const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
const treasuryAddress = parsedData.treasuryAddress;
const genericBondCalculatorAddress = parsedData.genericBondCalculatorAddress;

module.exports = [
    olasAddress,
    tokenomicsProxyAddress,
    treasuryAddress,
    genericBondCalculatorAddress
];