/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/staking/optimism/globals_optimism_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const provider = await ethers.providers.getDefaultProvider("mainnet");

    const networkURL = parsedData.networkURL;
    const networkProvider = new ethers.providers.JsonRpcProvider(networkURL);
    
    // Get EOAs
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAnetwork = new ethers.Wallet(account, networkProvider);

    // CDMProxy address on mainnet
    const CDMProxyAddress = parsedData.optimismL1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, provider);

    // OptimismMessenger address on Optimism
    const optimismMessengerAddress = parsedData.bridgeMediatorAddress;
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, networkProvider);

    // OLAS address on Optimism
    const olasAddress = parsedData.olasAddress;
    const tokenJSON = "artifacts/contracts/test/ERC20Token.sol/ERC20Token.json";
    contractFromJSON = fs.readFileSync(tokenJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const tokenABI = parsedFile["abi"];
    const olas = new ethers.Contract(olasAddress, tokenABI, networkProvider);

    // Get all the necessary contract addresses
    const oldTargetDispenserL2Address = "0x04b0007b2aFb398015B76e5f22993a1fddF83644";
    const targetDispenserL2Address = parsedData.optimismTargetDispenserL2Address;

    // Get TargetDispenserL2 contracts
    const oldTargetDispenserL2 = (await ethers.getContractAt("OptimismTargetDispenserL2", oldTargetDispenserL2Address)).connect(EOAnetwork);
    const targetDispenserL2 = (await ethers.getContractAt("OptimismTargetDispenserL2", targetDispenserL2Address)).connect(EOAnetwork);

    // Bridge mediator to migrate TargetDispenserL2 funds and execute the undelivered data
    const value = 0;
    let target = oldTargetDispenserL2Address;
    let rawPayload = oldTargetDispenserL2.interface.encodeFunctionData("pause", []);
    // Pack the second part of data
    let payload = ethers.utils.arrayify(rawPayload);
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    rawPayload = oldTargetDispenserL2.interface.encodeFunctionData("migrate", [targetDispenserL2Address]);
    // Pack the second part of data
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    const olasBalance = await olas.balanceOf(oldTargetDispenserL2Address);
    target = targetDispenserL2Address;
    rawPayload = targetDispenserL2.interface.encodeFunctionData("updateWithheldAmountMaintenance", [olasBalance]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Proposal preparation
    console.log("Proposal 18. Migrate funds from oldTargetDispenserL2Address to targetDispenserL2Address");
    // Build the bridge payload
    const messengerPayload = await optimismMessenger.interface.encodeFunctionData("processMessageFromSource", [data]);
    const minGasLimit = "2000000";
    // Build the final payload for the Timelock
    const timelockPayload = await CDMProxy.interface.encodeFunctionData("sendMessage", [optimismMessengerAddress,
        messengerPayload, minGasLimit]);

    const targets = [CDMProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Migrate funds from oldTargetDispenserL2Address to targetDispenserL2Address and update withheldAmount";

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
