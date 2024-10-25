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
    const voteWeightingAddress = parsedData.voteWeightingAddress;
    const retainerAddress = parsedData.retainerAddress;
    const maxNumClaimingEpochs = parsedData.maxNumClaimingEpochs;
    const maxNumStakingTargets = parsedData.maxNumStakingTargets;
    const minStakingWeight = parsedData.minStakingWeight;
    const maxStakingIncentive = parsedData.maxStakingIncentive;

    // Transaction signing and execution
    console.log("7. EOA to deploy Dispenser");
    const Dispenser = await ethers.getContractFactory("Dispenser");
    console.log("You are signing the following transaction: Dispenser.connect(EOA).deploy()");
    const dispenser = await Dispenser.connect(EOA).deploy(olasAddress, tokenomicsProxyAddress, treasuryAddress,
        voteWeightingAddress, retainerAddress, maxNumClaimingEpochs, maxNumStakingTargets, minStakingWeight,
        maxStakingIncentive);
    const result = await dispenser.deployed();

    // Transaction details
    console.log("Contract deployment: Dispenser");
    console.log("Contract address:", dispenser.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait half a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_07_dispenser.js --network " + providerName + " " + dispenser.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.dispenserAddress = dispenser.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
