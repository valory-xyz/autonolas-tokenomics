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

    const l1DepositProcessorAddress = "0x0C51d23918A8fFa6789A938E6D9555DD3982c99d";
    const l2TargetDispenserAddress = "0x93Cd3f6DcE64d67f4420939865A00aC89776D4b5";
    const targetInstance = "0x42C002Bc981A47d4143817BD9eA6A898a9916285";
    const defaultAmount = 100;
    const stakingTargets = [targetInstance];
    const stakingAmounts = new Array(stakingTargets.length).fill(defaultAmount);
    let payloadData = ethers.utils.defaultAbiCoder.encode(["address[]","uint256[]"], [stakingTargets, stakingAmounts]);
    let receiverABI = ["function receiveMessage(bytes memory data)"];
    let iReceiver = new ethers.utils.Interface(receiverABI);
    const messageCalldata = iReceiver.encodeFunctionData("receiveMessage", [payloadData]);
    console.log("messageCalldata", messageCalldata);


    // TESTING OF SENDING TOKEN AND MESSAGE
    const fs = require("fs");
    const dispenserAddress = "0x1F4C3134aFB97DE2BfBBF28894d24F58D0A95eFC";
    const dispenserJSON = "artifacts/contracts/test/MockServiceStakingDispenser.sol/MockServiceStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

    const minGasLimit = "2000000";
    const cost = "1000000";
    const bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256","uint256"], [cost, minGasLimit]);

    const transferAmount = defaultAmount;
    // Must be at least 20% bigger than cost
    const finalCost = "1200000";
    const gasLimit = "5000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        bridgePayload, transferAmount, { value: finalCost, gasLimit });
    console.log("TX hash", tx.hash);
    await tx.wait();
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
