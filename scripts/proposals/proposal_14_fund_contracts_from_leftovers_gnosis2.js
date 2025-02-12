/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const provider = await ethers.providers.getDefaultProvider("mainnet");

    const gnosisURL = "https://rpc.gnosischain.com";
    const gnosisProvider = new ethers.providers.JsonRpcProvider(gnosisURL);
    
    // Get EOAs
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAmainnet = new ethers.Wallet(account, provider);
    const EOAgnosis = new ethers.Wallet(account, gnosisProvider);

    // AMBProxy on mainnet
    const AMBProxyAddress = parsedData.gnosisAMBForeignAddress;
    const AMBProxyJSON = "abis/bridges/gnosis/EternalStorageProxy.json";
    let contractFromJSON = fs.readFileSync(AMBProxyJSON, "utf8");
    const AMBProxyABI = JSON.parse(contractFromJSON);
    const AMBProxy = new ethers.Contract(AMBProxyAddress, AMBProxyABI, provider);

    // HomeMediator on gnosis
    const homeMediatorAddress = "0x15bd56669F57192a97dF41A2aa8f4403e9491776";
    const homeMediatorJSON = "abis/bridges/gnosis/HomeMediator.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, gnosisProvider);

    // Contract address
    const targetDispenserL2Address = parsedData.gnosisTargetDispenserL2Address;

    // TargetDispenserL2 contract instance
    const targetDispenserL2 = (await ethers.getContractAt("GnosisTargetDispenserL2", targetDispenserL2Address)).connect(EOAgnosis);

    const stakingAddresses = ["0x6C6D01e8eA8f806eF0c22F0ef7ed81D868C1aB39", "0x17dbae44bc5618cc254055b386a29576b4f87015", "0xb0ef657b8302bd2c74b6e6d9b2b4b39145b19c6f", "0x3112c1613eac3dbae3d4e38cef023eb9e2c91cf7", "0xf4a75f476801b3fbb2e7093acdcc3576593cc1fc", "0x1430107A785C3A36a0C1FC0ee09B9631e2E72aFf", "0x041e679d04Fc0D4f75Eb937Dea729Df09a58e454"];
    // Emissions needed: 9050*10^18, 12600*10^18, 12700*10^18, 12400*10^18, 13000*10^18, 320*10^18, 320*10^18
    const stakingAmounts = ["9050000000000000000000", "12600000000000000000000", "12700000000000000000000", "12400000000000000000000", "13000000000000000000000", "320000000000000000000", "320000000000000000000"]

    // Bridge mediator to migrate TargetDispenserL2 funds and execute the undelivered data
    const value = 0;
    const batchHash = "0x" + "0".repeat(62) + "01";
    let target = targetDispenserL2Address;
    const dataToProcess = ethers.utils.defaultAbiCoder.encode(["address[]", "uint256[]", "bytes32"],
        [stakingAddresses, stakingAmounts, batchHash]);
    let rawPayload = targetDispenserL2.interface.encodeFunctionData("processDataMaintenance", [dataToProcess]);
    // Pack the second part of data
    let payload = ethers.utils.arrayify(rawPayload);
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    console.log("Payload to simulate on L2:", rawPayload);

    // Proposal preparation
    console.log("Proposal 14. Additionally allocate funds to selected staking contracts from L2 leftovers");
    // Build the bridge payload
    const mediatorPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);

    // AMBContractProxyHomeAddress on gnosis mainnet: 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59
    // Function to call by homeMediator: processMessageFromForeign
    console.log("AMBContractProxyHomeAddress to call homeMediator's processMessageFromForeign function with the data:", data);

    const requestGasLimit = "2000000";
    const timelockPayload = await AMBProxy.interface.encodeFunctionData("requireToPassMessage", [homeMediatorAddress,
        mediatorPayload, requestGasLimit]);

    const targets = [AMBProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Additionally allocate funds to selected staking contracts from L2 leftovers";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
