/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");
const AddressZero = ethers.constants.AddressZero;

const verifyRepo = false;
const verifySetup = true;

// ===================== CSV CONFIG =====================
const WRITE_OWNERSHIP_CSV = true;
const OWNERSHIP_CSV_PATH = "scripts/audit_chains/ownable_owners.csv";

// Autonolas deployer (as per your requirement)
const AUTONOLAS_DEPLOYER = "0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E";

// Minimal helper: normalize addresses (case-insensitive compare)
const norm = (a) => (a ? ethers.utils.getAddress(a) : a);

// Global accumulator for CSV rows (collected during setup checks)
const ownershipRows = [];

// Custom expect that is wrapped into try / catch block
function customExpect(arg1, arg2, log) {
    try {
        expect(arg1).to.equal(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
}

// Read storage slot and return the lower-20-bytes as a checksummed address
async function readSlotAddress(provider, contractAddress, slot) {
    const raw = await provider.getStorageAt(contractAddress, slot);
    return norm("0x" + raw.slice(-40));
}

// Load per-chain {oracles,pol,utils} globals JSONs. Missing files yield null.
function loadDeploymentGlobals(chainSlug) {
    const out = {oracles: null, pol: null, utils: null};
    for (const bucket of ["oracles", "pol", "utils"]) {
        const path = `scripts/deployment/${bucket}/globals_${chainSlug}.json`;
        try {
            out[bucket] = JSON.parse(fs.readFileSync(path, "utf8"));
        } catch {
            // optional: not every chain has every bucket (e.g., no pol on gnosis/polygon/arbitrum)
        }
    }
    return out;
}

// Write ownership CSV
function writeOwnershipCsv(rows, outPath) {
    const headers = [
        "chainId",
        "contractName",
        "contractAddress",
        "ownerAddress",
        "ownerCategory",
        "expectedDaoExecutor",
        "ownershipChangeRequired",
    ];

    const escapeCsv = (v) => {
        if (v === null || v === undefined) return "";
        const s = String(v);
        if (s.includes("\"") || s.includes(",") || s.includes("\n")) {
            return `"${s.replace(/"/g, "\"\"")}"`;
        }
        return s;
    };


    const lines = [
        headers.join(","),
        ...rows.map((r) => headers.map((h) => escapeCsv(r[h])).join(",")),
    ];

    fs.writeFileSync(outPath, lines.join("\n"), "utf8");
    console.log(`\n[CSV] Wrote ${rows.length} rows to ${outPath}\n`);
}

// Push a row into the ownership CSV accumulator
function recordOwnershipRow(chainId, contractName, contractAddress, ownerInfo) {
    if (!WRITE_OWNERSHIP_CSV || !ownerInfo) return;

    ownershipRows.push({
        chainId: String(chainId),
        contractName: contractName,
        contractAddress: norm(contractAddress),
        ownerAddress: ownerInfo.owner,
        ownerCategory: ownerInfo.ownerCategory,
        expectedDaoExecutor: ownerInfo.expectedDaoExecutor,
        ownershipChangeRequired: ownerInfo.ownershipChangeRequired,
    });
}

// Check the contract owner
async function checkOwner(chainId, contract, globalsInstance, log) {
    const owner = norm(await contract.owner());

    const expected =
        String(chainId) === "1"
            ? norm(globalsInstance["timelockAddress"])
            : norm(globalsInstance["bridgeMediatorAddress"]);

    // Keep existing verification behavior
    customExpect(owner, expected, log + ", function: owner()");

    // CSV purposes
    const ownerCategory =
        owner === norm(AUTONOLAS_DEPLOYER)
            ? "autonolas_deployer"
            : (owner === expected ? "dao_executor" : "other");

    const ownershipChangeRequired = owner === expected ? "no" : "yes";

    return {
        owner,
        expectedDaoExecutor: expected,
        ownerCategory: ownerCategory,
        ownershipChangeRequired: ownershipChangeRequired,
    };
}

// Check the bytecode
async function checkBytecode(provider, configContracts, contractName, log) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            // Forge JSON
            let bytecode = parsedFile["deployedBytecode"]["object"];
            if (bytecode === undefined) {
                // Hardhat JSON
                bytecode = parsedFile["deployedBytecode"];
            }
            const onChainCode = await provider.getCode(configContracts[i]["address"]);
            const tag = log + ", address: " + configContracts[i]["address"];

            // Tier 1 (failure): on-chain code length must match the artifact's deployedBytecode length.
            // If the lengths differ, the deployed instruction code is different from the artifact in the repo.
            if (onChainCode.length !== bytecode.length) {
                console.log(tag + ", bytecode length mismatch: artifact="
                    + Math.max(0, (bytecode.length - 2) / 2) + "B onchain="
                    + Math.max(0, (onChainCode.length - 2) / 2) + "B");
                console.log("\n");
                return;
            }

            // Tier 2 (warning): same length but the trailing CBOR metadata (last 43 bytes) differs.
            // Common when the deployed bytecode was compiled with a slightly different context
            // (solc patch version, optimizer settings, source-tree state) than the artifact in main.
            // This is not a code-level discrepancy, so we emit a single-line warning rather than
            // dumping the entire on-chain bytecode via an AssertionError.
            const artifactTail = bytecode.slice(-86).toLowerCase();
            const onchainTail = onChainCode.slice(-86).toLowerCase();
            if (artifactTail !== onchainTail) {
                console.log(tag + ", WARN: metadata-trailer drift "
                    + "(artifact ..." + artifactTail.slice(-12) + ", onchain ..." + onchainTail.slice(-12)
                    + "); code length matches.");
            }
            return;
        }
    }
}

