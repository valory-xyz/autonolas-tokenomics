/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");

async function main() {
    const URL = "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET;
    const provider = new ethers.providers.JsonRpcProvider(URL);
    await provider.getBlockNumber().then((result) => {
        console.log("Current fork block number: " + result);
    });

    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Get all the necessary contract addresses
    const depositoryAddress = parsedData.depositoryAddress;
    const tokenAddress = parsedData.OLAS_ETH_PairAddress;

    // EOA address
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOA = new ethers.Wallet(account, provider);
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    const depositoryJSON = "artifacts/contracts/Depository.sol/Depository.json";
    const contractFromJSON = fs.readFileSync(depositoryJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const abi = parsedFile["abi"];

    // Depository contract instance
    const depository = new ethers.Contract(depositoryAddress, abi, provider);

    // Get all events
    const eventName = "CreateBond";
    const eventFilter = depository.filters[eventName]();

    const events = await provider.getLogs({
        fromBlock: 17733103,
        toBlock: "latest",
        address: depository.address,
        topics: eventFilter.topics,
    });

    const IDF = ethers.BigNumber.from("1020000000000000000");
    const e18 = ethers.BigNumber.from("1" + "0".repeat(18));
    const e36 = ethers.BigNumber.from("1" + "0".repeat(36));
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

        const bondId = parseInt(uint256DataArray[0], 16);
        const amountOLAS = ethers.BigNumber.from("0x" + uint256DataArray[1]);
        const tokenAmount = ethers.BigNumber.from("0x" + uint256DataArray[2]);
        const expiry = parseInt(uint256DataArray[3], 16);

        const productId = parseInt(events[i].topics[2], 16);
        const product = await depository.mapBondProducts(productId);
        const priceLP = ethers.BigNumber.from(product.priceLP);


        let curPriceLP = await depository.getCurrentPriceLP(tokenAddress, { blockTag: events[i].blockNumber });
        curPriceLP = curPriceLP.mul(ethers.BigNumber.from(2));

        const expectedPayout = (priceLP.mul(tokenAmount).mul(IDF)).div(e36);
        expect(expectedPayout.toString()).to.equal(amountOLAS.toString());

        console.log("productId:", productId);
        console.log("bondId:", bondId);
        console.log("amountOLAS:", amountOLAS.toString());
        if(curPriceLP.lt(priceLP)) {
            console.log("+++++++Profitable: current price " + curPriceLP.toString() + " < price offered by product " + priceLP.toString());
        }
        else {
            console.log("-------Not Profitable: current price" + curPriceLP.toString() + " > price offered by product " + priceLP.toString());
        }
        console.log("Expected and actual OLAS amount match\n\n");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
