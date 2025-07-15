/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/staking/gnosis/globals_gnosis_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const provider = await ethers.providers.getDefaultProvider("mainnet");

    const networkURL = parsedData.networkURL;
    const networkProvider = new ethers.providers.JsonRpcProvider(networkURL);
    
    // Get EOAs
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAnetwork = new ethers.Wallet(account, networkProvider);

    // AMBProxy address on mainnet
    const AMBProxyAddress = parsedData.gnosisAMBForeignAddress;
    const AMBProxyJSON = "abis/bridges/gnosis/EternalStorageProxy.json";
    let contractFromJSON = fs.readFileSync(AMBProxyJSON, "utf8");
    const AMBProxyABI = JSON.parse(contractFromJSON);
    const AMBProxy = new ethers.Contract(AMBProxyAddress, AMBProxyABI, provider);

    // HomeMediator address on Gnosis
    const homeMediatorAddress = parsedData.bridgeMediatorAddress;
    const homeMediatorJSON = "abis/bridges/gnosis/HomeMediator.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, networkProvider);

    // OLAS address on Gnosis
    const olasAddress = parsedData.olasAddress;
    const tokenJSON = "artifacts/contracts/test/ERC20Token.sol/ERC20Token.json";
    contractFromJSON = fs.readFileSync(tokenJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const tokenABI = parsedFile["abi"];
    const olas = new ethers.Contract(olasAddress, tokenABI, networkProvider);

    // Get all the necessary contract addresses
    const oldTargetDispenserL2Address = "0x67722c823010CEb4BED5325fE109196C0f67D053";
    const targetDispenserL2Address = parsedData.gnosisTargetDispenserL2Address;

    // Get TargetDispenserL2 contracts
    const oldTargetDispenserL2 = (await ethers.getContractAt("GnosisTargetDispenserL2", oldTargetDispenserL2Address)).connect(EOAnetwork);
    const targetDispenserL2 = (await ethers.getContractAt("GnosisTargetDispenserL2", targetDispenserL2Address)).connect(EOAnetwork);

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

    olasBalance = await olas.balanceOf(targetDispenserL2Address);
    target = targetDispenserL2Address;
    rawPayload = targetDispenserL2.interface.encodeFunctionData("updateWithheldAmountMaintenance", [olasBalance]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Proposal preparation
    console.log("Proposal 20. Migrate funds from oldTargetDispenserL2Address to targetDispenserL2Address");
    // Build the bridge payload
    const mediatorPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);
    // Build the bridge payload
    const requestGasLimit = "2000000";
    const timelockPayload = await AMBProxy.interface.encodeFunctionData("requireToPassMessage", [homeMediatorAddress,
        mediatorPayload, requestGasLimit]);

    const targets = [AMBProxyAddress];
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
