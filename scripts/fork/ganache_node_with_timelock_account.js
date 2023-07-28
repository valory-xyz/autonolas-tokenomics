/*global process*/

const { ethers } = require("ethers");

async function main() {
    // To run ganache fork with the timelock being the signer, use the following command:
    // ganache-cli --fork node_URL --chain.chainId=100000 --gasPrice 20000000000 --gasLimit 1600000000 --deterministic --database.dbPath ganache_data -u 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE

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
    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
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

    // Change to this contract ABI when the new depository contract is set by tokenomics and treasury
    //const depositoryJSON = "artifacts/contracts/Depository.sol/Depository.json";
    const depositoryJSON = "abis/0.8.18/Depository.json";
    contractFromJSON = fs.readFileSync(depositoryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // Depository contract instance
    const depository = new ethers.Contract(depositoryAddress, abi, signer);
    //console.log(depository.address);

    // Create 5 bonding products
    const vesting = 3600 * 24 * 7;
    //await depository.connect(signer).create(tokenAddress, "229846666583294163442", "1" + "0".repeat(24), vesting);
    //await depository.connect(signer).create(tokenAddress, "201788328124398469593", "1" + "0".repeat(24), vesting);
    //await depository.connect(signer).create(tokenAddress, "178406379408652058052", "3" + "0".repeat(23), vesting);
    //await depository.connect(signer).create(tokenAddress, "159700820436054928818", "3" + "0".repeat(23), vesting);
    //await depository.connect(signer).create(tokenAddress, "150348040949756364202", "3" + "0".repeat(23), vesting);
    //console.log(await depository.isActiveProduct(0));

    const eventName = "CreateProduct";
    const eventFilter = depository.filters[eventName]();
    const curBlock = await provider.getBlock("latest");
    const curBlockNumber = curBlock.number;
    const filter = new Array;
    const productId = 0;
    filter.push(eventFilter.topics[0]);
    filter.push("0x" + "0".repeat(24) + tokenAddress.slice(2));
    filter.push(ethers.utils.hexZeroPad(ethers.utils.hexlify(productId), 32));

    const logs = await provider.getLogs({
        fromBlock: curBlockNumber - 10,
        toBlock: curBlockNumber,
        address: depository.address,
        topics: filter,
    });

    //const blockNumber = logs[0].blockNumber;
    //const block = await provider.getBlock(blockNumber);
    //const timestamp = block.timestamp;
    //console.log(timestamp);

    // Get the Uniswap Router contract
    const uniswapRouterAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const uniswapRouterJSON = "artifacts/@uniswap/v2-periphery/contracts/UniswapV2Router02.sol/UniswapV2Router02.json";
    contractFromJSON = fs.readFileSync(uniswapRouterJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const router = new ethers.Contract(uniswapRouterAddress, abi, signer);

    // Get OLAS tokens
    // to is the Metamask address
    const to = wallet.address;
    const deadline = Math.floor(Date.now() / 1e3 + vesting);
    console.log(deadline);
    // WETH-OLAS array
    const path = [wethAddress, olasAddress];
    // Swap ETH for OLAS tokens
    await router.connect(wallet).swapExactETHForTokens(0, path, to, deadline, {value: ethers.utils.parseEther("1")});

    // Get the OLAS contract
    const olasJSON = "abis/test/OLAS.json";
    contractFromJSON = fs.readFileSync(olasJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const olas = new ethers.Contract(olasAddress, abi, signer);
    console.log("OLAS balance:", Number(await olas.balanceOf(to)));

    // Get the WETH contract
    const wethJSON = "artifacts/canonical-weth/contracts/WETH9.sol/WETH9.json";
    contractFromJSON = fs.readFileSync(wethJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const weth = new ethers.Contract(wethAddress, abi, signer);

    // Get WETH for ETH
    await weth.connect(wallet).deposit({value: ethers.utils.parseEther("1")});
    console.log("WETH balance:", Number(await weth.balanceOf(wallet.address)));

    // Approve tokens for router
    await olas.connect(wallet).approve(uniswapRouterAddress, ethers.constants.MaxUint256);
    await weth.connect(wallet).approve(uniswapRouterAddress, ethers.constants.MaxUint256);
    
    // Get the LP contract
    const pairJSON = "artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json";
    contractFromJSON = fs.readFileSync(pairJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const pair = new ethers.Contract(tokenAddress, abi, signer);
    await pair.connect(wallet).approve(uniswapRouterAddress, ethers.constants.MaxUint256);
    const e18 = ethers.BigNumber.from("1" + "0".repeat(18));
    let reserves = await pair.getReserves();
    let reservesOLAS = reserves._reserve0;
    let reservesETH = reserves._reserve1;
    let totalSupply = await pair.totalSupply();
    let priceLPBefore = (reservesOLAS.mul(e18)).div(totalSupply);
    console.log("priceLP",priceLPBefore);
    // Get WETH-OLAS liquidity
    await router.connect(wallet).addLiquidity(wethAddress, olasAddress, ethers.utils.parseEther("0.5"), ethers.utils.parseEther("10000"), 0, 0, to, deadline);
  

    let tokenBalance = await pair.balanceOf(to);
    totalSupply = await pair.totalSupply();
    console.log("Our share", (Number(tokenBalance) * 1.0 / Number(totalSupply)));
    reserves = await pair.getReserves();
    reservesOLAS = reserves._reserve0;
    reservesETH = reserves._reserve1;
    let priceLPAfterAdd = (reservesOLAS.mul(e18)).div(totalSupply);
    console.log("priceLP",priceLPAfterAdd);
    if(priceLPBefore.eq(priceLPAfterAdd)) {
        console.log("addLiqidity not moved priceLP = reservesOLAS/totalSupply");
    }
    tokenBalance = tokenBalance.div(ethers.BigNumber.from(2));
    console.log(tokenBalance);

    // Remove liquidity
    await router.connect(wallet).removeLiquidity(wethAddress, olasAddress, tokenBalance, 0, 0, to, deadline);

    reserves = await pair.getReserves();
    reservesOLAS = reserves._reserve0;
    reservesETH = reserves._reserve1;
    totalSupply = await pair.totalSupply();
    let priceLPAfterRem = (reservesOLAS.mul(e18)).div(totalSupply);
    console.log("priceLP",priceLPAfterRem);

    if(priceLPAfterRem.eq(priceLPAfterAdd)) {
        console.log("removeLiqidity not moved priceLP = reservesOLAS/totalSupply");
    }

    /*
    node scripts/fork/ganache_node_with_timelock_account.js
    Current fork block number: 17784307
        1691064650
        OLAS balance: 1.0629334248726272e+22
        WETH balance: 1000000000000000000
        priceLP BigNumber { _hex: '0x05b819057dd47a6b2f', _isBigNumber: true }
        Our share 0.00356481863355418
        priceLP BigNumber { _hex: '0x05b819057dd47a6b2f', _isBigNumber: true }
        addLiqidity not moved priceLP = reservesOLAS/totalSupply
        BigNumber { _hex: '0x015c195520dc3c6cc1', _isBigNumber: true }
        priceLP BigNumber { _hex: '0x05b819057dd47a6b2f', _isBigNumber: true }
        removeLiqidity not moved priceLP = reservesOLAS/totalSupply
        2925
    */

    // Approve LP token for treasury
    //await pair.connect(wallet).approve(treasuryAddress, ethers.constants.MaxUint256);

    // Deposit for the bond
    //await depository.connect(wallet).deposit(0, "5" + "0".repeat(19));

    // Get the current nonce
    console.log(await provider.getTransactionCount(to));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
