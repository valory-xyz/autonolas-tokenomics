/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const provider = await ethers.providers.getDefaultProvider("mainnet");

    const optimisticURL = "https://optimism.drpc.org";
    const optimisticProvider = new ethers.providers.JsonRpcProvider(optimisticURL);
    
    // Get EOAs
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAmainnet = new ethers.Wallet(account, provider);
    const EOAoptimistic = new ethers.Wallet(account, optimisticProvider);

    // CDMProxy address on mainnet
    const CDMProxyAddress = parsedData.modeL1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, provider);

    // OptimismMessenger address on Mode
    const optimismMessengerAddress = "0x9338b5153AE39BB89f50468E608eD9d764B755fD";
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, optimisticProvider);

    // Get all the necessary contract addresses
    const oldTargetDispenserL2Address = "0x47135D1Cf850d7Df7f7f563F300cc7022F7978a4";
    const targetDispenserL2Address = parsedData.modeTargetDispenserL2Address;

    // Get TargetDispenserL2 contracts
    const oldTargetDispenserL2 = (await ethers.getContractAt("OptimismTargetDispenserL2", oldTargetDispenserL2Address));
    const targetDispenserL2 = (await ethers.getContractAt("OptimismTargetDispenserL2", targetDispenserL2Address)).connect(EOAoptimistic);

    // Bridge mediator to migrate TargetDispenserL2 funds and execute the undelivered data
    const value = 0;
    let target = oldTargetDispenserL2Address;
    let rawPayload = oldTargetDispenserL2.interface.encodeFunctionData("migrate", [targetDispenserL2Address]);
    // Pack the second part of data
    let payload = ethers.utils.arrayify(rawPayload);
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    target = targetDispenserL2Address;
    // Original un-delivered data:
    // 000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0e16c2d52963fd5d073b1f3907986b0a183c6e39399e5d8ef866c954b73886d7200000000000000000000000000000000000000000000000000000000000000010000000000000000000000005fc25f50e96857373c64dc0edb1abcbed4587e910000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000056a07b266954609c24
    // https://dashboard.tenderly.co/tx/mainnet/0xc947f7c5bc0c683ddb274030aa6e4d1305b0fc14bd17935598dc5b8a79922a5c/logs
    const dataToProcess = ethers.utils.defaultAbiCoder.encode(["address[]", "uint256[]", "bytes32"],
        [["0x5fc25f50e96857373c64dc0edb1abcbed4587e91"], ["1597983869041054358564"], "0xe16c2d52963fd5d073b1f3907986b0a183c6e39399e5d8ef866c954b73886d72"]);
    rawPayload = targetDispenserL2.interface.encodeFunctionData("processDataMaintenance", [dataToProcess]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Proposal preparation
    console.log("Proposal 11. Migrate funds from oldTargetDispenserL2Address to targetDispenserL2Address and re-deliver funds");
    // Build the bridge payload
    const messengerPayload = await optimismMessenger.interface.encodeFunctionData("processMessageFromSource", [data]);
    const minGasLimit = "2000000";
    // Build the final payload for the Timelock
    const timelockPayload = await CDMProxy.interface.encodeFunctionData("sendMessage", [optimismMessengerAddress,
        messengerPayload, minGasLimit]);

    const targets = [CDMProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Migrate funds from oldTargetDispenserL2Address to targetDispenserL2Address and re-deliver funds";

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
