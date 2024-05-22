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

    let networkURL = parsedData.networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonAmoy") {
        if (!process.env.ALCHEMY_API_KEY_AMOY) {
            console.log("set ALCHEMY_API_KEY_AMOY env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_AMOY;
    }

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
    console.log("3. EOA to deploy GnosisTargetDispenserL2");
    const GnosisTargetDispenserL2 = await ethers.getContractFactory("GnosisTargetDispenserL2");
    console.log("You are signing the following transaction: GnosisTargetDispenserL2.connect(EOA).deploy()");
    const gnosisTargetDispenserL2 = await GnosisTargetDispenserL2.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.serviceStakingFactoryAddress, parsedData.gnosisAMBHomeAddress,
        parsedData.gnosisDepositProcessorL1Address, parsedData.l1ChainId);
    const result = await gnosisTargetDispenserL2.deployed();

    // Transaction details
    console.log("Contract deployment: GnosisTargetDispenserL2");
    console.log("Contract address:", gnosisTargetDispenserL2.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.gnosisTargetDispenserL2Address = gnosisTargetDispenserL2.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking/gnosis/verify_03_gnosis_target_dispenser.js --network " + providerName + " " + gnosisTargetDispenserL2.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
