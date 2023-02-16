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
    const timelockAddress = parsedData.timelockAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
    const dispenserAddress = parsedData.dispenserAddress;

    // Transaction signing and execution
    console.log("10. EOA to transfer ownership rights of TokenomicsProxy to Timelock");
    const tokenomicsProxy = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    console.log("You are signing the following transaction: TokenomicsProxy.connect(EOA).changeOwner()");
    let result = await tokenomicsProxy.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", tokenomicsProxyAddress);
    console.log("Transaction:", result.hash);

    // Transaction signing and execution
    console.log("11. EOA to transfer ownership rights of Treasury to Timelock");
    const treasury = await ethers.getContractAt("Treasury", treasuryAddress);
    console.log("You are signing the following transaction: Treasury.connect(EOA).changeOwner()");
    result = await treasury.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", treasuryAddress);
    console.log("Transaction:", result.hash);

    // Transaction signing and execution
    console.log("12. EOA to transfer ownership rights of Depository to Timelock");
    const depository = await ethers.getContractAt("Depository", depositoryAddress);
    console.log("You are signing the following transaction: Depository.connect(EOA).changeOwner()");
    result = await depository.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", depositoryAddress);
    console.log("Transaction:", result.hash);

    // Transaction signing and execution
    console.log("13. EOA to transfer ownership rights of Dispenser to Timelock");
    const dispenser = await ethers.getContractAt("Dispenser", dispenserAddress);
    console.log("You are signing the following transaction: Dispenser.connect(EOA).changeOwner()");
    result = await dispenser.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", dispenserAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
