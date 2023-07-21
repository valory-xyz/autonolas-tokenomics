/*global process*/

const { ethers } = require("ethers");

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
    const timelockAddress = parsedData.timelockAddress;
    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
    const tokenAddress = parsedData.OLAS_ETH_PairAddress;
    const olasAddress = parsedData.olasAddress;
    const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    // EOA address
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOA = new ethers.Wallet(account, provider);
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    const treasuryJSON = "artifacts/contracts/Treasury.sol/Treasury.json";
    let contractFromJSON = fs.readFileSync(treasuryJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Treasury contract instance
    const treasury = new ethers.Contract(treasuryAddress, abi, provider);
    //console.log(treasury.address);

    const depositoryJSON = "artifacts/contracts/Depository.sol/Depository.json";
    contractFromJSON = fs.readFileSync(depositoryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // Depository contract instance
    const depository = new ethers.Contract(depositoryAddress, abi, provider);
    //console.log(depository.address);

    // Create a bonding product
    const vesting = 3600 * 24 * 7;
    //console.log(await depository.isActiveProduct(0));

    // Get the LP contract
    const pairJSON = "artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json";
    contractFromJSON = fs.readFileSync(pairJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const pair = new ethers.Contract(tokenAddress, abi, provider);

    const res = await pair.getReserves();
    const resOLAS = ethers.BigNumber.from(res._reserve0);
    const totalSupply = ethers.BigNumber.from(await pair.totalSupply());

    // Get the product with a specific Id
    const productId = 0;
    const product = await depository.mapBondProducts(productId);
    let priceLP = ethers.BigNumber.from(product.priceLP);

    // Get the current priceLP
    let curPriceLP = await depository.getCurrentPriceLP(tokenAddress);

    // IDF. Need to take from the tokenomics contract
    const IDF = ethers.BigNumber.from("1020000000000000000");
    const e18 = ethers.BigNumber.from("1" + "0".repeat(18));
    priceLP = Number((priceLP.mul(IDF)).div(e18).div(e18));
    curPriceLP = 2 * Number(curPriceLP.div(e18));
    console.log("Rounded product priceLP:", priceLP);
    console.log("Rounded current priceLP:", curPriceLP);

    const profit = priceLP / curPriceLP - 1;
    console.log("Profit:", profit);

    const oneYear = 3600 * 24 * 365;
    const n = oneYear / vesting;
    const APY = (1 + profit / n) ** n - 1;
    const roundAPY = Math.round(APY * 100, 2);
    console.log("Rounded APY:", roundAPY);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
