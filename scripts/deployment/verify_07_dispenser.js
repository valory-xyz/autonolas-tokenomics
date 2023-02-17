const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
const treasuryAddress = parsedData.treasuryAddress;

module.exports = [
    tokenomicsProxyAddress,
    treasuryAddress
];