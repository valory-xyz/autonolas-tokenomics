/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");
const AddressZero = ethers.constants.AddressZero;

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

// Custom expect for contain clause that is wrapped into try / catch block
function customExpectContain(arg1, arg2, log) {
    try {
        expect(arg1).contain(arg2);
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

// Check the bytecode
async function checkBytecode(provider, configContracts, contractName, log) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            const bytecode = parsedFile["deployedBytecode"];
            const onChainCreationCode = await provider.getCode(configContracts[i]["address"]);

            // Compare last 8-th part of deployed bytecode bytes (wveOLAS can't manage more)
            // We cannot compare the full one since the repo deployed bytecode does not contain immutable variable info
            const slicePart = -bytecode.length / 8;
            customExpectContain(onChainCreationCode, bytecode.slice(slicePart),
                log + ", address: " + configContracts[i]["address"] + ", failed bytecode comparison");
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
    // Check the contract owner
    const owner = await donatorBlacklist.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");
}

// Check Tokenomics Proxy: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkTokenomicsProxy(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const tokenomics = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + tokenomics.address;
    // Check contract owner
    const owner = await tokenomics.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");

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

    // Check tokenomics implementation address
    const implementationHash = await tokenomics.PROXY_TOKENOMICS();
    const implementation = await provider.getStorageAt(tokenomics.address, implementationHash);
    // Need to extract address size of bytes from the storage return value
    customExpect("0x" + implementation.slice(-40), globalsInstance["tokenomicsFourAddress"].toLowerCase(),
        log + ", function: PROXY_TOKENOMICS()");
}

