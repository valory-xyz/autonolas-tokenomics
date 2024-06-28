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

    const l1DepositProcessorAddress = "0x11acc5866363CAbeAB8EA57C0da64D85fDa92887";
    const l2TargetDispenserAddress = "0x9385d4E53c72a858C451D41f58Fcb8C070bDd18A";
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
    const dispenserAddress = "0x210af5b2FD68b3cdB94843C8e3462Daa52cCfe8F";
    const dispenserJSON = "artifacts/contracts/staking/test/MockStakingDispenser.sol/MockStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

//    console.log(await sepoliaProvider.getTransactionCount(EOAsepolia.address));
//    return;

    const gasPrice = ethers.utils.parseUnits("100", "gwei");
    // This is a contract-level message gas limit for L2 - capable of processing around 200 targets + amounts
    const minGasLimit = "2000000";
    const cost = 0;//ethers.BigNumber.from("1000000").mul(gasPrice);
    const bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [cost, minGasLimit]);

    const transferAmount = defaultAmount;
    // Must be at least 20% bigger for the gas limit than the calculated one
    const finalCost = ethers.BigNumber.from("1200000").mul(gasPrice);
    const gasLimit = "1000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        bridgePayload, transferAmount, { gasLimit, gasPrice });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // tx back: https://sepolia-optimism.etherscan.io/tx/0xad20c00a32969e6e819e4b5e47c7aba272b94d783e37db4706db56f414fc0db4
    // tx result:

    // https://docs.optimism.io/builders/app-developers/tutorials/cross-dom-solidity#interact-with-the-l2-greeter
    // https://github.com/t4sk/notes/tree/main/op
    // Make sure to "yarn" the "op" package
    // cp .env.sample .env
    // Assign the private key in .env
    // Might change both L1 and L2 RPCs in src/index.js
    // export L2_TX=0x6ef9bb50e9a70077ddb00d978b0baf93e3ba17e5f36a3978b225e97f7b613884
    // env $(cat .env) L2_TX=$L2_TX node src/index.js

    // This must be called as IBridge.relayMessage() after the transaction challenge period has passed
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L303
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l2-to-l1-transactions-1
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
