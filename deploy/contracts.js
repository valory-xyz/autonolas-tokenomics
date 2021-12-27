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
      componentRegistry: componentRegistry.address,
      agentRegistry: agentRegistry.address,
      mechMinter: mechMinter.address
    };

    let fs = require('fs');
    fs.writeFileSync("initDeploy.json", JSON.stringify(initDeployJSON));
};
