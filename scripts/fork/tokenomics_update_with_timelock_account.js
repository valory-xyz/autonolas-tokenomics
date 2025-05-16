/*global process*/

const { ethers } = require("ethers");

async function main() {
    // To run anvil fork with the timelock being the signer, use the following command:
    // anvil -f rpc_url --auto-impersonate --chain-id 1 --gas-price 20000000000 --gas-limit 1600000000

    let initBlockNumber;
    const URL = "http://127.0.0.1:8545";
    const provider = new ethers.providers.JsonRpcProvider(URL);
    await provider.getBlockNumber().then((result) => {
        initBlockNumber = result;
        console.log("Current fork block number: " + initBlockNumber);
    });

    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Get all the necessary contract addresses
    const timelockAddress = parsedData.timelockAddress;
    const tokenomicsProxyAddress = parsedData.tokenomicsProxyAddress;

    // Timelock address is specified via the "-u" command to ganache node
    const signer = provider.getSigner(timelockAddress);

    let privateKey = process.env.PRIVATE_KEY;
    let wallet = new ethers.Wallet(privateKey, provider);

    // Fund timelock
    await wallet.sendTransaction({to: timelockAddress, value: ethers.utils.parseEther("1")});

    const tokenomicsJSON = "artifacts/contracts/Tokenomics.sol/Tokenomics.json";
    let contractFromJSON = fs.readFileSync(tokenomicsJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Tokenomics contract instance
    const tokenomics = new ethers.Contract(tokenomicsProxyAddress, abi, signer);
    console.log("Tokenomics proxy address:", tokenomics.address);

    // Get bytecode
    const contractBytecode = parsedFile["bytecode"];
    let tx = await wallet.sendTransaction({
        data: contractBytecode,
        gasLimit: 10000000,
    });

    const receipt = await tx.wait();
    let tokenomicsImplementationAddress = receipt.contractAddress;
    // Currently deployed address
    //tokenomicsImplementationAddress = parsedData.tokenomicsFourAddress;
    console.log("New tokenomics implementation address:", tokenomicsImplementationAddress);

    // Change tokenomics implementation
    tx = await tokenomics.changeTokenomicsImplementation(tokenomicsImplementationAddress);
    await tx.wait();

    // Update tokenomics inflation
    console.log("\nUpdating tokenomics inflation");
    tx = await tokenomics.updateInflationPerSecondAndFractions(25, 4, 2, 69);
    let res = await tx.wait();
    console.log(res);

//    console.log("\nUpdate inflation events", res.logs);
//    // Epoch number where first staking claim is possible
//    const eNum = 14;
//    let j = 0;
//    for (let i = 1; i < 30; i += 3) {
//        const retained = ethers.utils.defaultAbiCoder.decode(["uint256"], res.logs[i].data);
//        console.log("retained in epoch:", eNum + j);
//        console.log("retained amount:", retained.toString());
//        j++;
//    }

    // Get inflation per second
    let inflationPerSecond = await tokenomics.inflationPerSecond();
    console.log("Updated inflation per second", inflationPerSecond.toString());
    let inflationPerYear = inflationPerSecond.mul(365).mul(86400);
    console.log("Updated inflation per year", inflationPerYear.toString());

    // Get current effective bond
    let effectiveBond = await tokenomics.effectiveBond();
    let maxBond = await tokenomics.maxBond();
    console.log("Updated effective bond:", effectiveBond.toString());
    console.log("Updated max bond:", maxBond.toString());

    // Update tokenomics inflation a second time (must not change values)
    console.log("\nUpdating tokenomics inflation again without tokenomics implementation change");
    tx = await tokenomics.updateInflationPerSecondAndFractions(25, 4, 2, 69);
    await tx.wait();

    // Get inflation per second and effective bond values
    inflationPerSecond = await tokenomics.inflationPerSecond();
    inflationPerYear = inflationPerSecond.mul(365).mul(86400);
    effectiveBond = await tokenomics.effectiveBond();
    maxBond = await tokenomics.maxBond();
    console.log("Updated inflation per second", inflationPerSecond.toString());
    console.log("Updated inflation per year", inflationPerYear.toString());
    console.log("Updated effective bond:", effectiveBond.toString());
    console.log("Updated max bond:", maxBond.toString());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
