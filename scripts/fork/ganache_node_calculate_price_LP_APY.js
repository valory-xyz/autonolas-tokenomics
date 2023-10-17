/*global process*/

const { ethers } = require("ethers");

async function main() {
    // To run ganache fork with the timelock being the signer, use the following command:
    // ganache-cli --fork node_URL --chain.chainId=100000 --gasPrice 20000000000 --gasLimit 1600000000 --deterministic --database.dbPath ganache_data -u 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE

    const URL = "http://127.0.0.1:8545";
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
    const depositoryAddress = parsedData.depositoryTwoAddress;
    const tokenAddress = parsedData.OLAS_ETH_PairAddress;
    const olasAddress = parsedData.olasAddress;
    const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    // Timelock address is specified via the "-u" command to ganache node
    const signer = provider.getSigner(timelockAddress);

    let privateKey = process.env.PRIVATE_KEY;
    let wallet = new ethers.Wallet(privateKey, provider);
    //wallet.sendTransaction({to: timelockAddress, value: ethers.utils.parseEther("1")});

    const treasuryJSON = "artifacts/contracts/Treasury.sol/Treasury.json";
    let contractFromJSON = fs.readFileSync(treasuryJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Treasury contract instance
    const treasury = new ethers.Contract(treasuryAddress, abi, signer);
    //console.log(treasury.address);

    // Enable tokenAddress
    //await treasury.connect(signer).enableToken(tokenAddress);
    //console.log(await treasury.isEnabled(tokenAddress));

    const depositoryJSON = "artifacts/contracts/Depository.sol/Depository.json";
    contractFromJSON = fs.readFileSync(depositoryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // Depository contract instance
    const depository = new ethers.Contract(depositoryAddress, abi, signer);
    //console.log(depository.address);

    // Create a bonding product
    const vesting = 3600 * 24 * 7;
    //await depository.connect(signer).create(tokenAddress, "229846666583294163442", "1" + "0".repeat(24), vesting);
    console.log(await depository.isActiveProduct(0));

    // Get the LP contract
    const pairJSON = "artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json";
    contractFromJSON = fs.readFileSync(pairJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const pair = new ethers.Contract(tokenAddress, abi, signer);

    const res = await pair.getReserves();
    const resOLAS = ethers.BigNumber.from(res._reserve0);
    const totalSupply = ethers.BigNumber.from(await pair.totalSupply());

    // Get the product with a specific Id
    const product = await depository.mapBondProducts(0);
    const priceLP = ethers.BigNumber.from(product.priceLP);

    // Get this from the tokenomics contract
    const IDF = ethers.BigNumber.from("1020000000000000000");
    const e36 = ethers.BigNumber.from("1" + "0".repeat(36));
    const profitNumerator = (priceLP.mul(totalSupply).mul(IDF).mul(ethers.BigNumber.from(2))).div(e36);
    const profitDenominator = ethers.BigNumber.from(3).mul(resOLAS);
    console.log("profitDenominator", profitDenominator.toString());

    const profit = Number(profitNumerator) * 1.0 / Number(profitDenominator) - 1;
    console.log("profit", profit);

    const oneYear = 3600 * 24 * 365;
    const n = oneYear / vesting;
    console.log(n);
    //const APY = Math.pow(profit, n) - 1;
    const APY = (1 + profit / n) ** n - 1;
    const roundAPY = Math.round(APY * 100, 2);
    console.log(roundAPY);

    //const pricesLP = ["153231111055529442295", "134525552082932313062", "118937586272434705368", "106467213624036619212", "100232027299837576135"];
    //const finalPricesLP = new Array(5);
    //for (let i = 0; i < 5; i++) {
    //    const priceLP = ethers.BigNumber.from(pricesLP[i]);
    //    finalPricesLP[i] = priceLP.add(priceLP.div(ethers.BigNumber.from(2)));
    //    console.log("finalPricesLP:", finalPricesLP[i].toString());
    //}
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
