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
    const modeDepositProcessorL1Address = parsedData.modeDepositProcessorL1Address;
    const modeTargetDispenserL2Address = parsedData.modeTargetDispenserL2Address;
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

    // Get the contract instance
    const modeDepositProcessorL1 = await ethers.getContractAt("OptimismDepositProcessorL1", modeDepositProcessorL1Address);

    // Transaction signing and execution
    console.log("12. EOA to set TargetDispenserL2 in DepositProcessorL1 on Mode");
    console.log("You are signing the following transaction: OptimismDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    const result = await modeDepositProcessorL1.connect(EOA).setL2TargetDispenser(modeTargetDispenserL2Address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
