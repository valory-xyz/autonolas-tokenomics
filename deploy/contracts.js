/*global ethers*/

module.exports = async () => {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploying component registry
    const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
    const componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
        "https://localhost/component/");
    await componentRegistry.deployed();

    // Deploying agent registry
    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    const agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
        componentRegistry.address);
    await agentRegistry.deployed();

    // Deploying minter
    const MechMinter = await ethers.getContractFactory("MechMinter");
    const mechMinter = await MechMinter.deploy(componentRegistry.address, agentRegistry.address, "mech minter",
        "MECHMINTER");
    await mechMinter.deployed();

    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("MechMinter deployed to:", mechMinter.address);

    // Whitelisting minter in component and agent registry
    await componentRegistry.changeMinter(mechMinter.address);
    await agentRegistry.changeMinter(mechMinter.address);
    console.log("Whitelisted MechMinter addresses to both ComponentRegistry and AgentRegistry contract instances");

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "mechMinter": mechMinter.address
    };

    // Write the json file with the setup
    let fs = require("fs");
    fs.writeFileSync("initDeploy.json", JSON.stringify(initDeployJSON));

    // Test address
    const testAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";
    // Create 3 components and two agents based on them
    await mechMinter.mintComponent(testAddress, testAddress, "componentHash 1", "Component 1", []);
    await mechMinter.mintAgent(testAddress, testAddress, "agentHash 1", "Agent 1", [1]);
    await mechMinter.mintComponent(testAddress, testAddress, "componentHash 2", "Component 2", [1]);
    await mechMinter.mintComponent(testAddress, testAddress, "componentHash 3", "Component 3", [1, 2]);
    await mechMinter.mintAgent(testAddress, testAddress, "agentHash 2", "Agent 2", [1, 2, 3]);
    const componentBalance = await componentRegistry.balanceOf(testAddress);
    const agentBalance = await agentRegistry.balanceOf(testAddress);
    console.log("Owner of minted components and agents:", testAddress);
    console.log("Number of components:", componentBalance);
    console.log("Number of agents:", agentBalance);
};
