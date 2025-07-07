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

    // EOA address
    const EOA = signers[0];
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    // Get contract instances
    const tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);

    // Proposal preparation
    console.log("Proposal 17. Change tokenomics incentive fractions");
    const targets = [tokenomicsProxyAddress];
    const values = [0];
    const callDatas = [
        tokenomics.interface.encodeFunctionData("changeIncentiveFractions", [83, 17, 25, 0, 0, 75])
    ];
    const description = "Change tokenomics incentive fractions";

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
