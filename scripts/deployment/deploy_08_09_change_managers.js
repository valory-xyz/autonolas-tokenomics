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
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
    const dispenserAddress = parsedData.dispenserAddress;
    const AddressZero = "0x" + "0".repeat(40);

    // Transaction signing and execution
    console.log("8. EOA to change managers for TokenomicsProxy");
    const tokenomicsProxy = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    console.log("You are signing the following transaction: TokenomicsProxy.connect(EOA).changeManagers()");
    let result = await tokenomicsProxy.connect(EOA).changeManagers(treasuryAddress, depositoryAddress, dispenserAddress);
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }
    // Transaction details
    console.log("Contract address:", tokenomicsProxyAddress);
    console.log("Transaction:", result.hash);

    // Transaction signing and execution
    console.log("9. EOA to change managers for Treasury");
    const treasury = await ethers.getContractAt("Treasury", treasuryAddress);
    console.log("You are signing the following transaction: Treasury.connect(EOA).changeManagers()");
    result = await treasury.connect(EOA).changeManagers(AddressZero, depositoryAddress, dispenserAddress);
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }
    // Transaction details
    console.log("Contract address:", treasuryAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
