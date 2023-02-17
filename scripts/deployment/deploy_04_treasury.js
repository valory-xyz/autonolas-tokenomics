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

    // Get all the necessary contract addresses
    const olasAddress = parsedData.olasAddress;
    const timelockAddress = parsedData.timelockAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    // Transaction signing and execution
    console.log("4. EOA to deploy Treasury");
    const Treasury = await ethers.getContractFactory("Treasury");
    console.log("You are signing the following transaction: Treasury.connect(EOA).deploy()");
    const treasury = await Treasury.connect(EOA).deploy(olasAddress, tokenomicsProxyAddress, timelockAddress, timelockAddress);
    const result = await treasury.deployed();
    // If on goerli, wait a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Transaction details
    console.log("Contract deployment: Treasury");
    console.log("Contract address:", treasury.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_04_treasury.js --network " + providerName + " " + treasury.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.treasuryAddress = treasury.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
