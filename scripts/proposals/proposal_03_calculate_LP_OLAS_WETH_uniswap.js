/*global process*/

const { ethers } = require("hardhat");
const { fetch } = require("cross-fetch");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;
    const provider = await ethers.providers.getDefaultProvider(providerName);

    // Get all the necessary contract addresses
    const depositoryTwoAddress = parsedData.depositoryTwoAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const tokenAddress = parsedData.OLAS_ETH_PairAddress;

    // Get the depository instance
    const depository = await ethers.getContractAt("Depository", depositoryTwoAddress);
    const tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    const pair = await ethers.getContractAt("UniswapV2Pair", tokenAddress);

    // Proposal preparation
    console.log("Proposal 3. Calculate LP price for the bonding product");

    // Fetch the ETH price
    const response = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd");
    const data = await response.json();
    let priceETH = data.ethereum.usd;
    console.log("Current ETH price:", priceETH);

    // Pool supply from the ETH-OLAS contract
    let totalSupply = await pair.totalSupply();
    const reserves = await pair.getReserves();
    let reservesOLAS = reserves._reserve0;
    let reservesETH = reserves._reserve1;
    const e18 = ethers.BigNumber.from("1" + "0".repeat(18));

    // Get the OLAS current price
    const olasPerETH = reservesOLAS.div(reservesETH);
    let priceOLAS = priceETH / Number(olasPerETH);
    console.log("Current OLAS price:", priceOLAS);

    // Convert prices in cents
    priceETH = ethers.BigNumber.from(Math.floor(priceETH * 100));
    priceOLAS = ethers.BigNumber.from(Math.floor(priceOLAS * 100));

    // Get current LP price
    let priceLP = ethers.BigNumber.from(await depository.getCurrentPriceLP(tokenAddress)).mul(2);
    console.log("Initial priceLP", priceLP.toString());

    // Estimate the average ETH amount of swaps the last number of days
    const numDays = 7;
    console.log("Last number of days to compute the average swap volume:", numDays);
    const numBlocksBack = Math.floor((3600 * 24 * numDays) / 12);

    // Get events
    const eventName = "Swap";
    const eventFilter = pair.filters[eventName]();
    let block = await provider.getBlock("latest");
    const curBlockNumber = block.number;

    const events = await provider.getLogs({
        fromBlock: curBlockNumber - numBlocksBack,
        toBlock: curBlockNumber,
        address: pair.address,
        topics: eventFilter.topics,
    });

    // Parse events and get tradable OLAS and ETH
    let amountOLAS = ethers.BigNumber.from(0);
    let numEventsOLAS = 0;
    let amountETH = ethers.BigNumber.from(0);
    let numEventsETH = 0;
    for (let i = 0; i < events.length; i++) {
        const uint256SizeInBytes = 32;
        const uint256Count = 4;
        const uint256DataArray = [];

        const data = events[i].data.slice(2);
        for (let i = 0; i < uint256Count; i++) {
            const startIndex = i * uint256SizeInBytes * 2; // 2 hex characters per byte
            const endIndex = startIndex + uint256SizeInBytes * 2;
            const uint256Data = data.substring(startIndex, endIndex);
            uint256DataArray.push(uint256Data);
        }
        const amount0In = ethers.BigNumber.from("0x" + uint256DataArray[0]);
        const amount1In = ethers.BigNumber.from("0x" + uint256DataArray[1]);
        const amount0Out = ethers.BigNumber.from("0x" + uint256DataArray[2]);
        const amount1Out = ethers.BigNumber.from("0x" + uint256DataArray[3]);

        if (amount0In.eq(0)) {
            amountETH = amountETH.add(amount1In);
            numEventsETH++;
        } else {
            amountOLAS = amountOLAS.add(amount0In);
            numEventsOLAS++;
        }
    }
    if (numEventsETH == 0) {
        numEventsETH = 1;
    }
    if (numEventsOLAS == 0) {
        numEventsOLAS = 1;
    }
    //console.log("amountOLAS", amountOLAS.toString());
    //console.log("amountETH", amountETH.toString());
    const avgAmountOLAS = amountOLAS.div(ethers.BigNumber.from(numEventsOLAS));
    const avgAmountETH = amountETH.div(ethers.BigNumber.from(numEventsETH));
    const avgAmountOLASNum = Number(amountOLAS.div(e18)) / numEventsOLAS;
    const e5 = ethers.BigNumber.from("1" + "0".repeat(5));
    // Since OLAS is approx 5 digits of ETH, make 5 digits more precision for ETH
    const avgAmountETHNum = Number(amountETH.mul(e5).div(e18)) / (Number(e5) * numEventsETH);
    console.log("Average OLAS amount per swap:", avgAmountOLASNum);
    console.log("Average ETH amount per swap:", avgAmountETHNum);
    // Convert OLAS to ETH
    const numEvents = ethers.BigNumber.from(events.length);
    const allAmountETH = amountETH.add(amountOLAS.div(olasPerETH));
    const allAvgAmountETH = allAmountETH.div(numEvents);
    //console.log("Overall amountETH", Number(allAmountETH) / Number(e18));

    // Record current reserves
    let newReservesETH = reservesETH;
    let newReservesOLAS = reservesOLAS;

    // Swap to get upper bound prices
    let priceCompare;
    let targetPrice = Number(priceOLAS);
    let firstStep = 4;
    let firstStepUsed = false;
    let pcStep = 5;
    let numSteps = 20;
    const pricesOLASIncrease = new Array();
    const pricesLPIncrease = new Array();

    // We need to iteratively swap by adding average ETH into the pool each time such that the price of OLAS increases
    // to the desired value.
    const condition = true;
    while (condition) {
        if (!firstStepUsed) {
            targetPrice += firstStep;
            firstStepUsed = true;
        } else {
            targetPrice += pcStep;
        }
        pricesOLASIncrease.push(targetPrice);
        while (condition) {
            //console.log("targetPrice", targetPrice);
            const amountInWithFee = avgAmountETH.mul(ethers.BigNumber.from(997));
            const numerator = amountInWithFee.mul(newReservesOLAS);
            const denominator = newReservesETH.mul(ethers.BigNumber.from(1000)).add(amountInWithFee);
            const res = numerator.div(denominator);

            newReservesETH = newReservesETH.add(avgAmountETH);
            newReservesOLAS = newReservesOLAS.sub(res);

            // This price must match the requested priceOLAS
            priceCompare = Number((newReservesETH.mul(priceETH)).div(newReservesOLAS));
            if (priceCompare >= targetPrice) {
                break;
            }
        }
        priceLP = (newReservesOLAS.mul(e18)).div(totalSupply).mul(ethers.BigNumber.from(2));
        pricesLPIncrease.push(priceLP);

        // Decrease the total price increase as we reached the new price, and break when we found all prices
        numSteps -= 1;
        if (numSteps == 0) {
            break;
        }
    }
    console.log("\n======= OLAS price increases =======");
    for (let i = 0; i < pricesOLASIncrease.length; i++) {
        console.log("OLAS price " + pricesOLASIncrease[i] + " (cents): priceLP " + pricesLPIncrease[i].toString());
    }

    // Set back current reserves
    newReservesETH = reservesETH;
    newReservesOLAS = reservesOLAS;

    // Swap to get lower bound prices
    targetPrice = Number(priceOLAS);
    firstStep = pcStep - firstStep;
    firstStepUsed = false;
    numSteps = 10;
    const pricesOLASDecrease = new Array();
    const pricesLPDecrease = new Array();

    // We need to iteratively swap by adding average ETH into the pool each time such that the price of OLAS increases
    // to the desired value.
    while (condition) {
        if (!firstStepUsed) {
            targetPrice -= firstStep;
            firstStepUsed = true;
        } else {
            targetPrice -= pcStep;
        }
        pricesOLASDecrease.push(targetPrice);
        while (condition) {
            //console.log("targetPrice", targetPrice);
            const amountInWithFee = avgAmountOLAS.mul(ethers.BigNumber.from(997));
            const numerator = amountInWithFee.mul(newReservesOLAS);
            const denominator = newReservesOLAS.mul(ethers.BigNumber.from(1000)).add(amountInWithFee);
            const res = numerator.div(denominator);

            newReservesOLAS = newReservesOLAS.add(avgAmountOLAS);
            newReservesETH = newReservesETH.sub(res);

            // This price must match the requested priceOLAS
            priceCompare = Number((newReservesETH.mul(priceETH)).div(newReservesOLAS));
            if (priceCompare <= targetPrice) {
                break;
            }
        }
        priceLP = (newReservesOLAS.mul(e18)).div(totalSupply).mul(ethers.BigNumber.from(2));
        pricesLPDecrease.push(priceLP);

        // Decrease the total price increase as we reached the new price, and break when we found all prices
        numSteps -= 1;
        if (numSteps == 0 || targetPrice <= pcStep) {
            break;
        }
    }
    console.log("\n======= OLAS price decreases =======");
    for (let i = 0; i < pricesOLASDecrease.length; i++) {
        console.log("OLAS price " + pricesOLASDecrease[i] + " (cents): priceLP " + pricesLPDecrease[i].toString());
    }
    console.log("\n");

    // Get effective bond
    const effectiveBond = ethers.BigNumber.from(await tokenomics.effectiveBond());
    // One day time
    const oneDay = 3600 * 24;

    // Price LP for OLAS price of corresponding prices
    const pricesLP = [pricesOLASIncrease[0]];
    const supplies = ["100000" + "0".repeat(18)];
    const vestings = [28 * oneDay];

    const numPrices = pricesLP.length;
    const targets = new Array(numPrices).fill(depositoryTwoAddress);
    const values = new Array(numPrices).fill(0);
    const callDatas = new Array(numPrices);
    for (let i = 0; i < numPrices; i++) {
        callDatas[i] = depository.interface.encodeFunctionData("create", [tokenAddress, pricesLP[i], supplies[i], vestings[i]]);
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
