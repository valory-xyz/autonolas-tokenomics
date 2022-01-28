/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceRegistry integration", function () {
    let componentRegistry;
    let agentRegistry;
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let serviceRegistry;
    let serviceManager;
    let signers;
    const name = "service name";
    const description = "service description";
    const configHash = "QmWWQKconfigHash";
    const agentIds = [1, 2];
    const agentNumSlots = [3, 4];
    const serviceIds = [1, 2];
    const threshold = 1;
    const componentHash = "0x0";
    const nonce =  0;
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
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy(agentRegistry.address, gnosisSafeL2.address,
            gnosisSafeProxyFactory.address);
        await serviceRegistry.deployed();

        const ServiceManager = await ethers.getContractFactory("ServiceManager");
        serviceManager = await ServiceManager.deploy(serviceRegistry.address);
        await serviceManager.deployed();

        signers = await ethers.getSigners();
    });

    context("Service creation via manager", async function () {
        it("Should fail when creating a service without a manager being white listed", async function () {
            const owner = signers[4].address;
            await expect(
                serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentNumSlots, threshold)
            ).to.be.revertedWith("serviceManager: MANAGER_ONLY");
        });

        it("Service Id=1 after first successful service creation must exist", async function () {
            const manager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(manager).create(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(true);
        });

        it("Registering several services and agent instances", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "1",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);
            await serviceManager.connect(owner).serviceActivate(serviceIds[1]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[0], agentIds[0]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[1], agentInstances[1], agentIds[1]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[2], agentIds[0]);

            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });
    });
    
    context("Service creation and update via manager", async function () {
        it("Creating services, updating one of them", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "1",
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "2",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceUpdate(owner.address, name, description, configHash, [1, 2, 3], [3, 0, 4],
                maxThreshold, serviceIds[0]);
            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });
    });

    context("Service manipulations via manager", async function () {
        it("Creating services, updating one of them, activating, registering agent instances", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);

            // Creating 3 canonical agents
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "1",
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "2",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating two services
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);
            await serviceManager.connect(owner).serviceActivate(serviceIds[1]);

            // Updating service Id == 1
            const newAgentIds = [1, 2, 3];
            const newAgentNumSlots = [2, 0, 1];
            const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[2];
            await serviceManager.serviceUpdate(owner.address, name, description, configHash, newAgentIds,
                newAgentNumSlots, newMaxThreshold, serviceIds[0]);

            // Registering agents for service Id == 1
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[0],
                newAgentIds[0]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[1],
                newAgentIds[2]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[2],
                newAgentIds[0]);

            // After the update, service has only 2 slots for canonical agent 1 and 1 slot for canonical agent 3
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[3], newAgentIds[0])
            ).to.be.revertedWith("registerAgent: SLOTS_FILLED");
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[3], newAgentIds[2])
            ).to.be.revertedWith("registerAgent: SLOTS_FILLED");

            // Cannot deactivate the service Id == 1 once one or more agent instances are registered
            await expect(
                serviceManager.connect(owner).serviceDeactivate(serviceIds[0])
            ).to.be.revertedWith("agentInstance: REGISTERED");

            // But the service Id == 2 can be deactivated since it doesn't have instances registered yet
            serviceManager.connect(owner).serviceDeactivate(serviceIds[1]);

            // When deactivated, no agent instance registration is possible
            const newAgentInstance = signers[11].address;
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[1], newAgentInstance, agentIds[0])
            ).to.be.revertedWith("registerAgent: INACTIVE");

            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });

        it("Creating a service, registering agent instances from different operators, calling Safe", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operators = [signers[6], signers[7]];
            const agentInstances = [signers[8].address, signers[9].address, signers[10].address, signers[11].address];
            await agentRegistry.changeManager(manager.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "1",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating a service
            const newAgentIds = [1, 2];
            const newAgentNumSlots = [2, 1];
            const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[1];
            await serviceManager.serviceCreate(owner.address, name, description, configHash, newAgentIds,
                newAgentNumSlots, newMaxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);

            // Registering agents for service Id == 1
            await serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[0],
                newAgentIds[0]);
            await serviceManager.connect(operators[1]).serviceRegisterAgent(serviceIds[0], agentInstances[1],
                newAgentIds[1]);

            // Safe is not possible without all the registered agent instances
            await expect(
                serviceManager.connect(owner).serviceCreateSafe(serviceIds[0], AddressZero, "0x",
                    AddressZero, AddressZero, 0, AddressZero, nonce)
            ).to.be.revertedWith("createSafe: NUM_INSTANCES");
            // Registering the final agent instance
            await serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[2],
                newAgentIds[0]);

            // Check that neither of operators can register the agent after all slots have been filled
            await expect(
                serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[3],
                    newAgentIds[0])
            ).to.be.revertedWith("registerAgent: SLOTS_FILLED");
            await expect(
                serviceManager.connect(operators[1]).serviceRegisterAgent(serviceIds[0], agentInstances[3],
                    newAgentIds[1])
            ).to.be.revertedWith("registerAgent: SLOTS_FILLED");

            // Creating Safe with blanc safe parameters for the test
            const safe = await serviceManager.connect(owner).serviceCreateSafe(serviceIds[0], AddressZero, "0x",
                AddressZero, AddressZero, 0, AddressZero, nonce);
            const result = await safe.wait();
            const proxyAddress = result.events[1].address;

            // Verify the deployment of the created Safe: checking threshold and owners
            const proxyContract = await ethers.getContractAt("GnosisSafeL2", proxyAddress);
            if (await proxyContract.getThreshold() != newMaxThreshold) {
                throw new Error("incorrect threshold");
            }
            const actualAgentInstances = [agentInstances[0], agentInstances[1], agentInstances[2]];
            for (const aInstance of actualAgentInstances) {
                const isOwner = await proxyContract.isOwner(aInstance);
                if (!isOwner) {
                    throw new Error("incorrect agent instance");
                }
            }
        });

        it("Creating services, destroying on of them, getting resulting information", async function () {
            const manager = signers[4];
            const sigOwner = signers[5];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(manager).create(owner, owner, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner, owner, componentHash + "1",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating two services
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);

            // Initial checks
            // Total supply must be 2
            let totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices == 2);
            expect(totalSupply.maxServiceId == 2);
            // Balance of owner is 2, each service id belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
            expect(await serviceRegistry.ownerOf(serviceIds[0])).to.equal(owner);
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner
            let serviceIdsRet = await serviceRegistry.getServiceIdsOfOwner(owner);
            expect(serviceIdsRet[0] == 1 && serviceIdsRet[1] == 2);

            // Destroy the very first service
            await serviceManager.connect(sigOwner).serviceDestroy(serviceIds[0]);

            // Check for the information consistency
            totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices == 1);
            expect(totalSupply.maxServiceId == 2);
            // Balance of owner is 1, only service Id 2 belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(false);
            expect(await serviceRegistry.exists(serviceIds[1])).to.equal(true);
            // Requesting for service 1 must revert with non existent service
            await expect(
                serviceRegistry.ownerOf(serviceIds[0])
            ).to.be.revertedWith("serviceExists: NO_SERVICE");
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner, must be service Id 2 only
            serviceIdsRet = await serviceRegistry.getServiceIdsOfOwner(owner);
            expect(serviceIdsRet[0] == 2);
        });

        it("Should fail when trying to update the destroyed service", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "1",
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash + "2",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.connect(owner).serviceDestroy(serviceIds[0]);
            await expect(
                serviceManager.serviceUpdate(owner.address, name, description, configHash, [1, 2, 3], [3, 0, 4],
                    maxThreshold, serviceIds[0])
            ).to.be.revertedWith("serviceOwner: SERVICE_NOT_FOUND");
        });

        it("Should fail when registering an agent instance after the timeout", async function () {
            const mechManager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash + "1", description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);
            await serviceManager.connect(owner).serviceSetRegistrationWindow(serviceIds[0], 0);
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstance, 1)
            ).to.be.revertedWith("registerAgent: TIMEOUT");
        });

        it("Should fail when trying to destroy a service with the block number not reached", async function () {
            const mechManager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash + "1", description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentNumSlots,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstance, 1)
            await serviceManager.connect(owner).serviceSetTerminationBlock(serviceIds[0], 1000);
            await expect(
                serviceManager.connect(owner).serviceDestroy(serviceIds[0])
            ).to.be.revertedWith("destroy: SERVICE_ACTIVE");
        });
    });
});

