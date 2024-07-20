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
    const baseDepositProcessorL1Address = parsedData.baseDepositProcessorL1Address;
    const celoDepositProcessorL1Address = parsedData.celoDepositProcessorL1Address;
    const gnosisDepositProcessorL1Address = parsedData.gnosisDepositProcessorL1Address;
    const optimismDepositProcessorL1Address = parsedData.optimismDepositProcessorL1Address;
    const polygonDepositProcessorL1Address = parsedData.polygonDepositProcessorL1Address;
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
    console.log("10. EOA to set deposit processors in Dispenser");
    console.log("You are signing the following transaction: Dispenser.connect(EOA).setDepositProcessorChainIds()");
    const ethereumChainId = (await provider.getNetwork()).chainId;
    const result = await setL2TargetDispenser.connect(EOA).setDepositProcessorChainIds([arbitrumDepositProcessorL1Address,
        baseDepositProcessorL1Address, celoDepositProcessorL1Address, ethereumDepositProcessorAddress,
        gnosisDepositProcessorL1Address, optimismDepositProcessorL1Address, polygonDepositProcessorL1Address],
        [parsedData.arbitrumL2TargetChainId, parsedData.baseL2TargetChainId, parsedData.celoL2TargetChainId, ethereumChainId,
        parsedData.gnosisL2TargetChainId, parsedData.optimisticL2TargetChainId, parsedData.polygonL2TargetChainId]);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
