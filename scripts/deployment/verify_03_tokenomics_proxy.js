const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const tokenomicsMasterAddress = parsedData.tokenomicsMasterAddress;
const proxyData = fs.readFileSync("proxyData.txt");

module.exports = [
    tokenomicsMasterAddress,
    proxyData
];