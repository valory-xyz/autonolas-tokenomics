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
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const treasuryAddress = parsedData.treasuryAddress;
    const dispenserAddress = parsedData.dispenserAddress;
    const arbitrumDepositProcessorL1Address = parsedData.arbitrumDepositProcessorL1Address;
    const baseDepositProcessorL1Address = parsedData.baseDepositProcessorL1Address;
    const celoDepositProcessorL1Address = parsedData.celoDepositProcessorL1Address;
    const ethereumDepositProcessorAddress = parsedData.ethereumDepositProcessorAddress;
    const gnosisDepositProcessorL1Address = parsedData.gnosisDepositProcessorL1Address;
    const optimismDepositProcessorL1Address = parsedData.optimismDepositProcessorL1Address;
    const polygonDepositProcessorL1Address = parsedData.polygonDepositProcessorL1Address;
    const minStakingWeight = parsedData.minStakingWeight;
    const maxStakingIncentive = parsedData.maxStakingIncentive;

    // Get contract instances
    const tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    const treasury = await ethers.getContractAt("Treasury", treasuryAddress);

    const oldDispenserAddress = "0xeED0000fE94d7cfeF4Dc0CA86a223f0F603A61B8";
    const dispenserJSON = "abis/0.8.18/Dispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const abi = parsedFile["abi"];
    const oldDispenser = new ethers.Contract(oldDispenserAddress, abi, provider);

    const AddressZero = ethers.constants.AddressZero;
    const AddressNull = "0x000000000000000000000000000000000000dEaD";

    // Proposal preparation
    console.log("Proposal 9. Change dispenser address in tokenomics and treasury, disable old Dispenser");
    const targets = [tokenomicsProxyAddress, tokenomicsProxyAddress, treasuryAddress, oldDispenserAddress,
        oldDispenserAddress];
    const values = [0, 0, 0, 0, 0];
    const callDatas = [
        tokenomics.interface.encodeFunctionData("changeManagers", [AddressZero, AddressZero, dispenserAddress]),
        tokenomics.interface.encodeFunctionData("changeStakingParams", [maxStakingIncentive, minStakingWeight]),
        treasury.interface.encodeFunctionData("changeManagers", [AddressZero, AddressZero, dispenserAddress]),
        oldDispenser.interface.encodeFunctionData("changeManagers", [AddressNull, AddressNull]),
        oldDispenser.interface.encodeFunctionData("changeOwner", [AddressNull])
    ];

    const description = "Change Dispenser address in Tokenomics and Treasury, disable old Dispenser";

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
