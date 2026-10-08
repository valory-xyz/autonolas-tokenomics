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

    // Supported on Sepolia only. On mainnet, use the .sh counterpart of this script: it binds the processor's
    // immutable l1Dispenser to the DispenserProxy, whereas this globals' dispenserAddress keeps the pre-proxy
    // Dispenser. The check uses the network the transaction is sent to (the Ledger's provider, or Hardhat's network
    // otherwise), and the globals must describe that same chain.
    const supportedChainIds = [11155111];
    const connectedChainId = (await (useLedger ? provider : ethers.provider).getNetwork()).chainId;
    if (!supportedChainIds.includes(connectedChainId) || Number(parsedData.chainId) !== connectedChainId) {
        throw new Error("Supported on Sepolia only (connected to chain " + connectedChainId + ", globals chainId "
            + parsedData.chainId + "); on mainnet use " + require("path").basename(__filename, ".js") + ".sh");
    }
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("2. EOA to deploy ArbitrumDepositProcessorL1");
    const ArbitrumDepositProcessorL1 = await ethers.getContractFactory("ArbitrumDepositProcessorL1");
    console.log("You are signing the following transaction: ArbitrumDepositProcessorL1.connect(EOA).deploy()");
    const arbitrumDepositProcessorL1 = await ArbitrumDepositProcessorL1.connect(EOA).deploy(parsedData.olasAddress,
        parsedData.dispenserAddress, parsedData.arbitrumL1ERC20GatewayRouterAddress,
        parsedData.arbitrumInboxAddress, parsedData.arbitrumL2TargetChainId, parsedData.arbitrumL1ERC20GatewayAddress,
        parsedData.arbitrumOutboxAddress, parsedData.arbitrumBridgeAddress);
    const result = await arbitrumDepositProcessorL1.deployed();

    // Transaction details
    console.log("Contract deployment: ArbitrumDepositProcessorL1");
    console.log("Contract address:", arbitrumDepositProcessorL1.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.arbitrumDepositProcessorL1Address = arbitrumDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/staking//verify_02_arbitrum_deposit_processor.js --network " + providerName + " " + arbitrumDepositProcessorL1.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
