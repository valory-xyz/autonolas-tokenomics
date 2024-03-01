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
    const callDatas = [depository.interface.encodeFunctionData("close", [[30,31]])];

    // Additional products to create with depository contract
    const oneDay = 3600 * 24;
    const vestings = [90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay, 90*oneDay, 45*oneDay];
    const pricesLP = ["1417088700721071600", "1417088700721071600", "1350257832250301000", "1350257832250301000", "1294565441857992000", "1294565441857992000", "1240009805859382000", "1240009805859382000", "1194546033276477200", "1194546033276477200", "1152293641444225400", "1152293641444225400", "1117165357297200300", "1117165357297200300", "1084112585527601800", "1084112585527601800", "1052956742336489100", "1052956742336489100"];
    const supplies = ["27500" + "0".repeat(18), "27500" + "0".repeat(18), "65000" + "0".repeat(18), "65000" + "0".repeat(18),"125000" + "0".repeat(18), "125000" + "0".repeat(18), "180000" + "0".repeat(18), "180000" + "0".repeat(18), "200000" + "0".repeat(18),"200000" + "0".repeat(18), "180000" + "0".repeat(18), "180000" + "0".repeat(18), "125000" + "0".repeat(18), "125000" + "0".repeat(18), "65000" + "0".repeat(18), "65000" + "0".repeat(18), "27500" + "0".repeat(18), "27500" + "0".repeat(18)];

    for (let i = 0; i < pricesLP.length; i++) {
        targets.push(depositoryTwoAddress);
        values.push(0);
        callDatas.push(depository.interface.encodeFunctionData("create", [parsedData.OLAS_WXDAI_PairAddress, pricesLP[i], supplies[i], vestings[i]]));
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
