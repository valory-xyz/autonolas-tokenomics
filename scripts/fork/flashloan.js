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

    const attackerJSON = "artifacts/contracts/test/FlashLoanAttacker.sol/FlashLoanAttacker.json";
    contractFromJSON = fs.readFileSync(attackerJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];
    const bytecode = parsedFile["bytecode"];
    const factory = new ethers.ContractFactory(abi, bytecode);
    const attacker = await factory.connect(wallet).deploy();
    await attacker.deployed();

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

    // Get the current nonce
    console.log(await provider.getTransactionCount(to));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
