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

    // EOA address
    const EOA = signers[0];
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const depositoryTwoAddress = parsedData.depositoryTwoAddress;

    // Get contract instances
    const tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    const depository = await ethers.getContractAt("Depository", depositoryTwoAddress);

    const AddressZero = "0x" + "0".repeat(40);

    // Proposal preparation
    console.log("Proposal 6. Change tokenomics top-up and bonding fractions, close old products and create new ones");
    const targets = [depositoryTwoAddress, tokenomicsProxyAddress];
    const values = [0, 0];
    const callDatas = [
        depository.interface.encodeFunctionData("close", [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]),
        tokenomics.interface.encodeFunctionData("changeIncentiveFractions", [83, 17, 90, 8, 2])
    ];

    // Additional products to create with depository contract
    const oneDay = 3600 * 24;
    const pricesLP = ["185491475634516176834","171739930293108999394","159606213815396784008","149090326201379530672",
        "140504866934837734890", "133345477624551759418", "125737933372879003894", "119271520758957161698", "113565862570202595056"];
    const supplies = ["100000" + "0".repeat(18), "100000" + "0".repeat(18), "100000" + "0".repeat(18), "100000" + "0".repeat(18),
        "100000" + "0".repeat(18), "150000" + "0".repeat(18), "150000" + "0".repeat(18), "150000" + "0".repeat(18), "150000" + "0".repeat(18)];
    const vestings = [28 * oneDay, 28 * oneDay, 21 * oneDay, 21 * oneDay, 14 * oneDay, 14 * oneDay, 7 * oneDay, 7 * oneDay, 7 * oneDay];

    for (let i = 0; i < pricesLP.length; i++) {
        targets.push(depositoryTwoAddress);
        values.push(0);
        callDatas.push(depository.interface.encodeFunctionData("create", [parsedData.OLAS_ETH_PairAddress, pricesLP[i], supplies[i], vestings[i]]));
    }

    const description = "Change tokenomics top-up and bonding fractions, close old products and create new ones";

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
