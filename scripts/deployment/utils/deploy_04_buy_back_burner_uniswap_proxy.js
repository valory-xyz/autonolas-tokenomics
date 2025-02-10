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
    const buyBackBurnerAddress = parsedData.buyBackBurnerAddress;
    const nativeTokenAddress = parsedData.nativeTokenAddress;

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

    // Assemble the contributors proxy data
    const buyBackBurner = await ethers.getContractAt("BuyBackBurnerUniswap", buyBackBurnerAddress);
    const proxyPayload = ethers.utils.defaultAbiCoder.encode(["address[]", "uint256"],
         [[parsedData.olasAddress, nativeTokenAddress, parsedData.uniswapPriceOracleAddress,
         parsedData.routerV2Address], parsedData.maxBuyBackSlippage]);
    const proxyData = buyBackBurner.interface.encodeFunctionData("initialize", [proxyPayload]);

    // Transaction signing and execution
    console.log("4. EOA to deploy BuyBackBurnerProxy based on BuyBackBurnerUniswap");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const BuyBackBurnerProxy = await ethers.getContractFactory("BuyBackBurnerProxy");
    console.log("You are signing the following transaction: BuyBackBurnerProxy.connect(EOA).deploy()");
    const buyBackBurnerProxy = await BuyBackBurnerProxy.connect(EOA).deploy(buyBackBurnerAddress, proxyData, { gasPrice });
    const result = await buyBackBurnerProxy.deployed();

    // Transaction details
    console.log("Contract deployment: buyBackBurnerProxy");
    console.log("Contract address:", buyBackBurnerProxy.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.buyBackBurnerProxyAddress = buyBackBurnerProxy.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/utils/verify_04_buy_back_burner_uniswap_proxy.js --network " + providerName + " " + buyBackBurnerProxy.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
