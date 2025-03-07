/*global process*/

const { ethers } = require("ethers");

async function main() {
    // To run anvil fork with the timelock being the signer, use the following command:
    // anvil -f rpc_url --auto-impersonate --chain-id 1 --gas-price 20000000000 --gas-limit 1600000000

    let initBlockNumber;
    const URL = "http://127.0.0.1:8545";
    const provider = new ethers.providers.JsonRpcProvider(URL);
    await provider.getBlockNumber().then((result) => {
        initBlockNumber = result;
        console.log("Current fork block number: " + initBlockNumber);
    });

    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Get all the necessary contract addresses
    const timelockAddress = parsedData.timelockAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const dispenserAddress = parsedData.dispenserAddress;

    // Timelock address is specified via the "-u" command to ganache node
    const signer = provider.getSigner(timelockAddress);

    let privateKey = process.env.PRIVATE_KEY;
    let wallet = new ethers.Wallet(privateKey, provider);
    //wallet.sendTransaction({to: timelockAddress, value: ethers.utils.parseEther("1")});

    const tokenomicsJSON = "artifacts/contracts/Tokenomics.sol/Tokenomics.json";
    let contractFromJSON = fs.readFileSync(tokenomicsJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Tokenomics contract instance
    const tokenomics = new ethers.Contract(tokenomicsProxyAddress, abi, wallet);
    console.log("Tokenomics address", tokenomics.address);

    const dispenserJSON = "artifacts/contracts/Dispenser.sol/Dispenser.json";
    contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // Tokenomics contract instance
    const dispenser = new ethers.Contract(dispenserAddress, abi, wallet);
    console.log("Dispenser address", dispenser.address);

    const epochCounter = await tokenomics.epochCounter();

    // Retain through all the not retained epochs
    for (let i = 0; i < 8; i++) {
        await dispenser.retain();
    }

    const stakingPoint = await tokenomics.mapEpochStakingPoints(epochCounter);
    const retained = stakingPoint.stakingIncentive;

    console.log("Retained:", retained.toString());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
