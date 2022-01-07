/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let signers;
    const name = "service name";
    const description = "service description";
    const agentIds = [1, 2];
    const agentNumSlots = [3, 4];
    const operatorSlots = [1, 10];
    const serviceId = 1;
    const agentId = 1;
    const threshold = 1;
    const componentHash = "0x0";
    const AddressZero = "0x" + "0".repeat(40);
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        const gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy(agentRegistry.address, gnosisSafeL2.address,
            gnosisSafeProxyFactory.address);
        await serviceRegistry.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Should fail when checking for the service id existence", async function () {
            const tokenId = 0;
            expect(await serviceRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the manager from a different address", async function () {
            await expect(
                serviceRegistry.connect(signers[3]).changeManager(signers[3].address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    context("Service creation", async function () {
        it("Should fail when creating a service without a manager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.createService(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("manager: MANAGER_ONLY");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const manager = signers[3];
            const AddressZero = "0x" + "0".repeat(40);
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(AddressZero, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("createService: EMPTY_OWNER");
        });

        it("Should fail when creating a service with an empty name", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, "", description, agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: EMPTY_NAME");
        });

        it("Should fail when creating a service with an empty description", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, "", agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: NO_DESCRIPTION");
        });

        it("Should fail when creating a service with incorrect agent slots values", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [], [],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: AGENTS_SLOTS");
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [1], [],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: AGENTS_SLOTS");
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [1, 3], [2],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: AGENTS_SLOTS");
        });

        it("Should fail when creating a service with incorrect operator slots values", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                    [], threshold)
            ).to.be.revertedWith("serviceInfo: OPERATOR_SLOTS");
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                    [0], threshold)
            ).to.be.revertedWith("serviceInfo: OPERATOR_SLOTS");
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                    [5, 2], threshold)
            ).to.be.revertedWith("serviceInfo: OPERATOR_SLOTS");
        });

        it("Should fail when creating a service with non existent canonical agent", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [0], [1],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: AGENT_NOT_FOUND");
        });

        it("Should fail when creating a service with duplicate canonical agents in agent slots", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [1, 1], [2, 2],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: DUPLICATE_AGENT");
        });

        it("Should fail when creating a service with incorrect input parameter", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, [1, 0], [2, 2],
                    operatorSlots, threshold)
            ).to.be.revertedWith("serviceInfo: AGENT_NOT_FOUND");
        });

        it("Checking for different signers threshold combinations", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            const minThreshold = Math.floor(maxThreshold * 2 / 3 + 1);
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, minThreshold - 1)
            ).to.be.revertedWith("serviceInfo: THRESHOLD");
            await expect(
                serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, maxThreshold + 1)
            ).to.be.revertedWith("serviceInfo: THRESHOLD");
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, minThreshold);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
        });

        it("Catching \"CreateServiceTransaction\" event log after registration of a service", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            const service = await serviceRegistry.connect(manager).createService(owner, name, description, agentIds,
                agentNumSlots, operatorSlots, maxThreshold);
            const result = await service.wait();
            expect(result.events[0].event).to.equal("CreateServiceTransaction");
        });

        it("Service Id=1 after first successful service registration must exist", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            expect(await serviceRegistry.exists(1)).to.equal(true);
        });
    });

    context("Service update", async function () {
        it("Should fail when creating a service without a manager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.createService(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("manager: MANAGER_ONLY");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const manager = signers[3];
            const AddressZero = "0x" + "0".repeat(40);
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).updateService(AddressZero, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold, 0)
            ).to.be.revertedWith("serviceOwner: SERVICE_NOT_FOUND");
        });

        it("Should fail when trying to update a non-existent service", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).updateService(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold, 0)
            ).to.be.revertedWith("serviceOwner: SERVICE_NOT_FOUND");
        });

        it("Catching \"UpdateServiceTransaction\" event log after update of a service", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            const service = await serviceRegistry.connect(manager).updateService(owner, name, description, agentIds,
                agentNumSlots, operatorSlots, maxThreshold, 1);
            const result = await service.wait();
            expect(result.events[0].event).to.equal("UpdateServiceTransaction");
            expect(await serviceRegistry.exists(1)).to.equal(true);
            expect(await serviceRegistry.exists(2)).to.equal(false);
        });

        it("Should fail when trying to update the service with already registered agent instances", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(manager).updateService(owner, name, description, agentIds,
                    agentNumSlots, operatorSlots, maxThreshold, 1)
            ).to.be.revertedWith("agentInstance: REGISTERED");
        });
    });

    context("Register agent instance", async function () {
        it("Should fail when registering an agent instance without a manager", async function () {
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await expect(
                serviceRegistry.registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("manager: MANAGER_ONLY");
        });

        it("Should fail when registering an agent instance with a non-existent service", async function () {
            const manager = signers[4];
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("serviceExists: NO_SERVICE");
        });

        it("Should fail when registering an agent instance for the inactive service", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("registerAgent: INACTIVE");
        });

        it("Should fail when registering an agent instance that is already registered", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("registerAgent: REGISTERED");
        });

        it("Should fail when registering an agent instance after the timeout", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).setRegistrationWindow(owner, serviceId, 0);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("registerAgent: TIMEOUT");
        });

        it("Should fail when registering an agent instance for non existent canonical agent Id in the service", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, 0)
            ).to.be.revertedWith("registerAgent: NO_AGENT");
        });

        it("Should fail when registering an agent instance for the service with no available slots", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[0], agentId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[1], agentId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[2], agentId);
            await expect(
                serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[3], agentId)
            ).to.be.revertedWith("registerAgent: SLOTS_FILLED");
        });

        it("Catching \"RegisterInstanceTransaction\" event log after agent instance registration", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            const regAgent = await serviceRegistry.connect(manager).registerAgent(operator, serviceId,
                agentInstance, agentId);
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstanceTransaction");
        });

        it("Registering several agent instances in different services by the same operator", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address, signers[9].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).activate(owner, serviceId + 1);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[0], agentId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId + 1, agentInstance[1], agentId);
            const regAgent = await serviceRegistry.connect(manager).registerAgent(operator, serviceId,
                agentInstance[2], agentId);
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstanceTransaction");
        });

        it("Should fail when registering an agent instance with the same address as operator", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await expect(
                serviceRegistry.connect(manager).registerAgent(agentInstances[0], serviceId, agentInstances[0], agentId)
            ).to.be.revertedWith("registerAgent: WRONG_OPERATOR");
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstances[0], agentId);
            await expect(
                serviceRegistry.connect(manager).registerAgent(agentInstances[0], serviceId, agentInstances[1], agentId)
            ).to.be.revertedWith("registerAgent: WRONG_OPERATOR");
        });
    });

    context("Activate and deactivate the service", async function () {
        it("Should fail when activating a service without a manager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.activate(owner, serviceId)
            ).to.be.revertedWith("manager: MANAGER_ONLY");
        });

        it("Should fail when activating a non-existent service", async function () {
            const manager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(manager.address);
            await expect(
                serviceRegistry.connect(manager).activate(owner, serviceId + 1)
            ).to.be.revertedWith("serviceOwner: SERVICE_NOT_FOUND");
        });

        it("Should fail when activating a service that is already active", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await expect(
                serviceRegistry.connect(manager).activate(owner, serviceId)
            ).to.be.revertedWith("activate: SERVICE_ACTIVE");
        });

        it("Catching \"ActivateService\" event log after service activation", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            const activateService = await serviceRegistry.connect(manager).activate(owner, serviceId);
            const result = await activateService.wait();
            expect(result.events[0].event).to.equal("ActivateService");
        });

        it("Should fail when deactivating a service with at least one registered agent instance", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(manager).deactivate(owner, serviceId)
            ).to.be.revertedWith("agentInstance: REGISTERED");
        });

        it("Should fail when deactivating a service that is already inactive", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await expect(
                serviceRegistry.connect(manager).deactivate(owner, serviceId)
            ).to.be.revertedWith("deactivate: SERVICE_INACTIVE");
        });

        it("Catching \"DeactivateService\" event log after service deactivation", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            const deactivateService = await serviceRegistry.connect(manager).deactivate(owner, serviceId);
            const result = await deactivateService.wait();
            expect(result.events[0].event).to.equal("DeactivateService");
        });
    });

    context("Safe contract from agent instances", async function () {
        it("Should fail when creating a Safe without a full set of registered agent instances", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(manager).createSafe(owner, serviceId, AddressZero, "0x", AddressZero,
                    AddressZero, 0, AddressZero, serviceId)
            ).to.be.revertedWith("createSafe: NUM_INSTANCES");
        });

        it("Catching \"CreateSafeWithAgents\" event log when calling the Safe contract creation", async function () {
            const minter = signers[3];
            const manager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address];
            const maxThreshold = 2;
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await serviceRegistry.changeManager(manager.address);
            await serviceRegistry.connect(manager).createService(owner, name, description, [1], [2],
                operatorSlots, maxThreshold);
            await serviceRegistry.connect(manager).activate(owner, serviceId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[0], agentId);
            await serviceRegistry.connect(manager).registerAgent(operator, serviceId, agentInstance[1], agentId);
            const safe = await serviceRegistry.connect(manager).createSafe(owner, serviceId, AddressZero, "0x",
                AddressZero, AddressZero, 0, AddressZero, serviceId);
            const result = await safe.wait();
            expect(result.events[0].event).to.equal("CreateSafeWithAgents");
        });
    });
});
