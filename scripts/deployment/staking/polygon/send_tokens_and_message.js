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

    const l1DepositProcessorAddress = "0x60C3c81b855a6734312bF02256D496F5faec745A";
    const l2TargetDispenserAddress = "0x118173028162C1b7c6Bf8488bd5dA2abd7c30F9D";
    const targetInstance = "0xa28327f6b308f1a04e565025400311f48275c0fc";
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
    const dispenserAddress = "0x210af5b2FD68b3cdB94843C8e3462Daa52cCfe8F";
    const dispenserJSON = "artifacts/contracts/staking/test/MockStakingDispenser.sol/MockStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

    const transferAmount = defaultAmount;
    const gasLimit = "3000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        "0x", transferAmount, { gasLimit });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // List of addresses: https://contracts.decentraland.org/links

    // L2 to L1 tracking:
    // tx: https://amoy.polygonscan.com/tx/0x41523761a3a93f087920da294fc620f6f4ee2e1b8ad2acceb0d877bac60ea5cf
    // proof link: https://proof-generator.polygon.technology/api/v1/amoy/exit-payload/0x41523761a3a93f087920da294fc620f6f4ee2e1b8ad2acceb0d877bac60ea5cf?eventSignature=0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
