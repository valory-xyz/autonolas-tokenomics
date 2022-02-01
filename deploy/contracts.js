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
    const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
    const registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
    await registriesManager.deployed();

    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("RegistriesManager deployed to:", registriesManager.address);

    // Whitelisting minter in component and agent registry
    await componentRegistry.changeManager(registriesManager.address);
    await agentRegistry.changeManager(registriesManager.address);
    console.log("Whitelisted RegistriesManager addresses to both ComponentRegistry and AgentRegistry contract instances");
    
    // Test address, IPFS hashes and descriptions
    const testAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";
    const compHs = [{hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"}];
    const agentHs = [{hash: "0x" + "3".repeat(62) + "11", hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "4".repeat(62) + "11", hashFunction: "0x12", size: "0x20"}];
    const compDs = ["Component 1", "Component 2", "Component 3"];
    const agentDs = ["Agent 1", "Agent 2"];
    const configHash = {hash: "0x" + "5".repeat(62) + "22", hashFunction: "0x12", size: "0x20"};
    // Create 3 components and two agents based on them
    await registriesManager.mintComponent(testAddress, testAddress, compHs[0], compDs[0], []);
    await registriesManager.mintAgent(testAddress, testAddress, agentHs[0], agentDs[0], [1]);
    await registriesManager.mintComponent(testAddress, testAddress, compHs[1], compDs[1], [1]);
    await registriesManager.mintComponent(testAddress, testAddress, compHs[2], compDs[2], [1, 2]);
    await registriesManager.mintAgent(testAddress, testAddress, agentHs[1], agentDs[1], [1, 2, 3]);
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

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "registriesManager": registriesManager.address,
        "serviceRegistry": serviceRegistry.address,
        "serviceManager": serviceManager.address
    };

    // Write the json file with the setup
    let fs = require("fs");
    fs.writeFileSync("initDeploy.json", JSON.stringify(initDeployJSON));
};
