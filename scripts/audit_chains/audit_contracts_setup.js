/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

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
async function findContractInstance(provider, configContracts, contractName) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
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
    customExpect("0x" + implementation.slice(-40), globalsInstance["tokenomicsTwoAddress"].toLowerCase(),
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
    customExpect(paused, false, log + ", function: paused()");
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

async function main() {
    // Check for the API keys
    if (!process.env.ALCHEMY_API_KEY_MAINNET || !process.env.ALCHEMY_API_KEY_GOERLI ||
        !process.env.ALCHEMY_API_KEY_MATIC || !process.env.ALCHEMY_API_KEY_MUMBAI) {
        console.log("Check API keys!");
        return;
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;
    // ################################# VERIFY CONTRACTS WITH REPO #################################
    // For now gnosis chains are not supported
    const networks = {
        "mainnet": "etherscan",
        "goerli": "goerli.etherscan",
    };

    console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

    // Traverse all chains
    for (let i = 0; i < numChains; i++) {
        // Skip gnosis chains
        if (!networks[configs[i]["name"]]) {
            continue;
        }

        console.log("\n\nNetwork:", configs[i]["name"]);
        const network = networks[configs[i]["name"]];
        const contracts = configs[i]["contracts"];

        // Verify contracts
        for (let j = 0; j < contracts.length; j++) {
            console.log("Checking " + contracts[j]["name"]);
            const execSync = require("child_process").execSync;
            try {
                execSync("scripts/audit_chains/audit_repo_contract.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
            } catch (error) {
                continue;
            }
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    const globalNames = {
        "mainnet": "scripts/deployment/globals_mainnet.json",
        "goerli": "scripts/deployment/globals_goerli.json",
    };

    const providerLinks = {
        "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
        "goerli": "https://eth-goerli.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_GOERLI,
    };

    // Get all the globals processed
    const globals = new Array();
    const providers = new Array();
    for (let i = 0; i < numChains; i++) {
        const dataJSON = fs.readFileSync(globalNames[configs[i]["name"]], "utf8");
        globals.push(JSON.parse(dataJSON));
        const provider = new ethers.providers.JsonRpcProvider(providerLinks[configs[i]["name"]]);
        providers.push(provider);
    }

    console.log("\nVerifying deployed contracts setup... If no error is output, then the contracts are correct.");

    // L1 contracts
    for (let i = 0; i < 2; i++) {
        console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

        const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];

        let log = initLog + ", contract: " + "DonatorBlacklist";
        await checkDonatorBlacklist(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "DonatorBlacklist", log);

        log = initLog + ", contract: " + "TokenomicsProxy";
        await checkTokenomicsProxy(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "TokenomicsProxy", log);

        log = initLog + ", contract: " + "Treasury";
        await checkTreasury(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "Treasury", log);

        log = initLog + ", contract: " + "GenericBondCalculator";
        await checkGenericBondCalculator(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GenericBondCalculator", log);

        log = initLog + ", contract: " + "Dispenser";
        await checkDispenser(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "Dispenser", log);

        log = initLog + ", contract: " + "Depository";
        await checkDepository(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "Depository", log);
    }
    // ################################# /VERIFY CONTRACTS SETUP #################################
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });