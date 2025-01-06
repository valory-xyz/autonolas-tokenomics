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

    const stakingAddresses = ["0x88eB38FF79fBa8C19943C0e5Acfa67D5876AdCC1", "0x6c65430515c70a3f5E62107CC301685B7D46f991"];
    // Emissions needed: 45534246575342515200000
    const stakingAmounts = Array(stakingAddresses.length).fill("45534246575342515200000");

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
