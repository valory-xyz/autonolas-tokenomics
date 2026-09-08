/*global process*/
/*
 * Registers every L1 deposit processor in the Dispenser.
 *
 * ORDERING: despite the file number, this is a terminal step rather than step 10 of a linear run.
 * Mode's L1 processor is deployed at step 11 and Robinhood's at step 13, so this must run only once
 * every per-chain processor deploy has completed. It hard-fails on a missing or zero entry rather
 * than registering a partial set: a chain left unregistered resolves to a zero processor and reverts
 * the claim, and in the batch path it takes the other chains' claims down with it.
 *
 * `deploy_10_set_deposit_processors.sh` is the equivalent shell route and is the preferred one.
 *
 * TWO CONSEQUENCES OF THE HARD FAIL, both deliberate:
 *
 *   1. This script is inoperative on `main` until wave 1 deploys. `robinhoodDepositProcessorL1Address`
 *      ships empty, so until Robinhood Chain is live the script throws for EVERY chain, not just
 *      Robinhood. That is the ordering rule above doing its job, but it means someone reaching for
 *      this during an unrelated incident hits a wall that has nothing to do with their chain.
 *
 *   2. It cannot express "disable a route". `Dispenser.setDepositProcessorChainIds` treats a zero
 *      processor as meaningful — "might be zero if there is a need to stop processing a specific L2
 *      chain Id" — and `requireAddress` rejects zero. Disabling a chain is a targeted call with a
 *      one-element array, not this bulk-register tool.
 *
 * NOTE ON PERMISSIONS: `Dispenser.owner()` is the Timelock, so on mainnet this call cannot be sent
 * from the deploying EOA at all — it reverts OwnerOnly and belongs in a governance proposal. Both
 * routes are therefore fresh-deployment tooling and a calldata reference, not an operational path
 * against the live Dispenser.
 */

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

// Processor rows: label, globals key holding the address, globals key holding the L2 target chain Id.
// The Ethereum row is L1-only, so its chain Id is the network's own rather than a globals key.
const PROCESSOR_ROWS = [
    ["Arbitrum", "arbitrumDepositProcessorL1Address", "arbitrumL2TargetChainId"],
    ["Base", "baseDepositProcessorL1Address", "baseL2TargetChainId"],
    ["Celo", "celoDepositProcessorL1Address", "celoL2TargetChainId"],
    ["Gnosis", "gnosisDepositProcessorL1Address", "gnosisL2TargetChainId"],
    ["Mode", "modeDepositProcessorL1Address", "modeL2TargetChainId"],
    ["Optimism", "optimismDepositProcessorL1Address", "optimismL2TargetChainId"],
    ["Polygon", "polygonDepositProcessorL1Address", "polygonL2TargetChainId"],
    ["Robinhood", "robinhoodDepositProcessorL1Address", "robinhoodL2TargetChainId"],
    ["Ethereum", "ethereumDepositProcessorAddress", null]
];

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function requireAddress(parsedData, label, key) {
    const value = parsedData[key];
    if (!value || value === ZERO_ADDRESS) {
        throw new Error(`${label}: ${key} is not set (or zero) in globals.json. Every processor must be ` +
            "deployed before this step runs - see the ordering note at the top of this file.");
    }
    return value;
}

function requireChainId(parsedData, label, key) {
    const value = parsedData[key];
    if (!value || Number(value) === 0) {
        throw new Error(`${label}: ${key} is not set (or zero) in globals.json.`);
    }
    return value;
}

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const dispenserAddress = requireAddress(parsedData, "Dispenser", "dispenserAddress");
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

    const ethereumChainId = (await provider.getNetwork()).chainId;

    // Build the two aligned arrays, hard-failing on any missing or zero entry
    const depositProcessors = [];
    const chainIds = [];
    for (const [label, addressKey, chainIdKey] of PROCESSOR_ROWS) {
        const depositProcessor = requireAddress(parsedData, label, addressKey);
        const chainId = chainIdKey === null ? ethereumChainId : requireChainId(parsedData, label, chainIdKey);
        depositProcessors.push(depositProcessor);
        chainIds.push(chainId);
        console.log(`  ${label}: ${depositProcessor} -> chainId ${chainId}`);
    }

    const dispenser = await ethers.getContractAt("Dispenser", dispenserAddress);

    // Transaction signing and execution
    console.log("10. EOA to set deposit processors in Dispenser");
    console.log("You are signing the following transaction: Dispenser.connect(EOA).setDepositProcessorChainIds()");
    const result = await dispenser.connect(EOA).setDepositProcessorChainIds(depositProcessors, chainIds);
    console.log("Transaction:", result.hash);

    // Await the receipt. Submitting is not succeeding: with the Dispenser Timelock-owned, OwnerOnly is the
    // likeliest failure here, and it reverts AFTER submission - so without this the script would print a
    // hash and exit 0 on a transaction that did nothing.
    const receipt = await result.wait();
    if (receipt.status !== 1) {
        throw new Error(`setDepositProcessorChainIds reverted in ${result.hash}`);
    }

    // Read back every route, mirroring deploy_10_set_deposit_processors.sh. A partially registered Dispenser
    // is the exact state the hard-fail guards above exist to prevent, so it is verified rather than assumed.
    let mismatch = false;
    for (let i = 0; i < depositProcessors.length; i++) {
        const onchain = await dispenser.mapChainIdDepositProcessors(chainIds[i]);
        if (onchain.toLowerCase() !== depositProcessors[i].toLowerCase()) {
            console.error(`  chainId ${chainIds[i]}: on-chain ${onchain} != ${depositProcessors[i]}`);
            mismatch = true;
        }
    }
    if (mismatch) {
        throw new Error("One or more deposit processors did not take effect");
    }
    console.log("All deposit processors whitelisted");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