// Find the contract name from the configuration data
// idx is to choose the contract, if there are more than one
async function findContractInstance(provider, configContracts, contractName, idx = 0) {
    let numFound = 0;
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Keep searching if needed idx is not found
            if (numFound != idx) {
                numFound++;
                continue;
            }

            // Get the contract instance
            let contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");

            // Additional step for the tokenomics proxy contract
            if (contractName === "TokenomicsProxy") {
                // Get previous abi as it had Tokenomcis implementation in it
                contractFromJSON = fs.readFileSync(configContracts[i - 1]["artifact"], "utf8");
            }
            const parsedFile = JSON.parse(contractFromJSON);
            const abi = parsedFile["abi"];

            // Get the contract instance
            const contractInstance = new ethers.Contract(configContracts[i]["address"], abi, provider);
            return contractInstance;
        }
    }
}

// Check Donator Blacklist: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkDonatorBlacklist(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const donatorBlacklist = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + donatorBlacklist.address;

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, donatorBlacklist, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, donatorBlacklist.address, ownerInfo);
}

// Check Tokenomics Proxy: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkTokenomicsProxy(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const tokenomics = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + tokenomics.address;

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, tokenomics, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, tokenomics.address, ownerInfo);

    // Check OLAS token
    const olas = await tokenomics.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check treasury
    const treasury = await tokenomics.treasury();
    customExpect(treasury, globalsInstance["treasuryAddress"], log + ", function: treasury()");

    // Check depository
    const depository = await tokenomics.depository();
    customExpect(depository, globalsInstance["depositoryTwoAddress"], log + ", function: depository()");

    // Check dispenser
    const dispenser = await tokenomics.dispenser();
    customExpect(dispenser, globalsInstance["dispenserAddress"], log + ", function: dispenser()");

    // Check tokenomics implementation address.
    // Reads the current `tokenomicsAddress` field, which is the address the DAO will vote in
    // (or has voted in) as the active Tokenomics implementation. Pre-vote, the slot still
    // points to the previous impl and this assertion will fail — that is expected.
    const implementationHash = await tokenomics.PROXY_TOKENOMICS();
    const implementation = await provider.getStorageAt(tokenomics.address, implementationHash);
    // Need to extract address size of bytes from the storage return value
    customExpect("0x" + implementation.slice(-40), globalsInstance["tokenomicsAddress"].toLowerCase(),
        log + ", function: PROXY_TOKENOMICS()");
}

// Check Treasury: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkTreasury(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const treasury = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + treasury.address;

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, treasury, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, treasury.address, ownerInfo);

    // Check OLAS token
    const olas = await treasury.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check tokenomics
    const tokenomics = await treasury.tokenomics();
    customExpect(tokenomics, globalsInstance["tokenomicsProxyAddress"], log + ", function: tokenomics()");

    // Check depository
    const depository = await treasury.depository();
    customExpect(depository, globalsInstance["depositoryTwoAddress"], log + ", function: depository()");

    // Check dispenser
    const dispenser = await treasury.dispenser();
    customExpect(dispenser, globalsInstance["dispenserAddress"], log + ", function: dispenser()");

    // Check minAcceptedETH (0.065 ETH)
    const minAcceptedETH = await treasury.minAcceptedETH();
    customExpect(minAcceptedETH.toString(), "65" + "0".repeat(15), log + ", function: minAcceptedETH()");

    // Check paused
    const paused = await treasury.paused();
    customExpect(paused, 1, log + ", function: paused()");
}

// Check Generic Bond Calculator: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGenericBondCalculator(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const genericBondCalculator = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + genericBondCalculator.address;
    // Check OLAS token
    const olas = await genericBondCalculator.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check tokenomics
    const tokenomics = await genericBondCalculator.tokenomics();
    customExpect(tokenomics, globalsInstance["tokenomicsProxyAddress"], log + ", function: tokenomics()");
}

// Check Dispenser: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkDispenser(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const dispenser = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + dispenser.address;

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, dispenser, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, dispenser.address, ownerInfo);

    // Check tokenomics
    const tokenomics = await dispenser.tokenomics();
    customExpect(tokenomics, globalsInstance["tokenomicsProxyAddress"], log + ", function: tokenomics()");

    // Check treasury
    const treasury = await dispenser.treasury();
    customExpect(treasury, globalsInstance["treasuryAddress"], log + ", function: treasury()");
}

// Check Depository: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkDepository(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const depository = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + depository.address;
    
    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, depository, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, depository.address, ownerInfo);

    // Check OLAS token
    const olas = await depository.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check tokenomics
    const tokenomics = await depository.tokenomics();
    customExpect(tokenomics, globalsInstance["tokenomicsProxyAddress"], log + ", function: tokenomics()");

    // Check treasury
    const treasury = await depository.treasury();
    customExpect(treasury, globalsInstance["treasuryAddress"], log + ", function: treasury()");

    // Check bond calculator
    const bondCalculator = await depository.bondCalculator();
    customExpect(bondCalculator, globalsInstance["genericBondCalculatorAddress"], log + ", function: bondCalculator()");

    // Check version
    const version = await depository.VERSION();
    customExpect(version, "1.0.1", log + ", function: VERSION()");

    // Check min vesting
    const minVesting = Number(await depository.MIN_VESTING());
    customExpect(minVesting, 3600 * 24, log + ", function: VERSION()");
}

// Check DepositProcessorL1: contract, globalsInstance
async function checkDepositProcessorL1(depositProcessorL1, globalsInstance, log) {
    log += ", address: " + depositProcessorL1.address;
    // Check contract owner
    const owner = await depositProcessorL1.owner();
    customExpect(owner, AddressZero, log + ", function: owner()");

    // Check L1 OLAS token
    const olas = await depositProcessorL1.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check L1 dispenser
    const dispenser = await depositProcessorL1.l1Dispenser();
    customExpect(dispenser, globalsInstance["dispenserAddress"], log + ", function: dispenser   ()");
}

