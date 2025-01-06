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

    // Get active products
    const activeProducts = await depository.getProducts(true);

    console.log("Proposal 15. Close all bonding  products");
    const targets = [depositoryTwoAddress];
    const values = [0];
    const callDatas = [depository.interface.encodeFunctionData("close", [activeProducts])];

    const description = "Close all bonding products";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", JSON.stringify(callDatas, null, 2));
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
