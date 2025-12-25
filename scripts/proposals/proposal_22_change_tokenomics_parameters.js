/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/globals_mainnet.json";
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

    // Get Tokenomics implementation contract
    const tokenomicsImplementation = await ethers.getContractAt("Tokenomics", tokenomicsFourAddress);

    // Proposal preparation
    console.log("Proposal 22. TokenomicsProxy to change Tokenomics parameters `changeTokenomicsParameters()`");
    const targets = [tokenomicsProxyAddress];
    const values = [0];
    const callDatas = [tokenomicsImplementation.interface.encodeFunctionData("changeTokenomicsParameters", [0, 0, 0, parsedData.epochLen, 0])];
    const description = "Change Tokenomics parameters";

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