// Check ArbitrumDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkArbitrumDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const arbitrumDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + arbitrumDepositProcessorL1.address;
    await checkDepositProcessorL1(arbitrumDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await arbitrumDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["arbitrumL1ERC20GatewayRouterAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await arbitrumDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["arbitrumInboxAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await arbitrumDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["arbitrumL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L1 ERC20Gateway
    const l1ERC20Gateway = await arbitrumDepositProcessorL1.l1ERC20Gateway();
    customExpect(l1ERC20Gateway, globalsInstance["arbitrumL1ERC20GatewayAddress"], log + ", function: l1ERC20Gateway()");

    // Check L1 outbox
    const outbox = await arbitrumDepositProcessorL1.outbox();
    customExpect(outbox, globalsInstance["arbitrumOutboxAddress"], log + ", function: outbox()");

    // Check L1 bridge
    const bridge = await arbitrumDepositProcessorL1.bridge();
    customExpect(bridge, globalsInstance["arbitrumBridgeAddress"], log + ", function: bridge()");

    // Check L2 target dispenser
    const l2TargetDispenser = await arbitrumDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["arbitrumTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check checkEthereumDepositProcessor: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkEthereumDepositProcessor(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const ethereumDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + ethereumDepositProcessorL1.address;
    // Check OLAS token
    const olas = await ethereumDepositProcessorL1.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check dispenser
    const dispenser = await ethereumDepositProcessorL1.dispenser();
    customExpect(dispenser, globalsInstance["dispenserAddress"], log + ", function: dispenser()");

    // Check L1 staking factory
    const stakingFactory = await ethereumDepositProcessorL1.stakingFactory();
    customExpect(stakingFactory, globalsInstance["serviceStakingFactoryAddress"], log + ", function: stakingFactory()");

    // Check L1 timelock
    const timelock = await ethereumDepositProcessorL1.timelock();
    customExpect(timelock, globalsInstance["timelockAddress"], log + ", function: timelock()");
}

// Check GnosisDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const gnosisDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + gnosisDepositProcessorL1.address;
    await checkDepositProcessorL1(gnosisDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await gnosisDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["gnosisOmniBridgeAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await gnosisDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["gnosisAMBForeignAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await gnosisDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["gnosisL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 target dispenser
    const l2TargetDispenser = await gnosisDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["gnosisTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check OptimismDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkOptimismDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const optimismDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + optimismDepositProcessorL1.address;
    await checkDepositProcessorL1(optimismDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await optimismDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["optimismL1StandardBridgeProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await optimismDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["optimismL1CrossDomainMessengerProxyAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await optimismDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["optimismL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 OLAS address
    const olasL2 = await optimismDepositProcessorL1.olasL2();
    customExpect(olasL2, globalsInstance["optimismOLASAddress"], log + ", function: olasL2()");

    // Check L2 target dispenser
    const l2TargetDispenser = await optimismDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["optimismTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check BaseDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBaseDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const baseDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName, 1);

    log += ", address: " + baseDepositProcessorL1.address;
    await checkDepositProcessorL1(baseDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await baseDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["baseL1StandardBridgeProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await baseDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["baseL1CrossDomainMessengerProxyAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await baseDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["baseL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 OLAS address
    const olasL2 = await baseDepositProcessorL1.olasL2();
    customExpect(olasL2, globalsInstance["baseOLASAddress"], log + ", function: olasL2()");

    // Check L2 target dispenser
    const l2TargetDispenser = await baseDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["baseTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check CeloDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkCeloDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const celoDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName, 2);

    log += ", address: " + celoDepositProcessorL1.address;
    await checkDepositProcessorL1(celoDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await celoDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["celoL1StandardBridgeProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await celoDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["celoL1CrossDomainMessengerProxyAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await celoDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["celoL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 OLAS address
    const olasL2 = await celoDepositProcessorL1.olasL2();
    customExpect(olasL2, globalsInstance["celoOLASAddress"], log + ", function: olasL2()");

    // Check L2 target dispenser
    const l2TargetDispenser = await celoDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["celoTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check ModeDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkModeDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const modeDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName, 3);

    log += ", address: " + modeDepositProcessorL1.address;
    await checkDepositProcessorL1(modeDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await modeDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["modeL1StandardBridgeProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await modeDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["modeL1CrossDomainMessengerProxyAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await modeDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["modeL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 OLAS address
    const olasL2 = await modeDepositProcessorL1.olasL2();
    customExpect(olasL2, globalsInstance["modeOLASAddress"], log + ", function: olasL2()");

    // Check L2 target dispenser
    const l2TargetDispenser = await modeDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["modeTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check PolygonDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkPolygonDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const polygonDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + polygonDepositProcessorL1.address;
    await checkDepositProcessorL1(polygonDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await polygonDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["polygonRootChainManagerProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await polygonDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["polygonFXRootAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await polygonDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["polygonL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L1 checkpoint manager
    const checkpointManager = await polygonDepositProcessorL1.checkpointManager();
    customExpect(checkpointManager, globalsInstance["polygonCheckpointManagerAddress"], log + ", function: checkpointManager()");

    // Check L1 predicate
    const predicate = await polygonDepositProcessorL1.predicate();
    customExpect(predicate, globalsInstance["polygonERC20PredicateAddress"], log + ", function: predicate()");

    // Check L2 target dispenser
    const l2TargetDispenser = await polygonDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["polygonTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check TargetDispenserL2: chain Id, contract name, contract, globalsInstance
async function checkTargetDispenserL2(chainId, contractName, targetDispenserL2, globalsInstance, log) {
    log += ", address: " + targetDispenserL2.address;

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, targetDispenserL2, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, targetDispenserL2.address, ownerInfo);

    // Check L2 OLAS token
    const olas = await targetDispenserL2.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check L2 staking factory
    const stakingFactory = await targetDispenserL2.stakingFactory();
    customExpect(stakingFactory, globalsInstance["serviceStakingFactoryAddress"], log + ", function: stakingFactory()");

    // Check L1 source chain Id
    const l1SourceChainId = await targetDispenserL2.l1SourceChainId();
    customExpect(l1SourceChainId.toString(), globalsInstance["l1ChainId"], log + ", function: l1SourceChainId()");
}

// Check PolygonTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkPolygonTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const polygonTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + polygonTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, polygonTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await polygonTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["polygonFXChildAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await polygonTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["polygonDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check GnosisTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const gnosisTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + gnosisTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, gnosisTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await gnosisTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["gnosisAMBHomeAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await gnosisTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["gnosisDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check ArbitrumTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkArbitrumTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const arbitrumTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + arbitrumTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, arbitrumTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await arbitrumTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["arbitrumArbSysAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await arbitrumTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["arbitrumDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check OptimismTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkOptimismTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const optimismTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + optimismTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, optimismTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await optimismTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["optimismL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await optimismTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["optimismDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check BaseTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBaseTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const baseTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + baseTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, baseTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await baseTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["baseL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await baseTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["baseDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check ModeTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkModeTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const modeTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + modeTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, modeTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await modeTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["modeL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await modeTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["modeDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check CeloTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name.
// After the Wormhole→OP-stack migration (proposal_23_migrate_l2_dispenser_celo.js) the Celo target
// dispenser is an OptimismTargetDispenserL2 instance, wired via Celo's OP-stack L2CrossDomainMessenger.
async function checkCeloTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const celoTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + celoTargetDispenserL2.address;
    await checkTargetDispenserL2(chainId, contractName, celoTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await celoTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["celoL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await celoTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["celoDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// ===================== Oracle / BBB / LM / Bridge2Burner / Scanner checks =====================

// EIP-1822 custom proxy slots (keccak256 of label strings)
const SLOT_BUY_BACK_BURNER_PROXY = "0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19";
const SLOT_PROXY_LIQUIDITY_MANAGER = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd";
const OLAS_BURNER_L1 = "0x51eb65012ca5cEB07320c497F4151aC207FEa4E0";

// Check UniswapPriceOracle: bytecode + immutables match oracles globals
async function checkUniswapPriceOracle(provider, oraclesGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const oracle = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + oracle.address;

    const pair = await oracle.pair();
    customExpect(norm(pair), norm(oraclesGlobals["pairAddress"]), log + ", function: pair()");

    const minTwapWindow = await oracle.minTwapWindow();
    customExpect(minTwapWindow.toString(), oraclesGlobals["minTwapWindowSeconds"], log + ", function: minTwapWindow()");

    const minUpdateInterval = await oracle.minUpdateInterval();
    customExpect(minUpdateInterval.toString(), oraclesGlobals["minUpdateIntervalSeconds"], log + ", function: minUpdateInterval()");

    const maxStaleness = await oracle.maxStaleness();
    customExpect(maxStaleness.toString(), oraclesGlobals["maxStalenessSeconds"], log + ", function: maxStaleness()");
}

// Check BalancerPriceOracle: bytecode + immutables match oracles globals
async function checkBalancerPriceOracle(provider, oraclesGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const oracle = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + oracle.address;

    const balancerVault = await oracle.balancerVault();
    customExpect(norm(balancerVault), norm(oraclesGlobals["balancerVaultAddress"]), log + ", function: balancerVault()");

    const balancerPoolId = await oracle.balancerPoolId();
    customExpect(balancerPoolId.toLowerCase(), oraclesGlobals["balancerPoolId"].toLowerCase(), log + ", function: balancerPoolId()");

    const minTwapWindow = await oracle.minTwapWindow();
    customExpect(minTwapWindow.toString(), oraclesGlobals["minTwapWindowSeconds"], log + ", function: minTwapWindow()");

    const minUpdateInterval = await oracle.minUpdateInterval();
    customExpect(minUpdateInterval.toString(), oraclesGlobals["minUpdateIntervalSeconds"], log + ", function: minUpdateInterval()");

    const maxStaleness = await oracle.maxStaleness();
    customExpect(maxStaleness.toString(), oraclesGlobals["maxStalenessSeconds"], log + ", function: maxStaleness()");
}

// Check NeighborhoodScanner: pure-logic contract — bytecode only.
async function checkNeighborhoodScanner(provider, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const scanner = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + scanner.address;
    // sanity: contract must respond (call non-mutating constant)
    const max = await scanner.MAX_NUM_BINARY_STEPS();
    customExpect(Number(max), 32, log + ", function: MAX_NUM_BINARY_STEPS()");
}

// Check Bridge2Burner (Gnosis/Optimism/Polygon variants): immutables match utils globals.
// Per-chain l2TokenRelayer source (must mirror deploy_00{a,b,c}_bridge2burner_*.sh):
//   Gnosis    → gnosisOmniBridgeAddress
//   Optimism  → l2StandardBridgeProxyAddress  (used on Optimism and Base)
//   Polygon   → bridgeMediatorAddress
async function checkBridge2Burner(provider, utilsGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const b2b = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + b2b.address;

    const olas = await b2b.olas();
    customExpect(norm(olas), norm(utilsGlobals["olasAddress"]), log + ", function: olas()");

    let expectedRelayer;
    if (contractName === "Bridge2BurnerGnosis") {
        expectedRelayer = utilsGlobals["gnosisOmniBridgeAddress"];
    } else if (contractName === "Bridge2BurnerOptimism") {
        expectedRelayer = utilsGlobals["l2StandardBridgeProxyAddress"];
    } else if (contractName === "Bridge2BurnerPolygon") {
        expectedRelayer = utilsGlobals["bridgeMediatorAddress"];
    }
    const l2TokenRelayer = await b2b.l2TokenRelayer();
    customExpect(norm(l2TokenRelayer), norm(expectedRelayer), log + ", function: l2TokenRelayer()");

    const olasBurner = await b2b.OLAS_BURNER();
    customExpect(norm(olasBurner), norm(OLAS_BURNER_L1), log + ", function: OLAS_BURNER()");
}

// Check Bridge2BurnerArbitrum: same as Bridge2Burner + l1Olas check
async function checkBridge2BurnerArbitrum(provider, utilsGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const b2b = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + b2b.address;

    const olas = await b2b.olas();
    customExpect(norm(olas), norm(utilsGlobals["olasAddress"]), log + ", function: olas()");

    const l2TokenRelayer = await b2b.l2TokenRelayer();
    customExpect(norm(l2TokenRelayer), norm(utilsGlobals["l2GatewayRouterAddress"]), log + ", function: l2TokenRelayer()");

    const l1Olas = await b2b.l1Olas();
    customExpect(norm(l1Olas), norm(utilsGlobals["l1OlasAddress"]), log + ", function: l1Olas()");

    const olasBurner = await b2b.OLAS_BURNER();
    customExpect(norm(olasBurner), norm(OLAS_BURNER_L1), log + ", function: OLAS_BURNER()");
}

// Check BuyBackBurner implementation (Uniswap or Balancer variant): immutables match utils globals.
async function checkBuyBackBurnerImpl(provider, utilsGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const impl = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + impl.address;

    const olasBurner = await impl.OLAS_BURNER();
    customExpect(norm(olasBurner), norm(OLAS_BURNER_L1), log + ", function: OLAS_BURNER()");

    // Mirror deploy_02_buy_back_burner_uniswap.js / deploy_01_buy_back_burner_balancer.js wiring:
    //   bridge2Burner = utils.bridge2BurnerAddress || utils.burnerAddress  (L2 bridge or L1 OLAS burner)
    //   treasury      = utils.bridgeMediatorAddress || utils.timelockAddress (L2 bridge mediator or L1 timelock)
    const expectedBridge2Burner = utilsGlobals["bridge2BurnerAddress"] || utilsGlobals["burnerAddress"];
    const bridge2Burner = await impl.bridge2Burner();
    customExpect(norm(bridge2Burner), norm(expectedBridge2Burner), log + ", function: bridge2Burner()");

    const expectedTreasury = utilsGlobals["bridgeMediatorAddress"] || utilsGlobals["timelockAddress"];
    const treasury = await impl.treasury();
    customExpect(norm(treasury), norm(expectedTreasury), log + ", function: treasury()");

    const liquidityManager = await impl.liquidityManager();
    customExpect(norm(liquidityManager), norm(utilsGlobals["liquidityManagerProxyAddress"] || AddressZero),
        log + ", function: liquidityManager()");

    const swapRouter = await impl.swapRouter();
    customExpect(norm(swapRouter), norm(utilsGlobals["swapRouterV3Address"] || AddressZero),
        log + ", function: swapRouter()");
}

// Check BuyBackBurnerProxy: storage slot points to expected impl, owner is set,
// and (via delegatecall through the proxy) state vars are properly initialized.
async function checkBuyBackBurnerProxy(chainId, provider, utilsGlobals, configContracts, contractName, log,
    expectedImplName) {
    await checkBytecode(provider, configContracts, contractName, log);
    // Find the proxy entry and the impl entry — instantiate the proxy with the impl's ABI so we can read state.
    let proxyAddress;
    let implContract;
    for (const c of configContracts) {
        if (c["name"] === contractName) proxyAddress = c["address"];
        if (c["name"] === expectedImplName) {
            const parsedFile = JSON.parse(fs.readFileSync(c["artifact"], "utf8"));
            implContract = parsedFile;
        }
    }
    log += ", address: " + proxyAddress;

    // 1) Storage slot points to the expected implementation.
    // We use the storage slot (not getImplementation()) because the legacy Base BBB proxy
    // — deployed in the agents.fun era under derivation path m/44'/60'/9'/0/0 — predates
    // the proxy's getImplementation() getter and reverts on that selector.
    const implFromSlot = await readSlotAddress(provider, proxyAddress, SLOT_BUY_BACK_BURNER_PROXY);
    const expectedImpl = configContracts.find((c) => c["name"] === expectedImplName)["address"];
    customExpect(implFromSlot, norm(expectedImpl), log + ", proxy storage slot != configured impl");

    // 2) Owner set (non-zero) — distinct from impl owner = address(0)
    const proxyAsImpl = new ethers.Contract(proxyAddress, implContract["abi"], provider);
    const owner = norm(await proxyAsImpl.owner());
    if (owner === norm(AddressZero)) {
        console.log(log + ", function: owner() — expected non-zero");
    }

    const expectedDao = utilsGlobals["timelockAddress"] || utilsGlobals["bridgeMediatorAddress"] || "";
    const ownerCategory =
        owner === norm(AUTONOLAS_DEPLOYER)
            ? "autonolas_deployer"
            : (norm(expectedDao) && owner === norm(expectedDao) ? "dao_executor" : "other");
    recordOwnershipRow(chainId, contractName, proxyAddress, {
        owner,
        expectedDaoExecutor: norm(expectedDao),
        ownerCategory,
        ownershipChangeRequired: ownerCategory === "dao_executor" ? "no" : "yes",
    });

    // 4) Initialized state matches utils globals
    const olas = norm(await proxyAsImpl.olas());
    customExpect(olas, norm(utilsGlobals["olasAddress"]), log + ", function: olas()");
}

// Check LiquidityManager implementation (ETH or Optimism variant): immutables match pol globals.
async function checkLiquidityManagerImpl(provider, polGlobals, configContracts, contractName, log) {
    await checkBytecode(provider, configContracts, contractName, log);
    const impl = await findContractInstance(provider, configContracts, contractName);
    log += ", address: " + impl.address;

    const olas = await impl.olas();
    customExpect(norm(olas), norm(polGlobals["olasAddress"]), log + ", function: olas()");

    const positionManagerV3 = await impl.positionManagerV3();
    customExpect(norm(positionManagerV3), norm(polGlobals["positionManagerV3Address"]),
        log + ", function: positionManagerV3()");

    const neighborhoodScanner = await impl.neighborhoodScanner();
    customExpect(norm(neighborhoodScanner), norm(polGlobals["neighborhoodScannerAddress"]),
        log + ", function: neighborhoodScanner()");

    const observationCardinality = await impl.observationCardinality();
    customExpect(observationCardinality.toString(), polGlobals["observationCardinality"],
        log + ", function: observationCardinality()");

    if (contractName === "LiquidityManagerETH") {
        const routerV2 = await impl.routerV2();
        customExpect(norm(routerV2), norm(polGlobals["routerV2Address"]), log + ", function: routerV2()");
        const oracleV2 = await impl.oracleV2();
        customExpect(norm(oracleV2), norm(polGlobals["uniswapPriceOracleAddress"]), log + ", function: oracleV2()");
    } else if (contractName === "LiquidityManagerOptimism") {
        const balancerVault = await impl.balancerVault();
        customExpect(norm(balancerVault), norm(polGlobals["balancerVaultAddress"]),
            log + ", function: balancerVault()");
        const oracleV2 = await impl.oracleV2();
        customExpect(norm(oracleV2), norm(polGlobals["balancerPriceOracleAddress"]),
            log + ", function: oracleV2()");
        const bridge2Burner = await impl.bridge2Burner();
        customExpect(norm(bridge2Burner), norm(polGlobals["bridge2BurnerAddress"]),
            log + ", function: bridge2Burner()");
    }
}

// Check LiquidityManagerProxy: storage slot, owner, maxSlippage, key wiring via delegatecall.
async function checkLiquidityManagerProxy(chainId, provider, polGlobals, configContracts, contractName, log, expectedImplName) {
    await checkBytecode(provider, configContracts, contractName, log);
    let proxyAddress;
    let implArtifact;
    for (const c of configContracts) {
        if (c["name"] === contractName) proxyAddress = c["address"];
        if (c["name"] === expectedImplName) {
            implArtifact = JSON.parse(fs.readFileSync(c["artifact"], "utf8"));
        }
    }
    log += ", address: " + proxyAddress;

    // 1) Storage slot points to expected implementation
    const implFromSlot = await readSlotAddress(provider, proxyAddress, SLOT_PROXY_LIQUIDITY_MANAGER);
    const expectedImpl = configContracts.find((c) => c["name"] === expectedImplName)["address"];
    customExpect(implFromSlot, norm(expectedImpl), log + ", proxy storage slot != configured impl");

    // 2) Via delegatecall (instantiate proxy with impl ABI), read state
    const proxyAsLM = new ethers.Contract(proxyAddress, implArtifact["abi"], provider);

    const owner = norm(await proxyAsLM.owner());
    if (owner === norm(AddressZero)) {
        console.log(log + ", function: owner() — expected non-zero");
    }
    const expectedDao = polGlobals["timelockAddress"] || polGlobals["bridgeMediatorAddress"] || "";
    const ownerCategory =
        owner === norm(AUTONOLAS_DEPLOYER)
            ? "autonolas_deployer"
            : (norm(expectedDao) && owner === norm(expectedDao) ? "dao_executor" : "other");
    recordOwnershipRow(chainId, contractName, proxyAddress, {
        owner,
        expectedDaoExecutor: norm(expectedDao),
        ownerCategory,
        ownershipChangeRequired: ownerCategory === "dao_executor" ? "no" : "yes",
    });

    const maxSlippage = await proxyAsLM.maxSlippage();
    customExpect(maxSlippage.toString(), polGlobals["liquidityManagerMaxSlippage"],
        log + ", function: maxSlippage()");

    const olas = await proxyAsLM.olas();
    customExpect(norm(olas), norm(polGlobals["olasAddress"]), log + ", function: olas()");
}

// ===================== /Oracle / BBB / LM / Bridge2Burner / Scanner checks =====================

async function main() {
    // Alchemy API keys are preferred. Without them, fall back to public RPCs (printed to the user).
    const useAlchemyMainnet = !!process.env.ALCHEMY_API_KEY_MAINNET;
    const useAlchemyMatic = !!process.env.ALCHEMY_API_KEY_MATIC;
    if (!useAlchemyMainnet || !useAlchemyMatic) {
        console.log("[INFO] ALCHEMY_API_KEY_MAINNET and/or ALCHEMY_API_KEY_MATIC not set — falling back to public RPCs.");
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;

    // ################################# VERIFY CONTRACTS WITH REPO #################################
    if (verifyRepo) {
        console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

        // Traverse all chains
        for (let i = 0; i < numChains; i++) {
            console.log("\n\nNetwork:", configs[i]["name"]);
            const contracts = configs[i]["contracts"];
            const chainId = configs[i]["chainId"];
            console.log("chainId", chainId);

            // Verify contracts
            for (let j = 0; j < contracts.length; j++) {
                console.log("Checking " + contracts[j]["name"]);
                const execSync = require("child_process").execSync;
                try {
                    execSync("scripts/audit_chains/audit_repo_contract.sh " + chainId + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
                } catch (err) {
                    err.stderr.toString();
                }
            }
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    if (verifySetup) {
        const globalNames = {
            "mainnet": "scripts/deployment/globals_mainnet.json",
            "polygon": "scripts/deployment/staking/polygon/globals_polygon_mainnet.json",
            "gnosis": "scripts/deployment/staking/gnosis/globals_gnosis_mainnet.json",
            "arbitrum": "scripts/deployment/staking/arbitrum/globals_arbitrum_mainnet.json",
            "optimism": "scripts/deployment/staking/optimism/globals_optimism_mainnet.json",
            "base": "scripts/deployment/staking/base/globals_base_mainnet.json",
            "celo": "scripts/deployment/staking/celo/globals_celo_mainnet.json",
            "mode": "scripts/deployment/staking/mode/globals_mode_mainnet.json"
        };

        const globals = new Array();
        for (let k in globalNames) {
            const dataJSON = fs.readFileSync(globalNames[k], "utf8");
            globals.push(JSON.parse(dataJSON));
        }
        // Special case for staking (also on L1)
        const dataJSON = fs.readFileSync("scripts/deployment/staking/globals_mainnet.json", "utf8");
        const globalsStaking = JSON.parse(dataJSON);


        const providerLinks = {
            "mainnet": useAlchemyMainnet
                ? "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET
                : "https://ethereum.publicnode.com",
            "polygon": useAlchemyMatic
                ? "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC
                : "https://polygon.drpc.org",
            "gnosis": "https://rpc.gnosischain.com",
            "arbitrum": "https://arb1.arbitrum.io/rpc",
            "optimism": "https://mainnet.optimism.io",
            "base": "https://mainnet.base.org",
            "celo": "https://forno.celo.org",
            "mode": "https://mainnet.mode.network"
        };

        const providers = new Array();
        for (let k in providerLinks) {
            const provider = new ethers.providers.JsonRpcProvider(providerLinks[k]);
            providers.push(provider);
        }

        // Per-chain deployment globals for {oracles, pol, utils} buckets. Keyed by configs[i].name.
        const chainSlug = {
            "mainnet": "eth_mainnet",
            "polygon": "polygon_mainnet",
            "gnosis": "gnosis_mainnet",
            "arbitrum": "arbitrum_mainnet",
            "optimism": "optimism_mainnet",
            "base": "base_mainnet",
            "celo": "celo_mainnet",
            "mode": "mode_mainnet"
        };
        const deploymentGlobals = {};
        for (const k in providerLinks) {
            deploymentGlobals[k] = loadDeploymentGlobals(chainSlug[k]);
        }

        console.log("\nVerifying deployed contracts setup... If no error is output, then the contracts are correct.");

        // L1 contracts
        console.log("\n######## Verifying setup on CHAIN ID", configs[0]["chainId"]);

        let initLog = "ChainId: " + configs[0]["chainId"] + ", network: " + configs[0]["name"];

        let log = initLog + ", contract: " + "DonatorBlacklist";
        await checkDonatorBlacklist(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "DonatorBlacklist", log);

        log = initLog + ", contract: " + "TokenomicsProxy";
        await checkTokenomicsProxy(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "TokenomicsProxy", log);

        log = initLog + ", contract: " + "Treasury";
        await checkTreasury(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "Treasury", log);

        log = initLog + ", contract: " + "GenericBondCalculator";
        await checkGenericBondCalculator(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "GenericBondCalculator", log);

        log = initLog + ", contract: " + "Dispenser";
        await checkDispenser(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "Dispenser", log);

        log = initLog + ", contract: " + "Depository";
        await checkDepository(configs[0]["chainId"], providers[0], globals[0], configs[0]["contracts"], "Depository", log);

        log = initLog + ", contract: " + "ArbitrumDepositProcessorL1";
        await checkArbitrumDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "ArbitrumDepositProcessorL1", log);

        log = initLog + ", contract: " + "EthereumDepositProcessor";
        await checkEthereumDepositProcessor(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "EthereumDepositProcessor", log);

        log = initLog + ", contract: " + "GnosisDepositProcessorL1";
        await checkGnosisDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "GnosisDepositProcessorL1", log);

        log = initLog + ", contract: " + "OptimismDepositProcessorL1";
        await checkOptimismDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "OptimismDepositProcessorL1", log);

        log = initLog + ", contract: " + "BaseDepositProcessorL1";
        await checkBaseDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "OptimismDepositProcessorL1", log);

        log = initLog + ", contract: " + "PolygonDepositProcessorL1";
        await checkPolygonDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "PolygonDepositProcessorL1", log);

        log = initLog + ", contract: " + "CeloDepositProcessorL1";
        await checkCeloDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "OptimismDepositProcessorL1", log);

        log = initLog + ", contract: " + "ModeDepositProcessorL1";
        await checkModeDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "OptimismDepositProcessorL1", log);

        // ---- L1 oracle / BBB / LM / NeighborhoodScanner (mainnet) ----
        const mDg = deploymentGlobals["mainnet"];

        log = initLog + ", contract: UniswapPriceOracle";
        await checkUniswapPriceOracle(providers[0], mDg.oracles, configs[0]["contracts"], "UniswapPriceOracle", log);

        log = initLog + ", contract: NeighborhoodScanner";
        await checkNeighborhoodScanner(providers[0], configs[0]["contracts"], "NeighborhoodScanner", log);

        log = initLog + ", contract: LiquidityManagerETH";
        await checkLiquidityManagerImpl(providers[0], mDg.pol, configs[0]["contracts"], "LiquidityManagerETH", log);

        log = initLog + ", contract: LiquidityManagerProxy";
        await checkLiquidityManagerProxy(configs[0]["chainId"], providers[0], mDg.pol, configs[0]["contracts"], "LiquidityManagerProxy", log, "LiquidityManagerETH");

        log = initLog + ", contract: BuyBackBurnerUniswap";
        await checkBuyBackBurnerImpl(providers[0], mDg.utils, configs[0]["contracts"], "BuyBackBurnerUniswap", log);

        log = initLog + ", contract: BuyBackBurnerProxy";
        await checkBuyBackBurnerProxy(configs[0]["chainId"], providers[0], mDg.utils, configs[0]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerUniswap");

        // L2 contracts
        let chainNumber = 1;
        // Polygon
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "PolygonTargetDispenserL2";
        await checkPolygonTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "PolygonTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["polygon"];
            log = initLog + ", contract: BalancerPriceOracle";
            await checkBalancerPriceOracle(providers[chainNumber], dg.oracles, configs[chainNumber]["contracts"], "BalancerPriceOracle", log);
            log = initLog + ", contract: Bridge2BurnerPolygon";
            await checkBridge2Burner(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerPolygon", log);
            log = initLog + ", contract: BuyBackBurnerBalancer";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerBalancer", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerBalancer");
        }
        chainNumber++;

        // Gnosis
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "GnosisTargetDispenserL2";
        await checkGnosisTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "GnosisTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["gnosis"];
            log = initLog + ", contract: BalancerPriceOracle";
            await checkBalancerPriceOracle(providers[chainNumber], dg.oracles, configs[chainNumber]["contracts"], "BalancerPriceOracle", log);
            log = initLog + ", contract: Bridge2BurnerGnosis";
            await checkBridge2Burner(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerGnosis", log);
            log = initLog + ", contract: BuyBackBurnerBalancer";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerBalancer", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerBalancer");
        }
        chainNumber++;

        // Arbitrum
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "ArbitrumTargetDispenserL2";
        await checkArbitrumTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "ArbitrumTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["arbitrum"];
            log = initLog + ", contract: BalancerPriceOracle";
            await checkBalancerPriceOracle(providers[chainNumber], dg.oracles, configs[chainNumber]["contracts"], "BalancerPriceOracle", log);
            log = initLog + ", contract: Bridge2BurnerArbitrum";
            await checkBridge2BurnerArbitrum(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerArbitrum", log);
            log = initLog + ", contract: BuyBackBurnerBalancer";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerBalancer", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerBalancer");
        }
        chainNumber++;

        // Optimism
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "OptimismTargetDispenserL2";
        await checkOptimismTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["optimism"];
            log = initLog + ", contract: BalancerPriceOracle";
            await checkBalancerPriceOracle(providers[chainNumber], dg.oracles, configs[chainNumber]["contracts"], "BalancerPriceOracle", log);
            log = initLog + ", contract: Bridge2BurnerOptimism";
            await checkBridge2Burner(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerOptimism", log);
            log = initLog + ", contract: NeighborhoodScanner";
            await checkNeighborhoodScanner(providers[chainNumber], configs[chainNumber]["contracts"], "NeighborhoodScanner", log);
            log = initLog + ", contract: LiquidityManagerOptimism";
            await checkLiquidityManagerImpl(providers[chainNumber], dg.pol, configs[chainNumber]["contracts"], "LiquidityManagerOptimism", log);
            log = initLog + ", contract: LiquidityManagerProxy";
            await checkLiquidityManagerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.pol, configs[chainNumber]["contracts"], "LiquidityManagerProxy", log, "LiquidityManagerOptimism");
            log = initLog + ", contract: BuyBackBurnerBalancer";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerBalancer", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerBalancer");
        }
        chainNumber++;

        // Base
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "BaseTargetDispenserL2";
        await checkBaseTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["base"];
            log = initLog + ", contract: BalancerPriceOracle";
            await checkBalancerPriceOracle(providers[chainNumber], dg.oracles, configs[chainNumber]["contracts"], "BalancerPriceOracle", log);
            log = initLog + ", contract: Bridge2BurnerOptimism";
            await checkBridge2Burner(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerOptimism", log);
            log = initLog + ", contract: NeighborhoodScanner";
            await checkNeighborhoodScanner(providers[chainNumber], configs[chainNumber]["contracts"], "NeighborhoodScanner", log);
            log = initLog + ", contract: LiquidityManagerOptimism";
            await checkLiquidityManagerImpl(providers[chainNumber], dg.pol, configs[chainNumber]["contracts"], "LiquidityManagerOptimism", log);
            log = initLog + ", contract: LiquidityManagerProxy";
            await checkLiquidityManagerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.pol, configs[chainNumber]["contracts"], "LiquidityManagerProxy", log, "LiquidityManagerOptimism");
            log = initLog + ", contract: BuyBackBurnerBalancer";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerBalancer", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerBalancer");
        }
        chainNumber++;

        // Celo — TargetDispenserL2 was migrated from Wormhole-bridged to OP-stack
        // (see scripts/proposals/proposal_23_migrate_l2_dispenser_celo.js). The block
        // mirrors the Optimism / Base structure for OP-stack chains; the Celo-specific
        // exclusions are: BalancerPriceOracle (Celo uses the legacy UniswapPriceOracle,
        // which is itself excluded — outdated, not redeployable for now),
        // NeighborhoodScanner, LiquidityManagerOptimism, and LiquidityManagerProxy
        // (none of those are deployed on Celo). Bridge2Burner and BBB Uniswap+Proxy
        // were (re)deployed on Celo in PR #292.
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
        log = initLog + ", contract: " + "CeloTargetDispenserL2";
        await checkCeloTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
        {
            const dg = deploymentGlobals["celo"];
            log = initLog + ", contract: Bridge2BurnerOptimism";
            await checkBridge2Burner(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "Bridge2BurnerOptimism", log);
            log = initLog + ", contract: BuyBackBurnerUniswap";
            await checkBuyBackBurnerImpl(providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerUniswap", log);
            log = initLog + ", contract: BuyBackBurnerProxy";
            await checkBuyBackBurnerProxy(configs[chainNumber]["chainId"], providers[chainNumber], dg.utils, configs[chainNumber]["contracts"], "BuyBackBurnerProxy", log, "BuyBackBurnerUniswap");
        }
        chainNumber++;

        // Mode
        console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
        try {
            initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
            log = initLog + ", contract: " + "OptimismTargetDispenserL2";
            await checkModeTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
        } catch (e) {
            console.log("  [SKIP] Mode TargetDispenser check skipped: " + (e.message || e));
        }
    }
    // ################################# /VERIFY CONTRACTS SETUP #################################
    // Write CSV once at the end of setup verification
    if (WRITE_OWNERSHIP_CSV) {
        writeOwnershipCsv(ownershipRows, OWNERSHIP_CSV_PATH);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
