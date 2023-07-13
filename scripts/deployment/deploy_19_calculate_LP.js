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
    let priceETH = data.ethereum.usd;
    console.log("ETH price in USD:", priceETH);
    let priceOLAS = 0.0742;
    // Number of OLAS
    const numOLAS = (numETH * priceETH) / priceOLAS;
    console.log("Number of OLAS:", numOLAS);

    // Supply is the half of the effective bond
    const supply = ethers.BigNumber.from(await tokenomics.effectiveBond()).div(ethers.BigNumber.from(2));
    // Vesting is 7 days
    const vesting = 3600 * 24 * 7;
    const token = parsedData.OLAS_ETH_PairAddress;
    // Current LP price
    let priceLP = ethers.BigNumber.from(await depository.getCurrentPriceLP(token));

    // Original pool supply from the ETH-OLAS contract
    const totalSupply = ethers.BigNumber.from("7973314868986424268666");
    // Price of ETH (in cents)
    priceETH = ethers.BigNumber.from(189000);
    // Desired price of OLAS (in cents)
    priceOLAS = ethers.BigNumber.from(10);
    // Initial reserves
    const reservesETH = ethers.BigNumber.from("50" + "0".repeat(18));
    const reservesOLAS = ethers.BigNumber.from("1271475" + "0".repeat(18));

    let newReservesETH = reservesETH;
    let newReservesOLAS = reservesOLAS;
    const addETH = ethers.BigNumber.from("1" + "0".repeat(18));
    let priceCompare;

    // We need to iteratively swap by adding 1 ETH into the pool each time such that the price of OLAS increases
    // to the desired value. 19 iterations for 0.16, 17 for 0.14, 13 for 0.12, 8 for 0.1, 2 for 0.08
    for (let i = 0; i < 2; i++) {
        const amountInWithFee = addETH.mul(ethers.BigNumber.from(997));
        const numerator = amountInWithFee.mul(reservesOLAS);
        const denominator = reservesETH.mul(ethers.BigNumber.from(1000)).add(amountInWithFee);
        const res = numerator.div(denominator);

        newReservesETH = newReservesETH.add(addETH);
        newReservesOLAS = newReservesOLAS.sub(res);

        // This price must match the requested priceOLAS
        priceCompare = (newReservesETH.mul(priceETH)).div(newReservesOLAS);
    }
    priceLP = (newReservesOLAS.mul(addETH)).div(totalSupply);
    //console.log("newReservesETH", newReservesETH);
    //console.log("newReservesOLAS", newReservesOLAS);
    //console.log("priceCompare", priceCompare);
    //console.log("priceLP", priceLP);

    // Price LP for OLAS price of 8, 10, 12, 14, 16 cents
    const pricesLP = ["153231111055529442295", "134525552082932313062", "118937586272434705368", "106467213624036619212", "100232027299837576135"];
    const supplies = ["1000000" + "0".repeat(18), "1000000" + "0".repeat(18), "300000" + "0".repeat(18), "300000" + "0".repeat(18), "300000" + "0".repeat(18)];

    // Final price LP
    const finalPricesLP = new Array(5);
    for (let i = 0; i < 5; i++) {
        priceLP = ethers.BigNumber.from(pricesLP[i]);
        finalPricesLP[i] = priceLP.add(priceLP.div(ethers.BigNumber.from(2)));
        //console.log("finalPricesLP:", finalPricesLP[i]);
    }

    //console.log("supply", supply);
    //console.log("pricesLP", pricesLP);

    const targets = new Array(5).fill(depositoryAddress);
    const values = new Array(5).fill(0);
    const callDatas = new Array(5);
    for (let i = 0; i < 5; i++) {
        callDatas[i] = depository.interface.encodeFunctionData("create", [token, finalPricesLP[i], supplies[i], vesting]);
    }
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