// Check Treasury: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkTreasury(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const treasury = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + treasury.address;
    // Check contract owner
    const owner = await treasury.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");

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
    // Check contract owner
    const owner = await dispenser.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");

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
    // Check contract owner
    const owner = await depository.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");

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
    customExpect(l1TokenRelayer, globalsInstance["optimisticL1StandardBridgeProxyAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await optimismDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["optimisticL1CrossDomainMessengerProxyAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await optimismDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["optimisticL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L2 OLAS address
    const olasL2 = await optimismDepositProcessorL1.olasL2();
    customExpect(olasL2, globalsInstance["optimisticOLASAddress"], log + ", function: olasL2()");

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

// Check ModeDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkModeDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const modeDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName, 2);

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

// Check CeloDepositProcessorL1: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkCeloDepositProcessorL1(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const celoDepositProcessorL1 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + celoDepositProcessorL1.address;
    await checkDepositProcessorL1(celoDepositProcessorL1, globalsInstance, log);

    // Check L1 token relayer
    const l1TokenRelayer = await celoDepositProcessorL1.l1TokenRelayer();
    customExpect(l1TokenRelayer, globalsInstance["wormholeL1TokenRelayerAddress"], log + ", function: l1TokenRelayer()");

    // Check L1 message relayer
    const l1MessageRelayer = await celoDepositProcessorL1.l1MessageRelayer();
    customExpect(l1MessageRelayer, globalsInstance["wormholeL1MessageRelayerAddress"], log + ", function: l1MessageRelayer()");

    // Check L2 target chain Id
    const l2TargetChainId = await celoDepositProcessorL1.l2TargetChainId();
    customExpect(l2TargetChainId.toString(), globalsInstance["celoL2TargetChainId"], log + ", function: l2TargetChainId()");

    // Check L1 wormhole core
    const wormhole = await celoDepositProcessorL1.wormhole();
    customExpect(wormhole, globalsInstance["wormholeL1CoreAddress"], log + ", function: wormhole()");

    // Check L2 wormhole chain Id format
    const wormholeTargetChainId = await celoDepositProcessorL1.wormholeTargetChainId();
    customExpect(wormholeTargetChainId.toString(), globalsInstance["celoWormholeL2TargetChainId"], log + ", function: wormholeTargetChainId()");

    // Check L2 target dispenser
    const l2TargetDispenser = await celoDepositProcessorL1.l2TargetDispenser();
    customExpect(l2TargetDispenser, globalsInstance["celoTargetDispenserL2Address"], log + ", function: l2TargetDispenser()");
}

// Check TargetDispenserL2: contract, globalsInstance
async function checkTargetDispenserL2(targetDispenserL2, globalsInstance, log) {
    log += ", address: " + targetDispenserL2.address;
    // Check contract owner
    const owner = await targetDispenserL2.owner();
    customExpect(owner, globalsInstance["bridgeMediatorAddress"], log + ", function: owner()");

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
    await checkTargetDispenserL2(polygonTargetDispenserL2, globalsInstance, log);

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
    await checkTargetDispenserL2(gnosisTargetDispenserL2, globalsInstance, log);

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
    await checkTargetDispenserL2(arbitrumTargetDispenserL2, globalsInstance, log);

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
    await checkTargetDispenserL2(optimismTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await optimismTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["optimisticL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

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
    await checkTargetDispenserL2(baseTargetDispenserL2, globalsInstance, log);

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
    await checkTargetDispenserL2(modeTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await modeTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["modeL2CrossDomainMessengerAddress"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await modeTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["modeDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");
}

// Check CeloTargetDispenserL2: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkCeloTargetDispenserL2(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const celoTargetDispenserL2 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + celoTargetDispenserL2.address;
    await checkTargetDispenserL2(celoTargetDispenserL2, globalsInstance, log);

    // Check L2 message relayer
    const l2MessageRelayer = await celoTargetDispenserL2.l2MessageRelayer();
    customExpect(l2MessageRelayer, globalsInstance["wormholeL2MessageRelayer"], log + ", function: l2MessageRelayer()");

    // Check L1 deposit processor
    const l1DepositProcessor = await celoTargetDispenserL2.l1DepositProcessor();
    customExpect(l1DepositProcessor, globalsInstance["celoDepositProcessorL1Address"], log + ", function: l1DepositProcessor()");

    // Check L2 wormhole core
    const wormhole = await celoTargetDispenserL2.wormhole();
    customExpect(wormhole, globalsInstance["wormholeL2CoreAddress"], log + ", function: wormhole()");
}

async function main() {
    // Check for the API keys
    if (!process.env.ALCHEMY_API_KEY_MAINNET || !process.env.ALCHEMY_API_KEY_SEPOLIA ||
        !process.env.ALCHEMY_API_KEY_MATIC || !process.env.ALCHEMY_API_KEY_AMOY) {
        console.log("Check API keys!");
        return;
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    // ################################# VERIFY CONTRACTS WITH REPO #################################
    console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

    // Currently the verification is fo mainnet only
    const network = "etherscan";
    const contracts = configs[0]["contracts"];

    // Verify contracts
    for (let i = 0; i < contracts.length; i++) {
        console.log("Checking " + contracts[i]["name"]);
        const execSync = require("child_process").execSync;
        try {
            execSync("scripts/audit_chains/audit_repo_contract.sh " + network + " " + contracts[i]["name"] + " " + contracts[i]["address"]);
        } catch (error) {
            continue;
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    const globalNames = {
        "mainnet": "scripts/deployment/globals_mainnet.json",
        "polygon": "scripts/deployment/staking/polygon/globals_polygon_mainnet.json",
        "gnosis": "scripts/deployment/staking/gnosis/globals_gnosis_mainnet.json",
        "arbitrumOne": "scripts/deployment/staking/arbitrum/globals_arbitrum_one.json",
        "optimistic": "scripts/deployment/staking/optimistic/globals_optimistic_mainnet.json",
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
        "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
        "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
        "gnosis": "https://rpc.gnosischain.com",
        "arbitrumOne": "https://arb1.arbitrum.io/rpc",
        "optimistic": "https://optimism.drpc.org",
        "base": "https://mainnet.base.org",
        "celo": "https://forno.celo.org",
        "mode": "https://mainnet.mode.network"
    };

    const providers = new Array();
    for (let k in providerLinks) {
        const provider = new ethers.providers.JsonRpcProvider(providerLinks[k]);
        providers.push(provider);
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
    await checkCeloDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "WormholeDepositProcessorL1", log);

    log = initLog + ", contract: " + "ModeDepositProcessorL1";
    await checkModeDepositProcessorL1(configs[0]["chainId"], providers[0], globalsStaking, configs[0]["contracts"], "OptimismDepositProcessorL1", log);

    // L2 contracts
    let chainNumber = 1;
    // Polygon
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "PolygonTargetDispenserL2";
    await checkPolygonTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "PolygonTargetDispenserL2", log);
    chainNumber++;

    // Gnosis
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "GnosisTargetDispenserL2";
    await checkGnosisTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "GnosisTargetDispenserL2", log);
    chainNumber++;

    // Arbitrum
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "ArbitrumTargetDispenserL2";
    await checkArbitrumTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "ArbitrumTargetDispenserL2", log);
    chainNumber++;

    // Optimism
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "OptimismTargetDispenserL2";
    await checkOptimismTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
    chainNumber++;

    // Base
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "BaseTargetDispenserL2";
    await checkBaseTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
    chainNumber++;

    // Celo
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "CeloTargetDispenserL2";
    await checkCeloTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "WormholeTargetDispenserL2", log);
    chainNumber++;

    // Mode
    console.log("\n######## Verifying setup on CHAIN ID", configs[chainNumber]["chainId"]);
    initLog = "ChainId: " + configs[chainNumber]["chainId"] + ", network: " + configs[chainNumber]["name"];
    log = initLog + ", contract: " + "OptimismTargetDispenserL2";
    await checkModeTargetDispenserL2(configs[chainNumber]["chainId"], providers[chainNumber], globals[chainNumber], configs[chainNumber]["contracts"], "OptimismTargetDispenserL2", log);
    // ################################# /VERIFY CONTRACTS SETUP #################################
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });