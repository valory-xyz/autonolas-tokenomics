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
    const networkURL = parsedData.networkURL;

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
    console.log("11. EOA to deploy OptimismTargetDispenserL2 for Mode");
    const OptimismTargetDispenserL2 = await ethers.getContractFactory("OptimismTargetDispenserL2");
    console.log("You are signing the following transaction: OptimismTargetDispenserL2.connect(EOA).deploy()");
    const modeTargetDispenserL2 = await OptimismTargetDispenserL2.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.serviceStakingFactoryAddress, parsedData.modeL2CrossDomainMessengerAddress,
        parsedData.modeDepositProcessorL1Address, parsedData.l1ChainId);
    const result = await modeTargetDispenserL2.deployed();

    // Transaction details
    console.log("Contract deployment: OptimismTargetDispenserL2");
    console.log("Contract address:", modeTargetDispenserL2.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.modeTargetDispenserL2Address = modeTargetDispenserL2.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking/optimistic/verify_11_mode_target_dispenser.js --network " + providerName + " " + modeTargetDispenserL2.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
