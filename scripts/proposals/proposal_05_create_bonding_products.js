/*global process*/

const { ethers } = require("hardhat");

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

    // Get the depository contract addresses
    const depositoryTwoAddress = parsedData.depositoryTwoAddress;

    // Get contract instances
    const depository = await ethers.getContractAt("Depository", depositoryTwoAddress);

    // Additional products to create with depository contract
    const oneDay = 3600 * 24;
    const vestings = [8 * oneDay, 10 * oneDay, 12 * oneDay, 14 * oneDay, 14 * oneDay];
    const pricesLP = ["295316122987384115698", "285963343501085551090", "276610564014786986482", "267257784528488421874", "257905005042189857266"];
    const supplies = ["100000000000000000000000","150000000000000000000000","200000000000000000000000","200000000000000000000000","200000000000000000000000"];

    const targets = new Array();
    const values = new Array();
    const callDatas = new Array();
    for (let i = 0; i < pricesLP.length; i++) {
        targets.push(depositoryTwoAddress);
        values.push(0);
        callDatas.push(depository.interface.encodeFunctionData("create", [parsedData.OLAS_ETH_PairAddress, pricesLP[i], supplies[i], vestings[i]]));
    }

    const description = "Create new bonding products";

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
