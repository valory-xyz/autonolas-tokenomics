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
    const tokenAddress = parsedData.XOLAS_WXDAI_PairAddress;

    // Timelock address is specified via the "-u" command to ganache node
    const signer = provider.getSigner(timelockAddress);

    let privateKey = process.env.PRIVATE_KEY;
    let wallet = new ethers.Wallet(privateKey, provider);
    wallet.sendTransaction({to: timelockAddress, value: ethers.utils.parseEther("1")});

    const treasuryJSON = "artifacts/contracts/Treasury.sol/Treasury.json";
    let contractFromJSON = fs.readFileSync(treasuryJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Treasury contract instance
    const treasury = new ethers.Contract(treasuryAddress, abi, signer);
    //console.log(treasury.address);

    // Enable tokenAddress
    await treasury.connect(signer).enableToken(tokenAddress);
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
    await depository.connect(signer).create(tokenAddress, "1417088700721071600", "1" + "0".repeat(23), vesting);
    //console.log(await depository.isActiveProduct(35));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
