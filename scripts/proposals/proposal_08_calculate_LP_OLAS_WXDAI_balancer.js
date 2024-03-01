/*global process*/

const { ethers } = require("hardhat");
const { BalancerSDK } =  require("@balancer-labs/sdk");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const gnosisURL = "https://rpc.gnosischain.com";
    const provider = new ethers.providers.JsonRpcProvider(gnosisURL);

    const balancer = new BalancerSDK({
        network: 100, // gnosis
        rpcUrl: gnosisURL,
    });

    // 50OLAS-50DAI pool Id
    const poolId = parsedData.OLAS_WXDAI_PoolId;

    // Swap contract tracking
    const vaultAddress = parsedData.vaultAddress;
    const vaultJSON = "abis/aux/Vault.json";
    const contractFromJSON = fs.readFileSync(vaultJSON, "utf8");
    const abi = JSON.parse(contractFromJSON);
    const vault = await ethers.getContractAt(abi, vaultAddress);

    // Get the SDK pool with service methods
    const pool = await balancer.pools.find(poolId);
    const tokenAddress = pool.address;
    const fee = pool.swapFee;

    // Proposal preparation
    console.log("Proposal 8. Calculate LP price for the bonding product on gnosis balancer");

    // Pool supply from the DAI-OLAS contract
    let totalSupplyRational = pool.totalShares;

    const reservesOLAS = pool.tokens[0].balance * 1.0;
    const reservesDAI = pool.tokens[1].balance * 1.0;

    // Current OLAS price
    const priceOLAS = pool.calcSpotPrice(pool.tokens[1].address, pool.tokens[0].address) * 1.0;
    console.log("Current OLAS price:", priceOLAS);
    console.log("OLAS reserves (rational)", reservesOLAS);
    console.log("Total supply (rational)", totalSupplyRational);

    // Get current LP price
    let priceLP = (reservesOLAS * 10**18 * 2) / totalSupplyRational;
    console.log("Initial priceLP", priceLP);

    // Estimate the average DAI amount of swaps the last number of days
    const numDays = 1;
    console.log("Last number of days to compute the average swap volume:", numDays);
    const numBlocksBack = Math.floor((3600 * 24 * numDays) / 5);

    // Get events
    let block = await provider.getBlock("latest");
    const curBlockNumber = block.number;

    const events = await provider.getLogs({
        fromBlock: curBlockNumber - numBlocksBack,
        toBlock: curBlockNumber,
        address: vault.address,
        topics: [ethers.utils.id("Swap(bytes32,address,address,uint256,uint256)"), poolId],
    });
    // Swap (index_topic_1 bytes32 poolId, index_topic_2 address tokenIn, index_topic_3 address tokenOut, uint256 amountIn, uint256 amountOut)

    // Parse events and get tradable OLAS and DAI
    let amountOLAS = ethers.BigNumber.from(0);
    let numEventsOLAS = 0;
    let amountDAI = ethers.BigNumber.from(0);
    let numEventsDAI = 0;
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

        // Get amounts in and out
        const amountIn = ethers.BigNumber.from("0x" + uint256DataArray[0]);
        const amountOut = ethers.BigNumber.from("0x" + uint256DataArray[1]);

        // Get tokens in and out
        const tokenIn = "0x" + events[i].topics[2].slice(26);
        const tokenOut = "0x" + events[i].topics[3].slice(26);

        // Of tokenIn is DAI, we add to its amount
        if (tokenIn == pool.tokens[1].address) {
            amountDAI = amountDAI.add(amountIn);
            numEventsDAI++;
        } else {
            amountOLAS = amountOLAS.add(amountIn);
            numEventsOLAS++;
        }
        //console.log(events[i]);
    }

    // To prevent a division by zero
    if (numEventsDAI == 0) {
        numEventsDAI = 1;
    }
    if (numEventsOLAS == 0) {
        numEventsOLAS = 1;
    }
    //console.log("amountOLAS", amountOLAS.toString());
    //console.log("amountDAI", amountDAI.toString());
    const e18 = ethers.BigNumber.from("1" + "0".repeat(18));
    const avgAmountOLAS = amountOLAS.div(ethers.BigNumber.from(numEventsOLAS));
    const avgAmountDAI = amountDAI.div(ethers.BigNumber.from(numEventsDAI));
    const avgAmountOLASNum = Number(amountOLAS.div(e18)) / numEventsOLAS;
    const avgAmountDAINum = Number(amountDAI.div(e18)) / numEventsDAI;
    console.log("Average OLAS amount per swap:", avgAmountOLASNum);
    console.log("Average DAI amount per swap:", avgAmountDAINum);

    // Record current reserves
    let newReservesDAI = reservesDAI;
    let newReservesOLAS = reservesOLAS;

    // Swap to get upper bound prices
    let priceCompare;
    let targetPrice = priceOLAS;
    let firstStep = 0.04;
    let firstStepUsed = false;
    let pcStep = 0.05;
    let numSteps = 20;
    const pricesOLASIncrease = new Array();
    const pricesLPIncrease = new Array();

    // We need to iteratively swap by adding average DAI into the pool each time such that the price of OLAS increases
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
            let spotPrice = newReservesOLAS / newReservesDAI;
            spotPrice = spotPrice / (1 - fee);
            const res = spotPrice * avgAmountDAINum;
            newReservesOLAS = newReservesOLAS - res;
            newReservesDAI = newReservesDAI + avgAmountDAINum;

            // This price must match the requested priceOLAS
            priceCompare = newReservesDAI / newReservesOLAS;
            if (priceCompare >= targetPrice) {
                break;
            }
        }

        priceLP = (newReservesOLAS * 10**18 * 2) / totalSupplyRational;
        pricesLPIncrease.push(priceLP);

        // Decrease the total price increase as we reached the new price, and break when we found all prices
        numSteps -= 1;
        if (numSteps == 0) {
            break;
        }
    }
    console.log("\n======= OLAS price increases =======");
    for (let i = 0; i < pricesOLASIncrease.length; i++) {
        console.log("OLAS price " + pricesOLASIncrease[i] + " (cents): priceLP " + pricesLPIncrease[i]);
    }

    // Set back current reserves
    newReservesDAI = reservesDAI;
    newReservesOLAS = reservesOLAS;

    // Swap to get lower bound prices
    targetPrice = priceOLAS;
    firstStep = pcStep - firstStep;
    firstStepUsed = false;
    numSteps = 10;
    const pricesOLASDecrease = new Array();
    const pricesLPDecrease = new Array();

    // We need to iteratively swap by adding average DAI into the pool each time such that the price of OLAS increases
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
            let spotPrice = newReservesDAI / newReservesOLAS;
            spotPrice = spotPrice / (1 - fee);
            const res = spotPrice * avgAmountOLASNum;
            newReservesDAI = newReservesDAI - res;
            newReservesOLAS = newReservesOLAS + avgAmountOLASNum;

            // This price must match the requested priceOLAS
            priceCompare = newReservesDAI / newReservesOLAS;
            if (priceCompare <= targetPrice) {
                break;
            }
        }

        priceLP = (newReservesOLAS * 10**18 * 2) / totalSupplyRational;
        pricesLPDecrease.push(priceLP);

        // Decrease the total price increase as we reached the new price, and break when we found all prices
        numSteps -= 1;
        if (numSteps == 0 || targetPrice <= pcStep) {
            break;
        }
    }
    console.log("\n======= OLAS price decreases =======");
    for (let i = 0; i < pricesOLASDecrease.length; i++) {
        console.log("OLAS price " + pricesOLASDecrease[i] + " (cents): priceLP " + pricesLPDecrease[i]);
    }
    console.log("\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
