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

    console.log("Proposal 5. Close old products and create new ones");
    const targets = [depositoryTwoAddress];
    const values = [0];
    const callDatas = [depository.interface.encodeFunctionData("close", [[10, 11, 12, 13, 14, 15, 16, 17, 18]])];

    // Additional products to create with depository contract
    const oneDay = 3600 * 24;
    const vestings = [28 * oneDay, 28 * oneDay, 21 * oneDay, 21 * oneDay, 14 * oneDay, 14 * oneDay, 14 * oneDay, 14 * oneDay, 7 * oneDay, 7 * oneDay, 7 * oneDay];
    const pricesLP = ["94581006194509583366", "90281999952533219560", "86251681600680378492", "82490051138951060162",
        "78997108567345264570", "76116346119503688058", "73187112785010524266", "70453161672816904726",
        "68109775005222373690", "65766388337627842656", "63618283892332855874"];
    const supplies = ["70000" + "0".repeat(18), "70000" + "0".repeat(18), "80000" + "0".repeat(18), "80000" + "0".repeat(18),
        "100000" + "0".repeat(18), "100000" + "0".repeat(18), "100000" + "0".repeat(18), "100000" + "0".repeat(18), "100000" + "0".repeat(18),
        "100000" + "0".repeat(18), "100000" + "0".repeat(18)];

    for (let i = 0; i < pricesLP.length; i++) {
        targets.push(depositoryTwoAddress);
        values.push(0);
        callDatas.push(depository.interface.encodeFunctionData("create", [parsedData.OLAS_ETH_PairAddress, pricesLP[i], supplies[i], vestings[i]]));
    }

    const description = "Close old products and create new ones";

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
