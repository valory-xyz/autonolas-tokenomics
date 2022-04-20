/*global describe, context, beforeEach, it*/
const { ethers, network } = require("hardhat");
const { expect } = require("chai");

describe("Tokenomics integration", async () => {
    const decimals = "0".repeat(18);
    const LARGE_APPROVAL = "1" + "0".repeat(6) + decimals;
    // Initial mint for ola and DAI (40,000)
    const initialMint = "4" + "0".repeat(4) + decimals;
    // Increase timestamp by amount determined by `offset`

    let erc20Token;
    let olaFactory;
    let depositoryFactory;
    let tokenomicsFactory;
    let veFactory;
    let dispenserFactory;
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let gnosisSafeMultisig;

    let dai;
    let ola;
    let pairODAI;
    let depository;
    let treasury;
    let treasuryFactory;
    let tokenomics;
    let ve;
    let dispenser;
    let epochLen = 100;

    let vesting = 60 * 60 *24;
    let timeToConclusion = 60 * 60 * 24;
    let conclusion;

    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
    const agentHash = {hash: "0x" + "7".repeat(64), hashFunction: "0x12", size: "0x20"};
    const agentHash1 = {hash: "0x" + "8".repeat(64), hashFunction: "0x12", size: "0x20"};
    const agentHash2 = {hash: "0x" + "9".repeat(64), hashFunction: "0x12", size: "0x20"};
    const configHash = {hash: "0x" + "5".repeat(64), hashFunction: "0x12", size: "0x20"};
    const configHash1 = {hash: "0x" + "6".repeat(64), hashFunction: "0x12", size: "0x20"};
    const regBond = 1000;
    const regDeposit = 1000;
    const maxThreshold = 1;
    const name = "service name";
    const description = "service description";
    const hundredETHBalance = ethers.utils.parseEther("100");
    const twoHundredETHBalance = ethers.utils.parseEther("200");
    const regServiceRevenue = hundredETHBalance;
    const doubleRegServiceRevenue = twoHundredETHBalance;
    const agentId = 1;
    const agentParams = [1, regBond];
    const serviceId = 1;
    const payload = "0x";
    const magicDenominator = 5192296858534816;
    const E18 = 10**18;
    const delta = 1.0 / 10**10;

    let signers;

    /**
     * Everything in this block is only run once before all tests.
     * This is the home for setup methods
     */
    beforeEach(async () => {
        signers = await ethers.getSigners();
        olaFactory = await ethers.getContractFactory("OLA");
        erc20Token = await ethers.getContractFactory("ERC20Token");
        depositoryFactory = await ethers.getContractFactory("Depository");
        treasuryFactory = await ethers.getContractFactory("Treasury");
        tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
        dispenserFactory = await ethers.getContractFactory("Dispenser");
        veFactory = await ethers.getContractFactory("VotingEscrow");

        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", agentRegistry.address);
        await serviceRegistry.deployed();

        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        const gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();


        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafeL2.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const deployer = signers[0];
        dai = await erc20Token.deploy();
        ola = await olaFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy(ola.address, deployer.address, deployer.address, epochLen, componentRegistry.address,
            agentRegistry.address, serviceRegistry.address);
        // Correct depository address is missing here, it will be defined just one line below
        treasury = await treasuryFactory.deploy(ola.address, deployer.address, tokenomics.address, deployer.address);
        // Change to the correct treasury address
        await tokenomics.changeTreasury(treasury.address);
        // Change to the correct depository address
        depository = await depositoryFactory.deploy(ola.address, treasury.address, tokenomics.address);
        await treasury.changeDepository(depository.address);
        await tokenomics.changeDepository(depository.address);

        ve = await veFactory.deploy(ola.address, "Governance OLA", "veOLA", "0.1", deployer.address);
        dispenser = await dispenserFactory.deploy(ola.address, ve.address, treasury.address, tokenomics.address);
        await ve.changeDispenser(dispenser.address);
        await treasury.changeDispenser(dispenser.address);

        // Airdrop from the deployer :)
        await dai.mint(deployer.address, initialMint);
        await ola.mint(deployer.address, initialMint);
        // Change treasury address
        await ola.changeTreasury(treasury.address);
        
        const block = await ethers.provider.getBlock("latest");
        conclusion = block.timestamp + timeToConclusion;
    });

    it("Calculate tokenomics factors with service registry coordination. One service is deployed", async () => {
        const mechManager = signers[3];
        const serviceManager = signers[4];
        const owner = signers[5].address;
        const operator = signers[6].address;
        const agentInstance = signers[7].address;

        // Create one agent
        await agentRegistry.changeManager(mechManager.address);
        await agentRegistry.connect(mechManager).create(owner, owner, agentHash, description, []);

        // Create one service
        await serviceRegistry.changeManager(serviceManager.address);
        await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [agentId],
            [agentParams], maxThreshold);

        // Register agent instances
        await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
        await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

        // Deploy the service
        await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
        await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);

        // Send deposits from a service
        await treasury.depositETHFromService(1, {value: regServiceRevenue});

        // Calculate current epoch parameters
        await treasury.allocateRewards();

        // Get the information from tokenomics point
        const epoch = await tokenomics.getEpoch();
        const point = await tokenomics.getPoint(epoch);

        // Checking the values with delta rounding error
        const ucf = Number(point.ucf / magicDenominator) * 1.0 / E18;
        expect(Math.abs(ucf - 0.5)).to.lessThan(delta);

        const usf = Number(point.usf / magicDenominator) * 1.0 / E18;
        expect(Math.abs(usf - 1.0)).to.lessThan(delta);
    });

    context("Tokenomics numbers", async function () {
        it("Calculate tokenomics factors. One service is deployed", async () => {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;

            // Create one agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash, description, []);

            // Create one service
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [agentId],
                [agentParams], maxThreshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

            // Deploy the service
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);

            // Send deposits from a service
            await treasury.depositETHFromService(1, {value: regServiceRevenue});

            // Calculate current epoch parameters
            await treasury.allocateRewards();

            // Get the information from tokenomics point
            const epoch = await tokenomics.getEpoch();
            const point = await tokenomics.getPoint(epoch);

            // Checking the values with delta rounding error
            const ucf = Number(point.ucf / magicDenominator) * 1.0 / E18;
            console.log(ucf);
            expect(Math.abs(ucf - 0.5)).to.lessThan(delta);

            const usf = Number(point.usf / magicDenominator) * 1.0 / E18;
            expect(Math.abs(usf - 1.0)).to.lessThan(delta);
        });

        it("Calculate tokenomics factors. Two services with one agent for each, 3 agents in total", async () => {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];

            // Create 3 agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash1, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash2, description, []);

            // Create services
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [agentId],
                [agentParams], maxThreshold);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash1, [2],
                [agentParams], maxThreshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, 2, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstances[0]], [agentId], {value: regBond});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, 2, [agentInstances[1]], [2], {value: regBond});

            // Deploy services
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);
            await serviceRegistry.connect(serviceManager).deploy(owner, 2, gnosisSafeMultisig.address, payload);

            // Fail if the sent amount and the sum of specified amount for each service do not match
            await expect(
                treasury.depositETHFromServiceBatch([1, 2], [regServiceRevenue, regServiceRevenue], {value: regServiceRevenue})
            ).to.be.revertedWith("WrongAmount");
            // Fail if the service Ids / amounts array differ in length
            await expect(
                treasury.depositETHFromServiceBatch([1, 2], [regServiceRevenue], {value: regServiceRevenue})
            ).to.be.revertedWith("WrongArrayLength");

            // Send deposits from services
            await treasury.depositETHFromServiceBatch([1, 2], [regServiceRevenue, regServiceRevenue], {value: doubleRegServiceRevenue});

            // Calculate current epoch parameters
            await treasury.allocateRewards();

            // Get the information from tokenomics point
            const epoch = await tokenomics.getEpoch();
            const point = await tokenomics.getPoint(epoch);

            // Checking the values with delta rounding error
            const ucf = Number(point.ucf / magicDenominator) * 1.0 / E18;
            expect(Math.abs(ucf - 0.166666666666666)).to.lessThan(delta);

            const usf = Number(point.usf / magicDenominator) * 1.0 / E18;
            expect(Math.abs(usf - 0.5)).to.lessThan(delta);
        });

        it("Calculate tokenomics factors. Two services with different set of agents are deployed", async () => {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const operator = signers[4].address;
            const agentInstances = [signers[5].address, signers[6].address, signers[7].address, signers[8].address];

            // Create 3 agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash1, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, agentHash2, description, []);

            // Create services
            const agentIds = [[1, 2], [2, 3]];
            const agentParams = [[1, regBond], [1, regBond]];
            const threshold = 2;
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds[0],
                agentParams, threshold);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash1, agentIds[1],
                agentParams, threshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, 2, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstances[0], agentInstances[1]],
                agentIds[0], {value: 2 * regBond});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, 2, [agentInstances[2], agentInstances[3]],
                agentIds[1], {value: 2 * regBond});

            // Deploy services
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);
            await serviceRegistry.connect(serviceManager).deploy(owner, 2, gnosisSafeMultisig.address, payload);

            // Send deposits services
            await treasury.depositETHFromServiceBatch([1, 2], [regServiceRevenue, regServiceRevenue], {value: doubleRegServiceRevenue});

            // Calculate current epoch parameters
            await treasury.allocateRewards();

            // Get the information from tokenomics point
            const epoch = await tokenomics.getEpoch();
            const point = await tokenomics.getPoint(epoch);

            // Checking the values with delta rounding error
            const ucf = Number(point.ucf / magicDenominator) * 1.0 / E18;
            expect(Math.abs(ucf - 0.375)).to.lessThan(delta);

            const usf = Number(point.usf / magicDenominator) * 1.0 / E18;
            expect(Math.abs(usf - 0.5)).to.lessThan(delta);
        });
    });


    context("Dispenser", async function () {
        it("Dispenser for an agent owner", async () => {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5];
            const ownerAddress = owner.address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;

            // Create one agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(ownerAddress, ownerAddress, agentHash, description, []);

            // Create one service
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(ownerAddress, name, description, configHash, [agentId],
                [agentParams], maxThreshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(ownerAddress, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

            // Deploy the service
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).deploy(ownerAddress, serviceId, gnosisSafeMultisig.address, payload);

            // Send deposits from a service
            await treasury.depositETHFromService(1, {value: regServiceRevenue});

            // Calculate current epoch parameters
            await treasury.allocateRewards();

            // Get owner rewards
            await dispenser.connect(owner).withdrawOwnerRewards();
            const balance = await ola.balanceOf(ownerAddress);

            // Check the received reward
            const agentFraction = await tokenomics.agentFraction();
            const expectedReward = regServiceRevenue * agentFraction / 100;
            expect(Number(balance)).to.equal(expectedReward);
        });
    });
});
