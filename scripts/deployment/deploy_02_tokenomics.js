/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    let EOA;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("2. EOA to deploy Tokenomics");
    const Tokenomics = await ethers.getContractFactory("Tokenomics");
    console.log("You are signing the following transaction: Tokenomics.connect(EOA).deploy()");
    const tokenomics = await Tokenomics.connect(EOA).deploy();
    const result = await tokenomics.deployed();

    // Transaction details
    console.log("Contract deployment: Tokenomics");
    console.log("Contract address:", tokenomics.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.tokenomicsFourAddress = tokenomics.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + tokenomics.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
