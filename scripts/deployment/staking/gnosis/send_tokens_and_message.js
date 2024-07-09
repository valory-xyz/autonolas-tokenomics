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

    const l1DepositProcessorAddress = "0x679Ce81a7bab6808534137585850dc81F90Ea8a4";
    const l2TargetDispenserAddress = "0xA126bf628f1fa7B922D0681733CbCE9236ca44Af";
    const targetInstance = "0x3c55f970d62d70dda9c3f9c7664e6f89010685ca";
    const defaultAmount = 100;
    const stakingTargets = [targetInstance];
    const stakingAmounts = new Array(stakingTargets.length).fill(defaultAmount);
    const payloadData = ethers.utils.defaultAbiCoder.encode(["address[]","uint256[]"], [stakingTargets, stakingAmounts]);
    const receiverABI = ["function receiveMessage(bytes memory data)"];
    const iReceiver = new ethers.utils.Interface(receiverABI);
    const messageCalldata = iReceiver.encodeFunctionData("receiveMessage", [payloadData]);
    console.log("messageCalldata:", messageCalldata);


    // TESTING OF SENDING TOKEN AND MESSAGE
    const fs = require("fs");
    const dispenserAddress = "0x42f43be9E5E50df51b86C5c6427223ff565f40C6";
    const dispenserJSON = "artifacts/contracts/staking/test/MockStakingDispenser.sol/MockStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

    const gasLimitMessage = "2000000";
    const bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [gasLimitMessage]);

    const transferAmount = defaultAmount;
    const gasLimit = "3000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        "0x", transferAmount, { gasLimit });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // tx back: https://gnosis-chiado.blockscout.com/tx/0x27e3b114b076cba6830d027a88bc8ccfb1af88d52f6c0d54cfab860cfb3cb687
    // To finalize, need to go to the AMBHelper contract, call getSignatures() with the encodedData from the UserRequestForSignature event
    // On AMBForeign, call the executeSignatures() function with the encodedData and obtained signatures
    // Finalizing tx on L1: https://sepolia.etherscan.io/tx/0x4e5cbcfa1342ca579c96d39a53470e4089abb42158524b89baece94e698ce1de
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
