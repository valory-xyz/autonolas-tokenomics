/*global process*/
/*
 * NOTE: this script does NOT register the Mode processor.
 *
 * Mode's L1 processor is deployed at step 11, after this step runs, so its address does not exist
 * yet here. `deploy_10_set_deposit_processors.sh` is the current equivalent and registers all eight
 * routes including Mode; prefer it. A chain left unregistered resolves to a zero processor and
 * reverts the claim - in the batch path it takes the other chains' claims down with it - so a
 * fresh deployment that uses this script must register Mode separately afterwards.
 */


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
    const ethereumDepositProcessorAddress = parsedData.ethereumDepositProcessorAddress;
    const dispenserProxyAddress = parsedData.dispenserProxyAddress;
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
    const celoDepositProcessorL1 = await ethers.getContractAt("OptimismDepositProcessorL1", celoDepositProcessorL1Address);
    const gnosisDepositProcessorL1 = await ethers.getContractAt("GnosisDepositProcessorL1", gnosisDepositProcessorL1Address);
    const optimismDepositProcessorL1 = await ethers.getContractAt("OptimismDepositProcessorL1", optimismDepositProcessorL1Address);
    const polygonDepositProcessorL1 = await ethers.getContractAt("PolygonDepositProcessorL1", polygonDepositProcessorL1Address);
    const dispenser = await ethers.getContractAt("Dispenser", dispenserProxyAddress);

    // Transaction signing and execution
    console.log("10. EOA to set deposit processors in Dispenser");
    console.log("You are signing the following transaction: Dispenser.connect(EOA).setDepositProcessorChainIds()");
    const ethereumChainId = (await provider.getNetwork()).chainId;
    const result = await dispenser.connect(EOA).setDepositProcessorChainIds([arbitrumDepositProcessorL1Address,
        baseDepositProcessorL1Address, celoDepositProcessorL1Address, ethereumDepositProcessorAddress,
        gnosisDepositProcessorL1Address, optimismDepositProcessorL1Address, polygonDepositProcessorL1Address],
    [parsedData.arbitrumL2TargetChainId, parsedData.baseL2TargetChainId, parsedData.celoL2TargetChainId, ethereumChainId,
        parsedData.gnosisL2TargetChainId, parsedData.optimismL2TargetChainId, parsedData.polygonL2TargetChainId]);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
