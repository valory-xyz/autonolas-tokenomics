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

    const depositoryJSON = "artifacts/contracts/Depository.sol/Depository.json";
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
        fromBlock: curBlockNumber - 10, // Starting block number to search for the event (You can adjust this)
        toBlock: curBlockNumber, // Ending block number to search for the event
        address: depository.address,
        topics: filter,
    });

    const blockNumber = logs[0].blockNumber;
    const block = await provider.getBlock(blockNumber);
    const timestamp = block.timestamp;
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
    //await router.connect(wallet).swapExactETHForTokens(0, path, to, deadline, {value: ethers.utils.parseEther("1")});

    // Get the OLAS contract
    const olasJSON = "abis/test/OLAS.json";
    contractFromJSON = fs.readFileSync(olasJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const olas = new ethers.Contract(olasAddress, abi, signer);
    //console.log("OLAS balance:", Number(await olas.balanceOf(to)));

    // Get the WETH contract
    const wethJSON = "artifacts/canonical-weth/contracts/WETH9.sol/WETH9.json";
    contractFromJSON = fs.readFileSync(wethJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const weth = new ethers.Contract(wethAddress, abi, signer);

    // Get WETH for ETH
    //await weth.connect(wallet).deposit({value: ethers.utils.parseEther("1")});
    //console.log("WETH balance:", Number(await weth.balanceOf(wallet.address)));

    // Approve tokens for router
    //await olas.connect(wallet).approve(uniswapRouterAddress, ethers.constants.MaxUint256);
    //await weth.connect(wallet).approve(uniswapRouterAddress, ethers.constants.MaxUint256);
    // Get WETH-OLAS liquidity
    //await router.connect(wallet).addLiquidity(wethAddress, olasAddress, ethers.utils.parseEther("0.5"), ethers.utils.parseEther("10000"), 0, 0, to, deadline);

    // Get the LP contract
    const pairJSON = "artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json";
    contractFromJSON = fs.readFileSync(pairJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const pair = new ethers.Contract(tokenAddress, abi, signer);
    const tokenBalance = Number(await pair.balanceOf(to));
    const totalSupply = Number(await pair.totalSupply());
    //console.log("Our share", (tokenBalance * 1.0 / totalSupply));

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
