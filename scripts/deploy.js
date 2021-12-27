/*global ethers, process*/

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
    const componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
        "https://localhost/component/");
    await componentRegistry.deployed();

    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    const agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
        componentRegistry.address);
    await agentRegistry.deployed();

    const MechMinter = await ethers.getContractFactory("MechMinter");
    const mechMinter = await MechMinter.deploy(componentRegistry.address, agentRegistry.address, "mech minter",
        "MECHMINTER");
    await mechMinter.deployed();

    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("MechMinter deployed to:", mechMinter.address);

    await componentRegistry.changeMinter(mechMinter.address);
    await agentRegistry.changeMinter(mechMinter.address);
    console.log("Whitelisted MechMinter addresses to both ComponentRegistry and AgentRegistry contract instances");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
