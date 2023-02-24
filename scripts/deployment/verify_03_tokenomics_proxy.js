const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const tokenomicsAddress = parsedData.tokenomicsAddress;
const proxyData = fs.readFileSync("proxyData.txt").toString();

module.exports = [
    tokenomicsAddress,
    proxyData
];