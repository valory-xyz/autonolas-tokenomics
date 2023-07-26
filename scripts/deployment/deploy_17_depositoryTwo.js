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
    const treasuryAddress = parsedData.treasuryAddress;
    const genericBondCalculatorAddress = parsedData.genericBondCalculatorAddress;

    // Transaction signing and execution
    console.log("20. EOA to deploy Depository");
    const Depository = await ethers.getContractFactory("Depository");
    console.log("You are signing the following transaction: Depository.connect(EOA).deploy()");
    const depositoryTwo = await Depository.connect(EOA).deploy(olasAddress, tokenomicsProxyAddress, treasuryAddress,
        genericBondCalculatorAddress);
    const result = await depositoryTwo.deployed();

    // Transaction details
    console.log("Contract deployment: Depository");
    console.log("Contract address:", depositoryTwo.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on goerli, wait a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.depositoryTwoAddress = depositoryTwo.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_06_depository.js --network " + providerName + " " + depositoryTwo.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
