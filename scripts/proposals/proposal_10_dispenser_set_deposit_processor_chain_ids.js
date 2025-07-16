/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/staking/globals_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;

    const provider = await ethers.providers.getDefaultProvider(providerName);

    // Get all the necessary contract addresses
    const dispenserAddress = parsedData.dispenserAddress;
    const depositProcessorL1Addresses = [parsedData.arbitrumDepositProcessorL1Address, parsedData.baseDepositProcessorL1Address,
        parsedData.celoDepositProcessorL1Address, parsedData.gnosisDepositProcessorL1Address,
        parsedData.modeDepositProcessorL1Address, parsedData.optimismDepositProcessorL1Address,
        parsedData.polygonDepositProcessorL1Address];
    const l2TargetChainIds = [parsedData.arbitrumL2TargetChainId, parsedData.baseL2TargetChainId,
        parsedData.celoL2TargetChainId, parsedData.gnosisL2TargetChainId, parsedData.modeL2TargetChainId,
        parsedData.optimismL2TargetChainId, parsedData.polygonL2TargetChainId];

    // Get dispenser contract instance
    const dispenser = await ethers.getContractAt("Dispenser", dispenserAddress);

    // Proposal preparation
    console.log("Proposal 10. Set Deposit Processor and Chain Id in Dispenser for Mode");
    const targets = [dispenserAddress];
    const values = [0];
    const callDatas = [
        dispenser.interface.encodeFunctionData("setDepositProcessorChainIds", [depositProcessorL1Addresses, l2TargetChainIds])
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
