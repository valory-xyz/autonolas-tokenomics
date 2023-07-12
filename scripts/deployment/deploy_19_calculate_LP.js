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
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const depositoryAddress = parsedData.depositoryAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    // Get the depository instance
    const depository = await ethers.getContractAt("Depository", depositoryAddress);
    const tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);

    // Proposal preparation
    console.log("19. Calculate LP price for the bonding product");

    const numETH = 50;
    const response = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd");
    const data = await response.json();
    const priceETH = data.ethereum.usd;
    console.log("ETH price in USD:", priceETH);
    const priceOLAS = 0.05;
    // Number of OLAS
    const numOLAS = (numETH * priceETH) / priceOLAS;
    console.log("Number of OLAS:", numOLAS);

    // Supply is the half of the effective bond
    const supply = ethers.BigNumber.from(await tokenomics.effectiveBond()).div(ethers.BigNumber.from(2));
    // Vesting is 30 days
    const vesting = 3600 * 24 * 30;
    const token = parsedData.OLAS_ETH_PairAddress;
    let priceLP = ethers.BigNumber.from("1000");//ethers.BigNumber.from(await depository.getCurrentPriceLP(token));

    // Final price LP
    priceLP = priceLP.add(priceLP.div(ethers.BigNumber.from(2)));

    console.log("supply", supply);
    console.log("priceLP", priceLP);

    const targets = [depositoryAddress];
    const values = [0];
    const callDatas = [depository.interface.encodeFunctionData("create", [token, priceLP, supply, vesting])];
    const description = "Create OLAS-ETH bonding product";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
