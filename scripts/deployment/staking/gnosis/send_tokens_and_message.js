/*global process*/

const { ethers } = require("hardhat");

const main = async () => {
    // Setting up providers and wallets
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);

    const l1DepositProcessorAddress = "0x92C42465483a58224B1F45A38b081Cfe28d671b0";
    const l2TargetDispenserAddress = "0x724bE493CeC72003C6941A9f4186dc2c45392315";
    const targetInstance = "0x4172a7f2888B8071b0df177f69d8FC61df0c164d";
    const defaultAmount = 100;
    const stakingTargets = [targetInstance];
    const stakingAmounts = new Array(stakingTargets.length).fill(defaultAmount);
    let payloadData = ethers.utils.defaultAbiCoder.encode(["address[]","uint256[]"], [stakingTargets, stakingAmounts]);
    let receiverABI = ["function receiveMessage(bytes memory data)"];
    let iReceiver = new ethers.utils.Interface(receiverABI);
    const messageCalldata = iReceiver.encodeFunctionData("receiveMessage", [payloadData]);
    console.log("messageCalldata:", messageCalldata);


    // TESTING OF SENDING TOKEN AND MESSAGE
    const fs = require("fs");
    const dispenserAddress = "0x1F4C3134aFB97DE2BfBBF28894d24F58D0A95eFC";
    const dispenserJSON = "artifacts/contracts/test/MockServiceStakingDispenser.sol/MockServiceStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

    const transferAmount = defaultAmount;
    const gasLimit = "3000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        "0x", transferAmount, { gasLimit });
    console.log("TX hash", tx.hash);
    await tx.wait();
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
