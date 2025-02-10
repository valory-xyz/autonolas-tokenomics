const { ethers } = require("hardhat");
const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const buyBackBurnerAddress = parsedData.buyBackBurnerAddress;
const proxyPayload = ethers.utils.defaultAbiCoder.encode(["address[]", "bytes32", "uint256"],
    [[parsedData.olasAddress, parsedData.nativeTokenAddress, parsedData.balancerPriceOracleAddress,
    parsedData.balancerVaultAddress], parsedData.balancerPoolId, parsedData.maxBuyBackSlippage]);
const iface = new ethers.utils.Interface(["function initialize(bytes memory payload)"]);
const proxyData = iface.encodeFunctionData("initialize", [proxyPayload]);

module.exports = [
    buyBackBurnerAddress,
    proxyData
];