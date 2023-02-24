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
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    // Transaction signing and execution
    console.log("5. EOA to deploy GenericBondCalculator");
    const GenericBondCalculator = await ethers.getContractFactory("GenericBondCalculator");
    console.log("You are signing the following transaction: GenericBondCalculator.connect(EOA).deploy()");
    const genericBondCalculator = await GenericBondCalculator.connect(EOA).deploy(olasAddress, tokenomicsProxyAddress);
    const result = await genericBondCalculator.deployed();
    // If on goerli, wait a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Transaction details
    console.log("Contract deployment: GenericBondCalculator");
    console.log("Contract address:", genericBondCalculator.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_05_generic_bond_calculator.js --network " + providerName + " " + genericBondCalculator.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.genericBondCalculatorAddress = genericBondCalculator.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
