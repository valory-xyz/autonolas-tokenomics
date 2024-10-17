/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;

    const provider = await ethers.providers.getDefaultProvider(providerName);

    // Get all the necessary contract addresses
    const dispenserAddress = parsedData.dispenserAddress;
    const depositProcessorL1Address = parsedData.modeDepositProcessorL1Address;
    const l2TargetChainId = parsedData.modeL2TargetChainId;

    // Get dispenser contract instance
    const dispenser = await ethers.getContractAt("Dispenser", dispenserAddress);

    // Proposal preparation
    console.log("Proposal 10. Set Deposit Processor and Chain Id in Dispenser for Mode");
    const targets = [dispenserAddress];
    const values = [0];
    const callDatas = [
        dispenser.interface.encodeFunctionData("setDepositProcessorChainIds", [[depositProcessorL1Address], [l2TargetChainId]])
    ];

    const description = "Set deposit processor and chain Id in Dispenser for Mode network";

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
