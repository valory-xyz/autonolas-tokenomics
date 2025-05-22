/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

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

    // Get all the necessary contract addresses
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    const tokenomicsProxy = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);

    // Proposal preparation
    console.log("Proposal 16. TokenomicsProxy to update and reset inflation, reset unused bonding and staking inflation");
    const targets = [tokenomicsProxyAddress];
    const values = [0];
    const callDatas = [tokenomicsProxy.interface.encodeFunctionData("updateInflationPerSecondAndFractions", [25, 4, 2, 69])];
    const description = "Update and reset tokenomics inflation, reset unused bonding and staking inflation";

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
