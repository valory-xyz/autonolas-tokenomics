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

    const l1DepositProcessorAddress = "0x5Bb894d064A5c32a05DF64718dF3fF9A2549D258";
    const l2TargetDispenserAddress = "0xA9D794548486D15BfbCe2b8b5F5518b739fa8A4b";
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
    const dispenserJSON = "artifacts/contracts/test/MockServiceStakingDispenser.sol/MockServiceStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, sepoliaProvider);

    const gasPrice = ethers.utils.parseUnits("2", "gwei");
    // This is a contract-level message gas limit for L2 - capable of processing around 200 targets + amounts
    const minGasLimit = "2000000";
    const cost = ethers.BigNumber.from("1000000").mul(gasPrice);
    const bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [cost, minGasLimit]);

    const transferAmount = defaultAmount;
    // Must be at least 20% bigger than cost
    const finalCost = ethers.BigNumber.from("1200000").mul(gasPrice);
    const gasLimit = "5000000";
    const tx = await dispenser.connect(EOAsepolia).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        bridgePayload, transferAmount, { value: finalCost, gasLimit, gasPrice });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // tx back: https://sepolia-optimism.etherscan.io/tx/0x6ef9bb50e9a70077ddb00d978b0baf93e3ba17e5f36a3978b225e97f7b613884

    // TODO This must be called as IBridge.relayMessage() after the transaction challenge period has passed
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L303
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l2-to-l1-transactions-1
    /**
     * @notice Relays a message that was sent by the other CrossDomainMessenger contract. Can only
     *         be executed via cross-chain call from the other messenger OR if the message was
     *         already received once and is currently being replayed.
     *
     * @param _nonce       Nonce of the message being relayed.
     * @param _sender      Address of the user who sent the message.
     * @param _target      Address that the message is targeted at.
     * @param _value       ETH value to send with the message.
     * @param _minGasLimit Minimum amount of gas that the message can be executed with.
     * @param _message     Message to send to the target.
     */
//    function relayMessage(
//        uint256 _nonce,
//        address _sender,
//        address _target,
//        uint256 _value,
//        uint256 _minGasLimit,
//        bytes calldata _message
//    ) external payable;
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
