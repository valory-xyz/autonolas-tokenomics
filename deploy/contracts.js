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

    // Test address, IPFS hashes and descriptions
    const testAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";
    const compHs = ["QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB",
        "QmWWQSuPMS6aXCbZKpEjPHPUZN2NjB3YrhJTHsV4X3vb2t",
        "QmT4AeWE9Q9EaoyLJiqaZuYQ8mJeq4ZBncjjFH9dQ9uDVA"];
    const agentHs = ["QmT9qk3CRYbFDWpDFYeAv8T8H1gnongwKhh5J68NLkLir6",
        "QmT9qk3CRYbFDW5J68NLkLir6pDFYeAv8T8H1gnongwKhh"];
    const compDs = ["Component 1", "Component 2", "Component 3"];
    const agentDs = ["Agent 1", "Agent 2"];
    const configHash = "QmWWQKpEjPHPUZSuPMS6aXCbZN2NjBsV4X3vb2t3YrhJTH";
    // Create 3 components and two agents based on them
    await mechMinter.mintComponent(testAddress, testAddress, compHs[0], compDs[0], []);
    await mechMinter.mintAgent(testAddress, testAddress, agentHs[0], agentDs[0], [1]);
    await mechMinter.mintComponent(testAddress, testAddress, compHs[1], compDs[1], [1]);
    await mechMinter.mintComponent(testAddress, testAddress, compHs[2], compDs[2], [1, 2]);
    await mechMinter.mintAgent(testAddress, testAddress, agentHs[1], agentDs[1], [1, 2, 3]);
    const componentBalance = await componentRegistry.balanceOf(testAddress);
    const agentBalance = await agentRegistry.balanceOf(testAddress);
    console.log("Owner of minted components and agents:", testAddress);
    console.log("Number of components:", componentBalance);
    console.log("Number of agents:", agentBalance);

    // Gnosis Safe deployment
    const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
    const gnosisSafeL2 = await GnosisSafeL2.deploy();
    await gnosisSafeL2.deployed();

    const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
    const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
    await gnosisSafeProxyFactory.deployed();

    // Creating and updating a service
    const name = "service name";
    const description = "service description";
    const agentIds = [1, 2];
    const agentNumSlots = [3, 4];
    const maxThreshold = agentNumSlots[0] + agentNumSlots[1];

    const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
    const serviceRegistry = await ServiceRegistry.deploy(agentRegistry.address, gnosisSafeL2.address,
        gnosisSafeProxyFactory.address);
    await serviceRegistry.deployed();

    const ServiceManager = await ethers.getContractFactory("ServiceManager");
    const serviceManager = await ServiceManager.deploy(serviceRegistry.address);
    await serviceManager.deployed();

    console.log("ServiceRegistry deployed to:", serviceRegistry.address);
    console.log("ServiceManager deployed to:", serviceManager.address);

    // Create a service
    await serviceRegistry.changeManager(serviceManager.address);
    await serviceManager.serviceCreate(testAddress, name, description, configHash, agentIds, agentNumSlots,
        maxThreshold);

    // Update a service
    const newAgentNumSlots = [2, 0];
    const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[1];
    await serviceManager.serviceUpdate(testAddress, name, description, configHash, agentIds, newAgentNumSlots,
        newMaxThreshold, 1);

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "mechMinter": mechMinter.address,
        "serviceRegistry": serviceRegistry.address,
        "serviceManager": serviceManager.address
    };

    // Write the json file with the setup
    let fs = require("fs");
    fs.writeFileSync("initDeploy.json", JSON.stringify(initDeployJSON));
};
