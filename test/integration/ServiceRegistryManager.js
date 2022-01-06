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
    const agentIds = [1, 2];
    const agentNumSlots = [3, 4];
    const operatorSlots = [1, 10];
    const serviceIds = [1, 2];
    const threshold = 1;
    const componentHash = "0x0";
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
                serviceManager.serviceCreate(owner, name, description, agentIds, agentNumSlots,
                    operatorSlots, threshold)
            ).to.be.revertedWith("manager: MANAGER_ONLY");
        });

        it("Service Id=1 after first successful service creation must exist", async function () {
            const minter = signers[4];
            const owner = signers[5].address;
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash, description, []);
            await agentRegistry.connect(minter).createAgent(owner, owner, componentHash + "1", description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(true);
        });

        it("Registering several services and agent instances", async function () {
            const minter = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "1",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
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
            const minter = signers[4];
            const owner = signers[5];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "1",
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "2",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceManager.serviceUpdate(owner.address, name, description, [1, 2, 3], [3, 0, 4],
                operatorSlots, maxThreshold, serviceIds[0]);
            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });
    });

    context("Service manipulations via manager", async function () {
        it("Creating services, updating one of them, activating, registering agent instances", async function () {
            const minter = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const maxThreshold = agentNumSlots[0] + agentNumSlots[1];
            await agentRegistry.changeMinter(minter.address);

            // Creating 3 canonical agents
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "1",
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "2",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating two services
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, agentIds, agentNumSlots,
                operatorSlots, maxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);
            await serviceManager.connect(owner).serviceActivate(serviceIds[1]);

            // Updating service Id == 1
            const newAgentIds = [1, 2, 3];
            const newAgentNumSlots = [2, 0, 1];
            const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[2];
            await serviceManager.serviceUpdate(owner.address, name, description, newAgentIds, newAgentNumSlots,
                operatorSlots, newMaxThreshold, serviceIds[0]);

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
            const minter = signers[4];
            const owner = signers[5];
            const operators = [signers[6], signers[7]];
            const agentInstances = [signers[8].address, signers[9].address, signers[10].address, signers[11].address];
            await agentRegistry.changeMinter(minter.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(minter).createAgent(owner.address, owner.address, componentHash + "1",
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating a service
            const newAgentIds = [1, 2];
            const newAgentNumSlots = [2, 1];
            const newMaxThreshold = newAgentNumSlots[0] + newAgentNumSlots[1];
            await serviceManager.serviceCreate(owner.address, name, description, newAgentIds, newAgentNumSlots,
                operatorSlots, newMaxThreshold);
            await serviceManager.connect(owner).serviceActivate(serviceIds[0]);

            // Registering agents for service Id == 1
            await serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[0],
                newAgentIds[0]);
            await serviceManager.connect(operators[1]).serviceRegisterAgent(serviceIds[0], agentInstances[1],
                newAgentIds[1]);
            // Safe is not possible without all the registered agent instances
            await expect(
                serviceManager.connect(owner).serviceCreateSafeDefault(serviceIds[0])
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

            // Creating Safe
            const safe = await serviceManager.connect(owner).serviceCreateSafeDefault(serviceIds[0]);
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
    });
});

