/*global ethers, process*/

async function main() {
    // Common parameters
    const AddressZero = "0x" + "0".repeat(40);

    // Test address, IPFS hashes and descriptions for components and agents
    const testAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";
    const compHs = [{hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"}];
    const agentHs = [{hash: "0x" + "3".repeat(62) + "11", hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "4".repeat(62) + "11", hashFunction: "0x12", size: "0x20"}];
    const compDs = ["Component 1", "Component 2", "Component 3"];
    const agentDs = ["Agent 1", "Agent 2"];
    const configHash = {hash: "0x" + "5".repeat(62) + "22", hashFunction: "0x12", size: "0x20"};

    // Safe related
    const safeThreshold = 7;
    const nonce =  0;

    // Governance related
    const minDelay = 1;
    const initialVotingDelay = 1; // blocks
    const initialVotingPeriod = 45818; // blocks ±= 1 week
    const initialProposalThreshold = 0; // voting power

    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());
    const signers = await ethers.getSigners();

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

    // Create 3 components and two agents based on defined component and agent hashes
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

    // Deploy safe multisig
    const safeSigners = signers.slice(1, 10).map(
        function (currentElement) {
            return currentElement.address;
        }
    );
    const setupData = gnosisSafeL2.interface.encodeFunctionData(
        "setup",
        // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
        [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
    );
    const safeContracts = require("@gnosis.pm/safe-contracts");
    const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
        setupData, nonce);
    await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());

    // Deploying governance contracts
    // Deploy voting token
    const Token = await ethers.getContractFactory("veOLA");
    const token = await Token.deploy();
    await token.deployed();
    console.log("veOLA token deployed to", token.address);

    // Deploy timelock with a multisig being a proposer
    const executors = [];
    const proposers = [proxyAddress];
    const Timelock = await ethers.getContractFactory("Timelock");
    const timelock = await Timelock.deploy(minDelay, proposers, executors);
    await timelock.deployed();
    console.log("Timelock deployed to", timelock.address);

    // Deploy Governance Bravo
    const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
    const governorBravo = await GovernorBravo.deploy(token.address, timelock.address, initialVotingDelay,
        initialVotingPeriod, initialProposalThreshold);
    await governorBravo.deployed();
    console.log("Governor Bravo deployed to", governorBravo.address);

    // Change the admin role from deployer to governorBravo
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    await timelock.connect(deployer).grantRole(adminRole, governorBravo.address);
    await timelock.connect(deployer).renounceRole(adminRole, deployer.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
