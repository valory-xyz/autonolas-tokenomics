/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const gasPriceInGwei = parsedData.gasPriceInGwei;
    // NOTE: pass the LiquidityManager *proxy* here, not the impl.
    const liquidityManagerAddress = parsedData.liquidityManagerProxyAddress;
    const bridge2BurnerAddress = parsedData.bridge2BurnerAddress || parsedData.burnerAddress;
    const treasuryAddress = parsedData.bridgeMediatorAddress || parsedData.timelockAddress;
    const swapRouterV3Address = parsedData.swapRouterV3Address;

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
    console.log("2. EOA to deploy BuyBackBurnerUniswap");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const BuyBackBurnerUniswap = await ethers.getContractFactory("BuyBackBurnerUniswap");
    console.log("You are signing the following transaction: BuyBackBurnerUniswap.connect(EOA).deploy(liquidityManager, bridge2Burner, treasury, swapRouter)");
    const buyBackBurner = await BuyBackBurnerUniswap.connect(EOA).deploy(
        liquidityManagerAddress, bridge2BurnerAddress, treasuryAddress, swapRouterV3Address,
        { gasPrice }
    );
    const result = await buyBackBurner.deployed();

    // Transaction details
    console.log("Contract deployment: BuyBackBurnerUniswap");
    console.log("Contract address:", buyBackBurner.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.buyBackBurnerAddress = buyBackBurner.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + buyBackBurner.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
