/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];

    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;
    const tokenomicsTwoAddress = parsedData.tokenomicsTwoAddress;
    const donatorBlacklistAddress = parsedData.donatorBlacklistAddress;
    const depositoryTwoAddress = parsedData.depositoryTwoAddress;
    const treasuryAddress = parsedData.treasuryAddress;

    // Get the contracts
    const tokenomicsProxy = await ethers.getContractAt("Tokenomics", tokenomicsProxyAddress);
    const treasury = await ethers.getContractAt("Treasury", treasuryAddress);

    const AddressZero = "0x" + "0".repeat(40);

    const targets = new Array();
    const values = new Array();
    const callDatas = new Array();

    // Proposal preparation
    console.log("Proposal 7:");
    console.log("TokenomicsProxy to change Tokenomics implementation calling `changeTokenomicsImplementation(TokenomicsTwo)`");
    targets.push(tokenomicsProxyAddress);
    values.push(0);
    callDatas.push(tokenomicsProxy.interface.encodeFunctionData("changeTokenomicsImplementation", [tokenomicsTwoAddress]));

    console.log("TokenomicsProxy to change DonatorBlacklist calling changeDonatorBlacklist()");
    targets.push(tokenomicsProxyAddress);
    values.push(0);
    callDatas.push(tokenomicsProxy.interface.encodeFunctionData("changeDonatorBlacklist", [donatorBlacklistAddress]));

    console.log("TokenomicsProxy to change Depository calling changeManagers(0x, depositoryTwo, 0x)");
    targets.push(tokenomicsProxyAddress);
    values.push(0);
    callDatas.push(tokenomicsProxy.interface.encodeFunctionData("changeManagers", [AddressZero, depositoryTwoAddress, AddressZero]));

    console.log("Treasury to change Depository calling changeManagers(0x, depositoryTwo, 0x)");
    targets.push(treasuryAddress);
    values.push(0);
    callDatas.push(treasury.interface.encodeFunctionData("changeManagers", [AddressZero, depositoryTwoAddress, AddressZero]));

    const description = "Sync goerli with mainnet";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
