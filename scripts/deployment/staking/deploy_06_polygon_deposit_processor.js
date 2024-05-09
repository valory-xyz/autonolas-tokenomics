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
    console.log("6. EOA to deploy PolygonDepositProcessorL1");
    const PolygonDepositProcessorL1 = await ethers.getContractFactory("PolygonDepositProcessorL1");
    console.log("You are signing the following transaction: PolygonDepositProcessorL1.connect(EOA).deploy()");
    const polygonDepositProcessorL1 = await PolygonDepositProcessorL1.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.dispenserAddress, parsedData.polygonRootChainManagerProxyAddress,
        parsedData.polygonFXRootAddress, parsedData.polygonL2TargetChainId, parsedData.polygonCheckpointManagerAddress,
        parsedData.polygonERC20PredicateAddress);
    const result = await polygonDepositProcessorL1.deployed();

    // Transaction details
    console.log("Contract deployment: PolygonDepositProcessorL1");
    console.log("Contract address:", polygonDepositProcessorL1.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.polygonDepositProcessorL1Address = polygonDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking/verify_06_polygon_deposit_processor.js --network " + providerName + " " + polygonDepositProcessorL1.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
