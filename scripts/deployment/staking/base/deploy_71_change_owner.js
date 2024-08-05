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
    const baseTargetDispenserL2Address = parsedData.baseTargetDispenserL2Address;
    const bridgeMediatorAddress = parsedData.bridgeMediatorAddress;

    let networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("71. EOA to change owner in OptimismTargetDispenserL2 (Base)");
    const baseTargetDispenserL2 = await ethers.getContractAt("OptimismTargetDispenserL2", baseTargetDispenserL2Address);
    console.log("You are signing the following transaction: OptimismTargetDispenserL2.connect(EOA).changeOwner()");
    const result = await baseTargetDispenserL2.connect(EOA).changeOwner(bridgeMediatorAddress);

    // Transaction details
    console.log("Contract deployment: OptimismTargetDispenserL2");
    console.log("Contract address:", baseTargetDispenserL2.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
