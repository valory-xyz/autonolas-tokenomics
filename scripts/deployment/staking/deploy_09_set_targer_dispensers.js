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
    const arbitrumDepositProcessorL1Address = parsedData.arbitrumDepositProcessorL1Address;
    const arbitrumTargetDispenserL2Address = parsedData.arbitrumTargetDispenserL2Address;
    const baseDepositProcessorL1Address = parsedData.baseDepositProcessorL1Address;
    const baseTargetDispenserL2Address = parsedData.baseTargetDispenserL2Address;
    const celoDepositProcessorL1Address = parsedData.celoDepositProcessorL1Address;
    const celoTargetDispenserL2Address = parsedData.celoTargetDispenserL2Address;
    const gnosisDepositProcessorL1Address = parsedData.gnosisDepositProcessorL1Address;
    const gnosisTargetDispenserL2Address = parsedData.gnosisTargetDispenserL2Address;
    const optimismDepositProcessorL1Address = parsedData.optimismDepositProcessorL1Address;
    const optimismTargetDispenserL2Address = parsedData.optimismTargetDispenserL2Address;
    const polygonDepositProcessorL1Address = parsedData.polygonDepositProcessorL1Address;
    const polygonTargetDispenserL2Address = parsedData.polygonTargetDispenserL2Address;
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

    // Get all the contracts
    const arbitrumDepositProcessorL1 = await ethers.getContractAt("ArbitrumDepositProcessorL1", arbitrumDepositProcessorL1Address);
    const baseDepositProcessorL1 = await ethers.getContractAt("OptimismDepositProcessorL1", baseDepositProcessorL1Address);
    const celoDepositProcessorL1 = await ethers.getContractAt("WormholeDepositProcessorL1", celoDepositProcessorL1Address);
    const gnosisDepositProcessorL1 = await ethers.getContractAt("GnosisDepositProcessorL1", gnosisDepositProcessorL1Address);
    const optimismDepositProcessorL1 = await ethers.getContractAt("OptimismDepositProcessorL1", optimismDepositProcessorL1Address);
    const polygonDepositProcessorL1 = await ethers.getContractAt("PolygonDepositProcessorL1", polygonDepositProcessorL1Address);

    // Transaction signing and execution
    console.log("9. EOA to set TargetDispenserL2 in DepositProcessorL1");

    console.log("You are signing the following transaction: ArbitrumDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    let result = await arbitrumDepositProcessorL1.connect(EOA).setL2TargetDispenser(arbitrumTargetDispenserL2Address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: OptimismDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    result = await baseDepositProcessorL1.connect(EOA).setL2TargetDispenser(baseTargetDispenserL2Address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: WormholeDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    result = await celoDepositProcessorL1.connect(EOA).setL2TargetDispenser(celoTargetDispenserL2Address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: GnosisDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    result = await gnosisDepositProcessorL1.connect(EOA).setL2TargetDispenser(gnosisTargetDispenserL2Address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: OptimismDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    result = await optimismDepositProcessorL1.connect(EOA).setL2TargetDispenser(optimismTargetDispenserL2Address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: PolygonDepositProcessorL1.connect(EOA).setL2TargetDispenser()");
    result = await polygonDepositProcessorL1.connect(EOA).setL2TargetDispenser(polygonTargetDispenserL2Address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
