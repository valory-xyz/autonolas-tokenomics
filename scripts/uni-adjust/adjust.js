/*global process*/

const hre = require("hardhat");

async function main() {
    var json = require("../../artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json");
    const actualBytecode = json["bytecode"];
    const initHash = hre.ethers.utils.keccak256(actualBytecode);
    const initHashReplace = initHash.slice(2);
    console.log(initHashReplace);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
