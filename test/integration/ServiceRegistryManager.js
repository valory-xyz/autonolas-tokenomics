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
    const configHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const regBond = 1000;
    const agentIds = [1, 2];
    const agentParams = [[3, regBond], [4, regBond]];
    const serviceIds = [1, 2];
    const threshold = 1;
    const maxThreshold = agentParams[0][0] + agentParams[1][0];
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
    const nonce =  0;
    const AddressZero = "0x" + "0".repeat(40);
    // Deadline must be bigger than minimum deadline plus current block number. However hardhat keeps on increasing
    // block number for each test, so we set a high enough value here, and in time sensitive tests use current blocks
    const regDeadline = 100000;
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
                serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentParams, threshold)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Service Id=1 after first successful service creation must exist", async function () {
            const manager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner, owner, componentHash, description, []);
            await agentRegistry.connect(manager).create(owner, owner, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(true);
        });

        it("Registering several services and agent instances", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], regDeadline);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[1], regDeadline);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[0], agentIds[0], {value: regBond});
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[1], agentInstances[1], agentIds[1], {value: regBond});
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[2], agentIds[0], {value: regBond});

            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });
    });
    
    context("Service creation and update via manager", async function () {
        it("Creating services, updating one of them", async function () {
            const manager = signers[4];
            const owner = signers[5];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash2,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).serviceUpdate(name, description, configHash, [1, 2, 3],
                [[3, regBond], [0, regBond], [4, regBond]], maxThreshold, serviceIds[0]);
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
            await agentRegistry.changeManager(manager.address);

            // Creating 3 canonical agents
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash2,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating two services
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], regDeadline);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[1], regDeadline);
            let state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(2);

            // Updating service Id == 1
            const newAgentIds = [1, 2, 3];
            const newAgentParams = [[2, regBond], [0, regBond], [1, regBond]];
            const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
            await serviceManager.connect(owner).serviceUpdate(name, description, configHash, newAgentIds,
                newAgentParams, newMaxThreshold, serviceIds[0]);
            state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(2);

            // Registering agents for service Id == 1
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[0],
                newAgentIds[0], {value: regBond});
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[2],
                newAgentIds[0], {value: regBond});
            // After the update, service has only 2 slots for canonical agent 1 and 1 slot for canonical agent 3
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[3], newAgentIds[0], {value: regBond})
            ).to.be.revertedWith("AgentInstancesSlotsFilled");
            // Registering agent instance for the last possible slot
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[1],
                newAgentIds[2], {value: regBond});
            // Now all slots are filled and the service cannot register more agent instances
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[3], newAgentIds[2], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");

            // Cannot deactivate the service Id == 1 once one or more agent instances are registered
            await expect(
                serviceManager.connect(owner).serviceDeactivateRegistration(serviceIds[0])
            ).to.be.revertedWith("AgentInstanceRegistered");

            // But the service Id == 2 can be deactivated since it doesn't have instances registered yet
            serviceManager.connect(owner).serviceDeactivateRegistration(serviceIds[1]);

            // When deactivated, no agent instance registration is possible
            const newAgentInstance = signers[11].address;
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[1], newAgentInstance, agentIds[0], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");

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
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating a service
            const newAgentIds = [1, 2];
            const newAgentParams = [[2, regBond], [1, regBond]];
            const newMaxThreshold = newAgentParams[0][0] + newAgentParams[1][0];
            await serviceManager.serviceCreate(owner.address, name, description, configHash, newAgentIds,
                newAgentParams, newMaxThreshold);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], regDeadline);

            // Registering agents for service Id == 1
            await serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[0],
                newAgentIds[0], {value: regBond});
            await serviceManager.connect(operators[1]).serviceRegisterAgent(serviceIds[0], agentInstances[1],
                newAgentIds[1], {value: regBond});

            // Safe is not possible without all the registered agent instances
            await expect(
                serviceManager.connect(owner).serviceCreateSafe(serviceIds[0], AddressZero, "0x",
                    AddressZero, AddressZero, 0, AddressZero, nonce)
            ).to.be.revertedWith("WrongServiceState");
            // Registering the final agent instance
            await serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[2],
                newAgentIds[0], {value: regBond});

            // Check that neither of operators can register the agent after all slots have been filled
            await expect(
                serviceManager.connect(operators[0]).serviceRegisterAgent(serviceIds[0], agentInstances[3],
                    newAgentIds[0], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");
            await expect(
                serviceManager.connect(operators[1]).serviceRegisterAgent(serviceIds[0], agentInstances[3],
                    newAgentIds[1], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");

            // Since all instances are registered, we can change the deadline now
            await serviceManager.connect(owner).serviceSetRegistrationDeadline(serviceIds[0], regDeadline - 10);

            // Creating Safe with blanc safe parameters for the test
            const safe = await serviceManager.connect(owner).serviceCreateSafe(serviceIds[0], AddressZero, "0x",
                AddressZero, AddressZero, 0, AddressZero, nonce);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;

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
            await agentRegistry.changeManager(manager.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(manager).create(owner, owner, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner, owner, componentHash1,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating two services
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.serviceCreate(owner, name, description, configHash, agentIds, agentParams,
                maxThreshold);

            // Initial checks
            // Total supply must be 2
            let totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices).to.equal(2);
            expect(totalSupply.maxServiceId).to.equal(2);
            // Balance of owner is 2, each service id belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
            expect(await serviceRegistry.ownerOf(serviceIds[0])).to.equal(owner);
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner
            let serviceIdsRet = await serviceRegistry.getServiceIdsOfOwner(owner);
            expect(serviceIdsRet[0] == 1 && serviceIdsRet[1] == 2).to.be.true;

            // Destroy the very first service
            await serviceManager.connect(sigOwner).serviceDestroy(serviceIds[0]);

            // Check for the information consistency
            totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply.actualNumServices).to.equal(1);
            expect(totalSupply.maxServiceId).to.equal(2);
            // Balance of owner is 1, only service Id 2 belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(false);
            expect(await serviceRegistry.exists(serviceIds[1])).to.equal(true);
            // Requesting for service 1 must revert with non existent service
            await expect(
                serviceRegistry.ownerOf(serviceIds[0])
            ).to.be.revertedWith("ServiceDoesNotExist");
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner, must be service Id 2 only
            serviceIdsRet = await serviceRegistry.getServiceIdsOfOwner(owner);
            expect(serviceIdsRet[0]).to.equal(2);
        });

        it("Terminated service is unbonded and destroyed", async function () {
            const mechManager = signers[3];
            const owner = signers[4];
            const operator = signers[5];
            const agentInstances = [signers[6].address, signers[7].address];
            const maxThreshold = 2;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.connect(owner).serviceCreate(owner.address, name, description, configHash, [agentIds[0]],
                [[maxThreshold, regBond]], maxThreshold);

            // Activate agent instance registration and register an agent instance
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], regDeadline);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[0], agentIds[0], {value: regBond});

            // Try to unbond when service is still in active registration
            await expect(
                serviceManager.connect(operator).serviceUnbond(serviceIds[0])
            ).to.be.revertedWith("WrongServiceState");

            // Registering the remaining agent instance
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstances[1], agentIds[0], {value: regBond});

            // Terminate the service before it's deployed
            await serviceManager.connect(owner).serviceTerminate(serviceIds[0]);
            let state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(6);

            // Try to destroy the service now, but there are still bonded agent instances
            await expect(
                serviceManager.connect(owner).serviceDestroy(serviceIds[0])
            ).to.be.revertedWith("AgentInstanceRegistered");

            // Unbond agent instances
            await serviceManager.connect(operator).serviceUnbond(serviceIds[0]);
            state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(7);

            // Destroy the service after it's terminated-unbonded
            await serviceManager.connect(owner).serviceDestroy(serviceIds[0]);
            state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(0);
        });

        it("Should fail when trying to update the destroyed service", async function () {
            const manager = signers[4];
            const owner = signers[5];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash2,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).serviceDestroy(serviceIds[0]);
            await expect(
                serviceManager.connect(owner).serviceUpdate(name, description, configHash, [1, 2, 3],
                    [[3, regBond], [0, regBond], [4, regBond]], maxThreshold, serviceIds[0])
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when registering an agent instance after the timeout", async function () {
            const mechManager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            const nBlocks = Number(await serviceRegistry.getMinRegistrationDeadline());
            const blockNumber = await ethers.provider.getBlockNumber();
            // Deadline must be bigger than a current block number plus the minimum registration deadline
            const tDeadline = blockNumber + nBlocks + 10;
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], tDeadline);
            // Mining past the deadline
            for (let i = blockNumber; i <= tDeadline; i++) {
                ethers.provider.send("evm_mine");
            }
            await expect(
                serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstance, 1, {value: regBond})
            ).to.be.revertedWith("RegistrationTimeout");
            const state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(3);
        });

        it("Should fail when trying to destroy a service with the block number not reached", async function () {
            const mechManager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash, description, []);
            await agentRegistry.connect(mechManager).create(owner.address, owner.address, componentHash1, description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], regDeadline);
            await serviceManager.connect(operator).serviceRegisterAgent(serviceIds[0], agentInstance, 1, {value: regBond});
            await expect(
                serviceManager.connect(owner).serviceDestroy(serviceIds[0])
            ).to.be.revertedWith("AgentInstanceRegistered");
        });
    });
});

