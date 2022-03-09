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
    const configHash = {hash: "0x" + "5".repeat(64), hashFunction: "0x12", size: "0x20"};
    const configHash1 = {hash: "0x" + "6".repeat(64), hashFunction: "0x12", size: "0x20"};
    const agentIds = [1, 2];
    const agentNumSlots = [3, 4];
    const serviceId = 1;
    const agentId = 1;
    const threshold = 1;
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
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

        it("Should fail when trying to change the serviceManager from a different address", async function () {
            await expect(
                serviceRegistry.connect(signers[3]).changeManager(signers[3].address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    context("Service creation", async function () {
        it("Should fail when creating a service without a serviceManager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.createService(owner, name, description, configHash, agentIds, agentNumSlots, threshold)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const serviceManager = signers[3];
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(AddressZero, name, description, configHash, agentIds,
                    agentNumSlots, threshold)
            ).to.be.revertedWith("ZeroAddress");
        });

        it("Should fail when creating a service with an empty name", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, "", description, configHash, agentIds,
                    agentNumSlots, threshold)
            ).to.be.revertedWith("EmptyString");
        });

        it("Should fail when creating a service with an empty description", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, "", configHash, agentIds, agentNumSlots,
                    threshold)
            ).to.be.revertedWith("EmptyString");
        });

        it("Should fail when creating a service with a wrong config IPFS hash header", async function () {
            const wrongConfigHashes = [ {hash: "0x" + "0".repeat(64), hashFunction: "0x11", size: "0x20"},
                {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x19"}];
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, wrongConfigHashes[0],
                    agentIds, agentNumSlots, threshold)
            ).to.be.revertedWith("WrongHash");
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, wrongConfigHashes[1],
                    agentIds, agentNumSlots, threshold)
            ).to.be.revertedWith("WrongHash");
        });

        it("Should fail when creating a service with incorrect agent slots values", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [], [], threshold)
            ).to.be.revertedWith("WrongAgentIdsData");
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1], [], threshold)
            ).to.be.revertedWith("WrongAgentIdsData");
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1, 3], [2],
                    threshold)
            ).to.be.revertedWith("WrongAgentIdsData");
        });

        it("Should fail when creating a service with non existent canonical agent", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                    agentNumSlots, threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when creating a service with duplicate canonical agents in agent slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1, 1], [2, 2],
                    threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when creating a service with incorrect input parameter", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1, 0], [2, 2],
                    threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when trying to set empty agent slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds, [3, 0],
                    threshold)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Checking for different signers threshold combinations", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            const minThreshold = Math.floor(maxThreshold * 2 / 3 + 1);
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                    agentNumSlots, minThreshold - 1)
            ).to.be.revertedWith("WrongThreshold");
            await expect(
                serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                    agentNumSlots, maxThreshold + 1)
            ).to.be.revertedWith("WrongThreshold");
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, minThreshold);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
        });

        it("Catching \"CreateService\" event log after registration of a service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            const service = await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash,
                agentIds, agentNumSlots, maxThreshold);
            const result = await service.wait();
            expect(result.events[0].event).to.equal("CreateService");
        });

        it("Service Id=1 after first successful service registration must exist", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            expect(await serviceRegistry.exists(1)).to.equal(true);
        });
    });

    context("Service update", async function () {
        it("Should fail when creating a service without a serviceManager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.createService(owner, name, description, configHash, agentIds, agentNumSlots, threshold)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const serviceManager = signers[3];
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).update(AddressZero, name, description, configHash, agentIds,
                    agentNumSlots, threshold, 0)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when trying to update a non-existent service", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).update(owner, name, description, configHash, agentIds,
                    agentNumSlots, threshold, 0)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Catching \"UpdateService\" event log after update of a service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            const service = await serviceRegistry.connect(serviceManager).update(owner, name, description, configHash,
                agentIds, agentNumSlots, maxThreshold, 1);
            const result = await service.wait();
            expect(result.events[0].event).to.equal("UpdateService");
            expect(await serviceRegistry.exists(1)).to.equal(true);
            expect(await serviceRegistry.exists(2)).to.equal(false);
        });

        it("Should fail when trying to update the service with already registered agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(serviceManager).update(owner, name, description, configHash, agentIds,
                    agentNumSlots, maxThreshold, 1)
            ).to.be.revertedWith("AgentInstanceRegistered");
        });

        it("Update specifically for hashes, then get service hashes", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);

            // If we update with the same config hash as previous one, it must not be added
            await serviceRegistry.connect(serviceManager).update(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold, 1);
            let hashes = await serviceRegistry.getConfigHashes(serviceId);
            expect(hashes.numHashes).to.equal(1);
            expect(hashes.configHashes[0].hash).to.equal(configHash.hash);

            // Now we are going to have two config hashes
            await serviceRegistry.connect(serviceManager).update(owner, name, description, configHash1, agentIds,
                agentNumSlots, maxThreshold, 1);
            hashes = await serviceRegistry.getConfigHashes(serviceId);
            expect(hashes.numHashes).to.equal(2);
            expect(hashes.configHashes[0].hash).to.equal(configHash.hash);
            expect(hashes.configHashes[1].hash).to.equal(configHash1.hash);
        });
    });

    context("Register agent instance", async function () {
        it("Should fail when registering an agent instance without a serviceManager", async function () {
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await expect(
                serviceRegistry.registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when registering an agent instance with a non-existent service", async function () {
            const serviceManager = signers[4];
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("ServiceDoesNotExist");
        });

        it("Should fail when registering an agent instance for the inactive service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("ServiceInactive");
        });

        it("Should fail when registering an agent instance that is already registered", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description,
                []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("AgentInstanceRegistered");
        });

        it("Should fail when registering an agent instance for non existent canonical agent Id", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, 0)
            ).to.be.revertedWith("AgentNotInService");
        });

        it("Should fail when registering an agent instance for the service with no available slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance[0], agentId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance[1], agentId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance[2], agentId);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance[3], agentId)
            ).to.be.revertedWith("AgentInstancesSlotsFilled");
        });

        it("Catching \"RegisterInstance\" event log after agent instance registration", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            const regAgent = await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId,
                agentInstance, agentId);
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstance");
        });

        it("Registering several agent instances in different services by the same operator", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address, signers[9].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance[0], agentId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId + 1, agentInstance[1], agentId);
            const regAgent = await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId,
                agentInstance[2], agentId);
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstance");
        });

        it("Should fail when registering an agent instance with the same address as operator", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(agentInstances[0], serviceId, agentInstances[0], agentId)
            ).to.be.revertedWith("WrongOperator");
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstances[0], agentId);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(agentInstances[0], serviceId, agentInstances[1], agentId)
            ).to.be.revertedWith("WrongOperator");
        });
    });

    context("activateRegistration / deactivateRegistration / destroy the service", async function () {
        it("Should fail when activating a service without a serviceManager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.activateRegistration(owner, serviceId)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when activating a non-existent service", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when activating a service that is already active", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId)
            ).to.be.revertedWith("ServiceActive");
        });

        it("Catching \"ActivateRegistration\" event log after service activation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            const activateService = await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            const result = await activateService.wait();
            expect(result.events[0].event).to.equal("ActivateRegistration");
        });

        it("Should fail when deactivating a service with at least one registered agent instance", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(serviceManager).deactivateRegistration(owner, serviceId)
            ).to.be.revertedWith("AgentInstanceRegistered");
        });

        it("Should fail when deactivating a service that is already inactive", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await expect(
                serviceRegistry.connect(serviceManager).deactivateRegistration(owner, serviceId)
            ).to.be.revertedWith("ServiceInactive");
        });

        it("Catching \"DeactivateRegistration\" event log after service deactivation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            const deactivateService = await serviceRegistry.connect(serviceManager).deactivateRegistration(owner, serviceId);
            const result = await deactivateService.wait();
            expect(result.events[0].event).to.equal("DeactivateRegistration");
        });

        it("Should fail when trying to destroy a service with at least one agent instance", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(serviceManager).destroy(owner, serviceId)
            ).to.be.revertedWith("ServiceActive");
        });

        it("Catching \"DestroyService\" event. Service is destroyed without agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            const deactivateService = await serviceRegistry.connect(serviceManager).destroy(owner, serviceId);
            const result = await deactivateService.wait();
            expect(result.events[0].event).to.equal("DestroyService");
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
        });

        it("\"DestroyService\" event: expired service is destroyed with agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 1);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId)
            ).to.be.revertedWith("ServiceTerminated");
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(7);
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 0);
            serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 1);
            const deactivateService = await serviceRegistry.connect(serviceManager).destroy(owner, serviceId);
            const result = await deactivateService.wait();
            expect(result.events[0].event).to.equal("DestroyService");
        });

        it("\"DestroyService\" event: inactive service with the termination block set is destroyed", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 1000);
            const tBlock = await serviceRegistry.getTerminationBlock(serviceId);
            expect(tBlock).to.equal(1000);
            const deactivateService = await serviceRegistry.connect(serviceManager).destroy(owner, serviceId);
            const result = await deactivateService.wait();
            expect(result.events[0].event).to.equal("DestroyService");
        });
    });

    context("Safe contract from agent instances", async function () {
        it("Should fail when creating a Safe without a full set of registered agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstance, agentId);
            await expect(
                serviceRegistry.connect(serviceManager).createSafe(owner, serviceId, AddressZero, "0x", AddressZero,
                    AddressZero, 0, AddressZero, serviceId)
            ).to.be.revertedWith("AgentInstancesSlotsNotFilled");
        });

        it("Catching \"CreateSafeWithAgents\" event log when calling the Safe contract creation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            const maxThreshold = 2;

            // Create a component
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash2, description, [1]);

            // Create a service and activate the agent instance registration
            let state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1], [2],
                maxThreshold);
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(1);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(2);

            /// Register agent instances
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstances[0], agentId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstances[1], agentId);
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(4);

            // Set termination block and try to deploy the service. It must fail as termination block has passed
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 1);
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(6);
            await expect(
                serviceRegistry.connect(serviceManager).createSafe(owner, serviceId, AddressZero, "0x",
                    AddressZero, AddressZero, 0, AddressZero, serviceId)
            ).to.be.revertedWith("ServiceTerminated");

            // Set the termination block to unlimited and create safe
            await serviceRegistry.connect(serviceManager).setTerminationBlock(owner, serviceId, 0);
            const safe = await serviceRegistry.connect(serviceManager).createSafe(owner, serviceId, AddressZero, "0x",
                AddressZero, AddressZero, 0, AddressZero, serviceId);
            const result = await safe.wait();
            expect(result.events[0].event).to.equal("CreateSafeWithAgents");
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(5);

            // Check the service info
            const serviceIdFromAgentId = await serviceRegistry.getServiceIdsCreatedWithAgentId(agentId);
            expect(serviceIdFromAgentId.numServiceIds).to.equal(1);
            expect(serviceIdFromAgentId.serviceIds[0]).to.equal(serviceId);
            for (let i = 1; i < 2; i++) {
                const serviceIdFromComponentId = await serviceRegistry.getServiceIdsCreatedWithComponentId(i);
                expect(serviceIdFromComponentId.numServiceIds).to.equal(1);
                expect(serviceIdFromComponentId.serviceIds[0]).to.equal(serviceId);
            }
        });
    });

    context("High-level read-only service info requests", async function () {
        it("Should fail when requesting info about a non-existent service", async function () {
            const owner = signers[3].address;
            expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

            await expect(
                serviceRegistry.ownerOf(serviceId)
            ).to.be.revertedWith("ServiceDoesNotExist");

            await expect(
                serviceRegistry.getServiceInfo(serviceId)
            ).to.be.revertedWith("ServiceDoesNotExist");
        });

        it("Obtaining information about service existence, balance, owner, service info", async function () {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);

            // Initially owner does not have any services
            expect(await serviceRegistry.exists(serviceId)).to.equal(false);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

            // Creating a service
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);

            // Initial checks
            expect(await serviceRegistry.exists(serviceId)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);

            // Check for the service info components
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.owner).to.equal(owner);
            expect(serviceInfo.name).to.equal(name);
            expect(serviceInfo.description).to.equal(description);
            expect(serviceInfo.active).to.equal(false);
            expect(serviceInfo.numAgentIds).to.equal(agentIds.length);
            expect(serviceInfo.configHash.hash).to.equal(configHash.hash);
            for (let i = 0; i < agentIds.length; i++) {
                expect(serviceInfo.agentIds[i]).to.equal(agentIds[i]);
            }
            for (let i = 0; i < agentNumSlots.length; i++) {
                expect(serviceInfo.agentNumSlots[i]).to.equal(agentNumSlots[i]);
            }
            const tBlock = await serviceRegistry.getTerminationBlock(serviceId);
            expect(tBlock).to.equal(0);
        });

        it("Obtaining service information after update and creating one more service", async function () {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash1, description, []);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash2, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIds,
                agentNumSlots, maxThreshold);

            // Updating a service
            const newAgentIds = [1, 2, 3];
            const newAgentNumSlots = [2, 0, 1];
            const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[2];
            await serviceRegistry.connect(serviceManager).update(owner, name, description, configHash, newAgentIds,
                newAgentNumSlots, newMaxThreshold, serviceId);

            // Initial checks
            expect(await serviceRegistry.exists(serviceId)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);
            let totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices).to.equal(1);
            expect(totalSupply.maxServiceId).to.equal(1);

            // Check for the service info components
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.owner).to.equal(owner);
            expect(serviceInfo.name).to.equal(name);
            expect(serviceInfo.description).to.equal(description);
            expect(serviceInfo.active).to.equal(false);
            expect(serviceInfo.numAgentIds).to.equal(agentIds.length);
            const agentIdsCheck = [newAgentIds[0], newAgentIds[2]];
            for (let i = 0; i < agentIds.length; i++) {
                expect(serviceInfo.agentIds[i]).to.equal(agentIdsCheck[i]);
            }
            const agentNumSlotsCheck = [newAgentNumSlots[0], newAgentNumSlots[2]];
            for (let i = 0; i < agentNumSlotsCheck.length; i++) {
                expect(serviceInfo.agentNumSlots[i]).to.equal(agentNumSlotsCheck[i]);
            }
            const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
            expect(agentInstancesInfo.numAgentInstances).to.equal(0);

            // Creating a second service and do basic checks
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, agentIdsCheck,
                agentNumSlotsCheck, newMaxThreshold);
            expect(await serviceRegistry.exists(serviceId + 1)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
            expect(await serviceRegistry.ownerOf(serviceId + 1)).to.equal(owner);
            const serviceIds = await serviceRegistry.getServiceIdsOfOwner(owner);
            expect(serviceIds[0] == 1 && serviceIds[1]).to.equal(2);
            totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices).to.equal(2);
            expect(totalSupply.maxServiceId).to.equal(2);
        });

        it("Check for returned set of registered agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            const maxThreshold = 2;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, owner, componentHash, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).createService(owner, name, description, configHash, [1], [2],
                maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstances[0], agentId);
            await serviceRegistry.connect(serviceManager).registerAgent(operator, serviceId, agentInstances[1], agentId);

            /// Get the service info
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.numAagentInstances == agentInstances.length);
            for (let i = 0; i < agentInstances.length; i++) {
                expect(serviceInfo.agentInstances[i]).to.equal(agentInstances[i]);
            }
            const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
            expect(agentInstancesInfo.agentInstances == 2);
            for (let i = 0; i < agentInstances.length; i++) {
                expect(agentInstancesInfo.agentInstances[i]).to.equal(agentInstances[i]);
            }
        });

        it("Should fail when getting hashes of non-existent services", async function () {
            await expect(
                serviceRegistry.getConfigHashes(1)
            ).to.be.revertedWith("ServiceDoesNotExist");
        });
    });
});
