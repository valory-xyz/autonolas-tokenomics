/*global process*/

const { ethers } = require("hardhat");
const { L1ERC20Gateway } = require("@arbitrum/sdk/dist/lib/abi/L1ERC20Gateway");
const { L2ERC20Gateway } = require("@arbitrum/sdk/dist/lib/abi/L2ERC20Gateway");
const { L1ToL2MessageGasEstimator } = require("@arbitrum/sdk/dist/lib/message/L1ToL2MessageGasEstimator");
const { Erc20Bridger, getL2Network } = require("@arbitrum/sdk");
const { getBaseFee } = require("@arbitrum/sdk/dist/lib/utils/lib");

const main = async () => {
    // Setting up providers and wallets
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const arbitrumSepoliaURL = "https://sepolia-rollup.arbitrum.io/rpc";
    const arbitrumSepoliaProvider = new ethers.providers.JsonRpcProvider(arbitrumSepoliaURL);
    await arbitrumSepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number arbitrum sepolia: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOAarbitrumSepolia = new ethers.Wallet(account, arbitrumSepoliaProvider);
    console.log("EOA", EOAsepolia.address);
    if (EOAarbitrumSepolia.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    const l1TokenAddress = "0xeb2725bD76f6b1569Cf1484fCa0f2D55714A085d";
    //const erc20Token = (await ethers.getContractAt("ERC20Token", tokenAddress)).connect(EOAarbitrumSepolia);
    //console.log(erc20Token.address);

    // Use l2Network to create an Arbitrum SDK EthBridger instance
    // We'll use EthBridger to retrieve the Inbox address
    const l2Network = await getL2Network(arbitrumSepoliaProvider);

    // Get L1 and L2 gateway addresses
    const erc20Bridger = new Erc20Bridger(l2Network);
    // const l1ERC20GatewayAddress = erc20Bridger.l2Network.tokenBridge.l1ERC20Gateway;
    // const l2ERC20GatewayAddress = erc20Bridger.l2Network.tokenBridge.l2ERC20Gateway;

    // Calculate the L2 token address
    const l2TokenAddress = await erc20Bridger.getL2ERC20Address(
        l1TokenAddress,
        sepoliaProvider
    );
    console.log("L2 calculated token address:", l2TokenAddress);

    const res = await erc20Bridger.deposit({
        amount: 0,
        erc20L1Address: l1TokenAddress,
        l1Signer: EOAsepolia,
        l2Provider: arbitrumSepoliaProvider
    });

    const rec = await res.wait(2);
    console.log("L2 deployment tx:", rec.transactionHash);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
