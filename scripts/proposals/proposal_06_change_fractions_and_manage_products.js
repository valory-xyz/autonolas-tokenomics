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
    console.log("Proposal 5. Change tokenomics top-up and bonding fractions, close old products and create new ones");
    const targets = [depositoryTwoAddress, tokenomicsProxyAddress];
    const values = [0, 0];
    const callDatas = [
        depository.interface.encodeFunctionData("close", [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]),
        tokenomics.interface.encodeFunctionData("changeIncentiveFractions", [83, 17, 95, 4, 1])
    ];

    // Additional products to create with depository contract
    const vesting = 3600 * 24 * 7;
    const pricesLP = ["248552225555891292658","239199446069592728050","229846666583294163442","220493887096995598809","211141107610697034201"];
    const supplies = ["200000000000000000000000","300000000000000000000000","400000000000000000000000","400000000000000000000000","500000000000000000000000"];

    for (let i = 0; i < pricesLP.length; i++) {
        targets.push(depositoryTwoAddress);
        values.push(0);
        callDatas.push(depository.interface.encodeFunctionData("create", [parsedData.OLAS_ETH_PairAddress, pricesLP[i], supplies[i], vesting]));
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
