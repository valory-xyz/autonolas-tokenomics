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
    const governorAddress = parsedData.governorAddress;
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const treasuryAddress = parsedData.treasuryAddress;

    // Get the GovernorOLAS instance via its ABI
    const GovernorOLASJSON = "scripts/deployment/GovernorOLAS.json";
    let contractFromJSON = fs.readFileSync(GovernorOLASJSON, "utf8");
    let contract = JSON.parse(contractFromJSON);
    const GovernorOLASABI = contract["abi"];
    const governor = await ethers.getContractAt(GovernorOLASABI, governorAddress);

    // Preparing a proposal
    const pAddresses = [olasAddress, serviceRegistryAddress];
    const pValues = [0, 0];
    // [olas.interface.encodeFunctionData("changeMinter", [treasuryAddress]), serviceRegistry.interface.encodeFunctionData("changeDrainer", [treasuryAddress])]
    const pCallData = ["0x2c4d4d18" + "0".repeat(24) + treasuryAddress.replace("0x", ""),
        "0x10c6aa19" + "0".repeat(24) + treasuryAddress.replace("0x", "")];
    const pDescription = "OLAS minter, service registry drainer";

    // Transaction signing and execution
    console.log("15-16. EOA to initiate a proposal for Timelock to transfer the minter role of OLAS to the Treasury and ServiceRegistry to transfer the drainer role to the Treasury");
    console.log("You are signing the following transaction: GovernorOLAS.connect(EOA).propose()");
    const result = await governor.connect(EOA)["propose(address[],uint256[],bytes[],string)"](pAddresses, pValues, pCallData, pDescription);
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }
    // Transaction details
    console.log("Contract address:", governorAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
