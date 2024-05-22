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
    console.log("5. EOA to deploy WormholeDepositProcessorL1");
    const WormholeDepositProcessorL1 = await ethers.getContractFactory("WormholeDepositProcessorL1");
    console.log("You are signing the following transaction: WormholeDepositProcessorL1.connect(EOA).deploy()");
    const wormholeDepositProcessorL1 = await WormholeDepositProcessorL1.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.dispenserAddress, parsedData.wormholeL1TokenRelayerAddress,
        parsedData.wormholeL1MessageRelayerAddress, parsedData.celoL2TargetChainId,
        parsedData.wormholeL1CoreAddress, parsedData.celoWormholeL2TargetChainId);
    const result = await wormholeDepositProcessorL1.deployed();

    // Transaction details
    console.log("Contract deployment: WormholeDepositProcessorL1");
    console.log("Contract address:", wormholeDepositProcessorL1.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.celoWormholeDepositProcessorL1Address = wormholeDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking/verify_05_wormhole_deposit_processor.js --network " + providerName + " " + wormholeDepositProcessorL1.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
