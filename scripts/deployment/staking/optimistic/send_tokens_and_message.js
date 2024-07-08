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

    const l1DepositProcessorAddress = "0x79A469c291cF7867eba1882e9F05E84A14dC378F";
    const l2TargetDispenserAddress = "0x5AEf43F1B212DF954f60C62C1F14333c28F44Ce2";
    const targetInstance = "0xCae661c929EC23e695e904d871C8D623f83bAC38";
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

    const gasPrice = ethers.utils.parseUnits("20", "gwei");
    // This is a contract-level message gas limit for L2 - capable of processing around 100 targets + amounts
    const minGasLimit = "2000000";
    // The default bridge payload is empty, uncomment if need to set gas limit more than 2M
    const bridgePayload = "0x";//ethers.utils.defaultAbiCoder.encode(["uint256"], [minGasLimit]);

    const transferAmount = defaultAmount;
    // Must be at least 20% bigger for the gas limit than the calculated one
    const gasLimit = "1000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        bridgePayload, transferAmount, { gasLimit, gasPrice });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // tx back: https://sepolia-optimism.etherscan.io/tx/0x299a1cb1d3811ce2addcc48e50eeb923ba1b9a16cacca5fd4ec83bd3af0961ee
    // tx result:

    // https://docs.optimism.io/builders/app-developers/tutorials/cross-dom-solidity#interact-with-the-l2-greeter
    // https://github.com/t4sk/notes/tree/main/op
    // Make sure to "yarn" the "op" package
    // cp .env.sample .env
    // Assign the private key in .env
    // Might change both L1 and L2 RPCs in src/index.js
    // export L2_TX=0x299a1cb1d3811ce2addcc48e50eeb923ba1b9a16cacca5fd4ec83bd3af0961ee
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
