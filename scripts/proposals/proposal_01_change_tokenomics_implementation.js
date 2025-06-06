/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    const EOA = signers[0];
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const governorTwoAddress = parsedData.governorTwoAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const tokenomicsFourAddress = parsedData.tokenomicsFourAddress;

    // Get the GovernorOLAS instance via its ABI
    const GovernorOLASJSON = "abis/misc/GovernorOLAS.json";
    let contractFromJSON = fs.readFileSync(GovernorOLASJSON, "utf8");
    let contract = JSON.parse(contractFromJSON);
    const GovernorOLASABI = contract["abi"];
    const governor = await ethers.getContractAt(GovernorOLASABI, governorTwoAddress);

    const tokenomicsProxy = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);

    // Proposal preparation
    console.log("Proposal 1. TokenomicsProxy to change Tokenomics implementation calling `changeTokenomicsImplementation(TokenomicsFour)`");
    const targets = [tokenomicsProxyAddress];
    const values = [0];
    const callDatas = [tokenomicsProxy.interface.encodeFunctionData("changeTokenomicsImplementation", [tokenomicsFourAddress])];
    const description = "Change Tokenomics implementation to the version 1.3.0";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
