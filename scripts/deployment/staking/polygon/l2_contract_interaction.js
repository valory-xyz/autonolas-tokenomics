/*global process*/

const { ethers } = require("hardhat");

const main = async () => {
    // Setting up providers and wallets
    const ALCHEMY_API_KEY_AMOY = process.env.ALCHEMY_API_KEY_AMOY;
    const amoyURL = "https://polygon-amoy.g.alchemy.com/v2/" + ALCHEMY_API_KEY_AMOY;
    const amoyProvider = new ethers.providers.JsonRpcProvider(amoyURL);
    await amoyProvider.getBlockNumber().then((result) => {
        console.log("Current block number amoy: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAamoy = new ethers.Wallet(account, amoyProvider);

    const fs = require("fs");
    const l2TargetDispenserAddress = "0xab217B10Fb8800Aa709fEECa19341eDF41853018";
    const dispenserJSON = "artifacts/contracts/staking/PolygonTargetDispenserL2.sol/PolygonTargetDispenserL2.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(l2TargetDispenserAddress, dispenserABI, amoyProvider);

    const gasLimit = "300000";
    const tx = await dispenser.connect(EOAamoy).syncWithheldAmount("0x", { gasLimit });
    console.log("TX hash", tx.hash);
    await tx.wait();
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
