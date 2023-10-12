/*global process*/

const { ethers } = require("hardhat");
const { fetch } = require("cross-fetch");
const { BalancerSDK } =  require('@balancer-labs/sdk');

const balancer = new BalancerSDK({
    network: 100, // gnosis
    rpcUrl: 'https://rpc.gnosischain.com',
});


async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;
    const provider = await ethers.providers.getDefaultProvider(providerName);

    // 50OLAS-50WXDAI pool Id
    const poolId ="0x79c872ed3acb3fc5770dd8a0cd9cd5db3b3ac985000200000000000000000067";

    // Swap contract tracking
    const vaultAddress = "0xba12222222228d8ba445958a75a0704d566bf2c8";
    const vaultJSON = "abis/aux/Vault.json";
    const contractFromJSON = fs.readFileSync(vaultJSON, "utf8");
    const abi = JSON.parse(contractFromJSON);
    const vault = await ethers.getContractAt(abi, vaultAddress);

    // Get the SDK pool with service methods
    const pool = await balancer.pools.find(poolId);
    const tokenAddress = pool.address;
    const pair = await ethers.getContractAt("UniswapV2Pair", tokenAddress);

    const fee = pool.swapFee;
    let x = pool.tokens[1].balance / pool.tokens[0].balance;
    // address: '0xce11e14225575945b8e6dc0d4f2dd4c570f79d9f' token[0] OLAS
    // address: '0xe91d153e0b41518a2ce8dd3d7944fa863463a97d' token[1] WXDAI
    x = x / (1 - fee);
    // console.log(pool);
    //console.log(x);
    //console.log(pool.calcSpotPrice(pool.tokens[1].address, pool.tokens[0].address));

    // Proposal preparation
    console.log("Proposal 8. Calculate LP price for the bonding product on gnosis balancer");

    // Pool supply from the ETH-OLAS contract
    let totalSupply = await pair.totalSupply();
    let totalSupplyRational = pool.totalShares;

    let reservesXOLAS = pool.tokens[0].balance;
    let reservesWXDAI = pool.tokens[1].balance;
    //const e18 = ethers.BigNumber.from("1" + "0".repeat(18));

    // Current XOLAS price
    const priceXOLAS = pool.calcSpotPrice(pool.tokens[1].address, pool.tokens[0].address);
    console.log("Current OLAS price:", priceXOLAS);
    console.log("XOLAS reserves (rational)", reservesXOLAS);
    console.log("Total supply (rational)", totalSupplyRational);

    // Get current LP price
    let priceLP = (reservesXOLAS * 10**18 * 2) / totalSupplyRational;
    console.log("Initial priceLP", priceLP);

    // Estimate the average ETH amount of swaps the last number of days
    const numDays = 1;
    console.log("Last number of days to compute the average swap volume:", numDays);
    const numBlocksBack = 100;//Math.floor((3600 * 24 * numDays) / 12);

    // Get events
    const eventName = "Swap";
    const eventFilter = vault.filters[eventName]();
    let block = await provider.getBlock("latest");
    const curBlockNumber = block.number;

    const events = await provider.getLogs({
        fromBlock: 30418493,//curBlockNumber - numBlocksBack,
        toBlock: 30418495,//curBlockNumber,
        address: vault.address,
        topics: eventFilter.topics,
    });

    // Parse events and get tradable OLAS and ETH
    let amountOLAS = ethers.BigNumber.from(0);
    let numEventsOLAS = 0;
    let amountETH = ethers.BigNumber.from(0);
    let numEventsETH = 0;
    for (let i = 0; i < events.length; i++) {
        const uint256SizeInBytes = 32;
        const uint256Count = 2;
        const uint256DataArray = [];

        const data = events[i].data.slice(2);
        for (let i = 0; i < uint256Count; i++) {
            const startIndex = i * uint256SizeInBytes * 2; // 2 hex characters per byte
            const endIndex = startIndex + uint256SizeInBytes * 2;
            const uint256Data = data.substring(startIndex, endIndex);
            uint256DataArray.push(uint256Data);
        }
        const amountIn = ethers.BigNumber.from("0x" + uint256DataArray[0]);
        const amountOut = ethers.BigNumber.from("0x" + uint256DataArray[1]);
    // Swap (index_topic_1 bytes32 poolId, index_topic_2 address tokenIn, index_topic_3 address tokenOut, uint256 amountIn, uint256 amountOut)

//        if (amountIn.eq(0)) {
//            amountETH = amountETH.add(amount1In);
//            numEventsETH++;
//        } else {
//            amountOLAS = amountOLAS.add(amountIn);
//            numEventsOLAS++;
//        }
        console.log(events[i]);
        console.log(events[i].topics[1]);
        //break;
    }

    return;

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
    let newReservesOLAS = reservesXOLAS;

    // Swap to get upper bound prices
    let priceCompare;
    let targetPrice = Number(priceXOLAS);
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
            const numerator = amountInWithFee.mul(reservesXOLAS);
            const denominator = reservesETH.mul(ethers.BigNumber.from(1000)).add(amountInWithFee);
            const res = numerator.div(denominator);

            newReservesETH = newReservesETH.add(avgAmountETH);
            newReservesOLAS = newReservesOLAS.sub(res);

            // This price must match the requested priceXOLAS
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
    newReservesOLAS = reservesXOLAS;

    // Swap to get lower bound prices
    targetPrice = Number(priceXOLAS);
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
            const numerator = amountInWithFee.mul(reservesETH);
            const denominator = reservesXOLAS.mul(ethers.BigNumber.from(1000)).add(amountInWithFee);
            const res = numerator.div(denominator);

            newReservesOLAS = newReservesOLAS.add(avgAmountOLAS);
            newReservesETH = newReservesETH.sub(res);

            // This price must match the requested priceXOLAS
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
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
