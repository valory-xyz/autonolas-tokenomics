/*global process*/

const { ethers } = require("hardhat");

const main = async () => {
    // Setting up providers and wallets
    const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
    const polygonURL = "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC;
    const polygonProvider = new ethers.providers.JsonRpcProvider(polygonURL);
    await polygonProvider.getBlockNumber().then((result) => {
        console.log("Current block number polygon: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOApolygon = new ethers.Wallet(account, polygonProvider);

    const l1DepositProcessorAddress = "0xab217B10Fb8800Aa709fEECa19341eDF41853018";
    const l2TargetDispenserAddress = "0x7a6ca5BD19EE9182BEe5662008dFF05c60C3A76f";
    const targetInstance = "0x49DB8Be279e8eEc6975f30A3beCC57CAC9922cBB";
    const defaultAmount = ethers.utils.parseEther("100.0");
    const stakingTargets = [targetInstance];
    const stakingAmounts = new Array(stakingTargets.length).fill(defaultAmount);
    let payloadData = ethers.utils.defaultAbiCoder.encode(["address[]","uint256[]"], [stakingTargets, stakingAmounts]);


    // TESTING OF SENDING TOKEN AND MESSAGE
    const fs = require("fs");
    const dispenserAddress = "0xc2c7E40674f1C7Bb99eFe5680Efd79842502bED4";
    const dispenserJSON = "artifacts/contracts/staking/test/MockServiceStakingDispenser.sol/MockServiceStakingDispenser.json";
    const contractFromJSON = fs.readFileSync(dispenserJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const dispenserABI = parsedFile["abi"];
    const dispenser = new ethers.Contract(dispenserAddress, dispenserABI, polygonProvider);

    // gasLimitMessage is usually set to 2_000_000 as a constant in testing to handle about 200 targets + amounts
    const gasLimitMessage = "2000000";
    const bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
        [EOApolygon.address, gasLimitMessage]);
    console.log("bridgePayload", bridgePayload);
    const gasPrice = await polygonProvider.getGasPrice();

    // Run this with wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, gasLimitMessage);
    const wormholeCost = ethers.BigNumber.from("500000").mul(gasPrice);
    console.log("Wormhole cost", wormholeCost);
    const totalCost = wormholeCost.mul(2);

    const transferAmount = defaultAmount;
    const tx = await dispenser.connect(EOApolygon).mintAndSend(l1DepositProcessorAddress, targetInstance, defaultAmount,
        bridgePayload, transferAmount, { value: totalCost });
    console.log("TX hash", tx.hash);
    await tx.wait();

    // tx back:
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
