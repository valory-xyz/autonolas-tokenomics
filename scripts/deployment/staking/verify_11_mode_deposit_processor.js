const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

// Supported for Sepolia globals only. This file has no network connection, so it checks the globals' chainId, a
// weaker guarantee than the deploy scripts' check of the connected chain. On mainnet the processor's l1Dispenser is
// the DispenserProxy, not this globals' dispenserAddress (the pre-proxy Dispenser), and the .sh deploy script
// verifies it with the right arguments.
const supportedChainIds = [11155111];
if (!supportedChainIds.includes(Number(parsedData.chainId))) {
    throw new Error("Supported for Sepolia globals only (globals chainId " + parsedData.chainId
        + "); on mainnet the .sh deploy script verifies the processor");
}

module.exports = [
    parsedData.olasAddress,
    parsedData.dispenserAddress,
    parsedData.modeL1StandardBridgeProxyAddress,
    parsedData.modeL1CrossDomainMessengerProxyAddress,
    parsedData.modeL2TargetChainId,
    parsedData.modeOLASAddress
];