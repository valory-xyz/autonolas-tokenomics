/*global ethers, process*/

async function main() {
    // We get the contract to deploy
    const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
    const componentRegistry = await ComponentRegistry.deploy();

    console.log("ComponentRegistry deployed to:", componentRegistry.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
