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
    console.log("4. EOA to deploy OptimismDepositProcessorL1");
    const OptimismDepositProcessorL1 = await ethers.getContractFactory("OptimismDepositProcessorL1");
    console.log("You are signing the following transaction: OptimismDepositProcessorL1.connect(EOA).deploy()");
    const optimismDepositProcessorL1 = await OptimismDepositProcessorL1.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.dispenserAddress, parsedData.optimisticL1StandardBridgeProxyAddress,
        parsedData.optimisticL1CrossDomainMessengerProxyAddress, parsedData.optimisticL2TargetChainId,
        parsedData.optimisticOLASAddress);
    const result = await optimismDepositProcessorL1.deployed();

    // Transaction details
    console.log("Contract deployment: OptimismDepositProcessorL1");
    console.log("Contract address:", optimismDepositProcessorL1.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.optimismDepositProcessorL1Address = optimismDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking/verify_04_optimism_deposit_processor.js --network " + providerName + " " + optimismDepositProcessorL1.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
