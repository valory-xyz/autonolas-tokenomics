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
    let gnosisSafeMultisig;
    let token;
    let treasury;
    let tokenomics;
    let signers;
    const name = "service name";
    const description = "service description";
    const configHash = {hash: "0x" + "5".repeat(64), hashFunction: "0x12", size: "0x20"};
    const regBond = 1000;
    const regDeposit = 1000;
    const regFine = 500;
    const regReward = 2000;
    const agentIds = [1, 2];
    const agentParams = [[3, regBond], [4, regBond]];
    const serviceIds = [1, 2];
    const threshold = 1;
    const maxThreshold = agentParams[0][0] + agentParams[1][0];
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
    const payload = "0x";
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
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", agentRegistry.address);
        await serviceRegistry.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafeL2.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const Token = await ethers.getContractFactory("OLA");
        token = await Token.deploy(0, AddressZero);
        await token.deployed();

        // Depositary and dispenser are irrelevant in this set of tests, tokenomics will be correctly assigned below
        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(token.address, AddressZero, AddressZero, AddressZero);
        await treasury.deployed();

        const ServiceManager = await ethers.getContractFactory("ServiceManager");
        serviceManager = await ServiceManager.deploy(serviceRegistry.address, treasury.address);
        await serviceManager.deployed();

        const Tokenomics = await ethers.getContractFactory("Tokenomics");
        tokenomics = await Tokenomics.deploy(token.address, treasury.address, AddressZero, AddressZero, 1,
            componentRegistry.address, agentRegistry.address, serviceRegistry.address);
        await tokenomics.deployed();

        // Change to the correct tokenomics address
        await treasury.changeTokenomics(tokenomics.address);
        await token.changeMinter(treasury.address);

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
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[1], {value: regDeposit});
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[0], agentInstances[2]],
                [agentIds[0], agentIds[0]], {value: 2*regBond});
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[1], [agentInstances[1]], [agentIds[1]], {value: regBond});

            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });

        it("Pausing and unpausing", async function () {
            const manager = signers[2];
            const owner = signers[3];

            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash, description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Can't unpause unpaused contract
            await expect(
                serviceManager.unpause()
            ).to.be.revertedWith("Pausable: not paused");

            // Pause the contract
            await serviceManager.pause();

            // Try creating a contract when paused
            await expect(
                serviceManager.serviceCreate(owner.address, name, description, configHash, [1], [[1, regBond]], 1)
            ).to.be.revertedWith("Pausable: paused");

            // Try to pause again
            await expect(
                serviceManager.pause()
            ).to.be.revertedWith("Pausable: paused");

            // Unpause the contract
            await serviceManager.unpause();

            // Create a service
            await serviceManager.serviceCreate(owner.address, name, description, configHash, [1], [[1, regBond]], 1);
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

            // Updating service Id == 1
            const newAgentIds = [1, 2, 3];
            const newAgentParams = [[2, regBond], [0, regBond], [1, regBond]];
            const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
            await serviceManager.connect(owner).serviceUpdate(name, description, configHash, newAgentIds,
                newAgentParams, newMaxThreshold, serviceIds[0]);
            let state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(1);

            // Activate the registration
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[1], {value: regDeposit});
            state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(2);

            // Fail when trying to update the service again, even though no agent instances are registered yet
            await expect(
                serviceManager.connect(owner).serviceUpdate(name, description, configHash, newAgentIds,
                    newAgentParams, newMaxThreshold, serviceIds[0])
            ).to.be.revertedWith("WrongServiceState");

            // Registering agents for service Id == 1
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[0], agentInstances[2]],
                [newAgentIds[0], newAgentIds[0]], {value: 2*regBond});
            // After the update, service has only 2 slots for canonical agent 1 and 1 slot for canonical agent 3
            await expect(
                serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[3]], [newAgentIds[0]], {value: regBond})
            ).to.be.revertedWith("AgentInstancesSlotsFilled");
            // Registering agent instance for the last possible slot
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[1]],
                [newAgentIds[2]], {value: regBond});
            // Now all slots are filled and the service cannot register more agent instances
            await expect(
                serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[3]], [newAgentIds[2]], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");

            // When terminated, no agent instance registration is possible
            await serviceManager.connect(owner).serviceTerminate(serviceIds[1]);
            const newAgentInstance = signers[11].address;
            await expect(
                serviceManager.connect(operator).serviceRegisterAgents(serviceIds[1], [newAgentInstance], [agentIds[0]], {value: regBond})
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
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});

            // Registering agents for service Id == 1
            await serviceManager.connect(operators[0]).serviceRegisterAgents(serviceIds[0], [agentInstances[0], agentInstances[1]],
                [newAgentIds[0], newAgentIds[1]], {value: 2*regBond});

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Safe is not possible without all the registered agent instances
            await expect(
                serviceManager.connect(owner).serviceDeploy(serviceIds[0], gnosisSafeMultisig.address, payload)
            ).to.be.revertedWith("WrongServiceState");
            // Registering the final agent instance
            await serviceManager.connect(operators[0]).serviceRegisterAgents(serviceIds[0], [agentInstances[2]],
                [newAgentIds[0]], {value: regBond});

            // Check that neither of operators can register the agent after all slots have been filled
            await expect(
                serviceManager.connect(operators[0]).serviceRegisterAgents(serviceIds[0], [agentInstances[3]],
                    [newAgentIds[0]], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");
            await expect(
                serviceManager.connect(operators[1]).serviceRegisterAgents(serviceIds[0], [agentInstances[3]],
                    [newAgentIds[1]], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");

            // Creating Safe with blanc safe parameters for the test
            const safe = await serviceManager.connect(owner).serviceDeploy(serviceIds[0], gnosisSafeMultisig.address, payload);
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
            expect(totalSupply).to.equal(2);
            // Balance of owner is 2, each service id belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
            expect(await serviceRegistry.ownerOf(serviceIds[0])).to.equal(owner);
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner
            let serviceIdsRet = await serviceRegistry.balanceOf(owner);
            for (let i = 0; i < serviceIdsRet; i++) {
                const serviceIdCheck = await serviceRegistry.tokenOfOwnerByIndex(owner, i);
                expect(serviceIdCheck).to.be.equal(i + 1);
            }

            // Activate registration and terminate the very first service and destroy it
            await serviceManager.connect(sigOwner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(sigOwner).serviceTerminate(serviceIds[0]);
            await serviceManager.connect(sigOwner).serviceDestroy(serviceIds[0]);

            // Check for the information consistency
            totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply).to.equal(1);
            // Balance of owner is 1, only service Id 2 belongs to the owner
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(false);
            expect(await serviceRegistry.exists(serviceIds[1])).to.equal(true);
            // Requesting for service 1 must revert with non existent service
            await expect(
                serviceRegistry.ownerOf(serviceIds[0])
            ).to.be.revertedWith("ERC721: owner query for nonexistent token");
            expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
            // Getting the set of service Ids of the owner, must be service Id 2 only
            serviceIdsRet = await serviceRegistry.balanceOf(owner);
            expect(await serviceRegistry.tokenOfOwnerByIndex(owner, 0)).to.equal(2);
        });

        it("Terminated service is unbonded", async function () {
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
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[0]],
                [agentIds[0]], {value: regBond});

            // Try to unbond when service is still in active registration
            await expect(
                serviceManager.connect(operator).serviceUnbond(serviceIds[0])
            ).to.be.revertedWith("WrongServiceState");

            // Registering the remaining agent instance
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstances[1]],
                [agentIds[0]], {value: regBond});

            // Terminate the service before it's deployed
            await serviceManager.connect(owner).serviceTerminate(serviceIds[0]);
            let state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(5);

            // Unbond agent instances. Since all the agents will eb unbonded, the service state is terminated-unbonded
            await serviceManager.connect(operator).serviceUnbond(serviceIds[0]);
            state = await serviceRegistry.getServiceState(serviceIds[0]);
            expect(state).to.equal(6);
        });

        it("Should fail when trying to update the terminated service is destroyed", async function () {
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
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(owner).serviceTerminate(serviceIds[0]);
            await serviceManager.connect(owner).serviceDestroy(serviceIds[0]);
            await expect(
                serviceManager.connect(owner).serviceUpdate(name, description, configHash, [1, 2, 3],
                    [[3, regBond], [0, regBond], [4, regBond]], maxThreshold, serviceIds[0])
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when registering an agent instance after the service is destroyed", async function () {
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
            await serviceManager.connect(owner).serviceDestroy(serviceIds[0]);
            await expect(
                serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstance], [1], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");
        });
    });

    context("Manipulations with payable set of functions or balance-related", async function () {
        it("Should revert when calling fallback and receive", async function () {
            const owner = signers[1];
            await expect(
                owner.sendTransaction({to: serviceManager.address, value: regBond})
            ).to.be.revertedWith("WrongFunction");

            await expect(
                owner.sendTransaction({to: serviceManager.address, value: regBond, data: "0x12"})
            ).to.be.revertedWith("WrongFunction");
        });

        it("Create a service, then deploy, slash, unbond", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7];
            await agentRegistry.changeManager(manager.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash1,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating a service and activating registration
            await serviceManager.serviceCreate(owner.address, name, description, configHash, [1], [[1, regBond]], 1);
            await serviceManager.connect(owner).serviceActivateRegistration(serviceIds[0], {value: regDeposit});

            // Registering agent instance
            await serviceManager.connect(operator).serviceRegisterAgents(serviceIds[0], [agentInstance.address],
                [agentIds[0]], {value: regBond});

            // Check the contract's initial balance
            const expectedContractBalance = regBond + regDeposit;
            const contractBalance = Number(await ethers.provider.getBalance(serviceRegistry.address));
            expect(contractBalance).to.equal(expectedContractBalance);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create multisig
            const safe = await serviceManager.connect(owner).serviceDeploy(serviceIds[0], gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;

            // Check initial operator's balance
            const balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator.address, serviceIds[0]));
            expect(balanceOperator).to.equal(regBond);

            // Get all the necessary info about multisig and slash the operator
            const multisig = await ethers.getContractAt("GnosisSafeL2", proxyAddress);
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(serviceRegistry, "slash",
                [[agentInstance.address], [regFine], serviceIds[0]], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(agentInstance, multisig, txHashData, 0);

            // Slash the agent instance operator with the correct multisig
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Check the new operator's balance, it must be the original balance minus the fine
            const newBalanceOperator = Number(await serviceRegistry.getOperatorBalance(operator.address, serviceIds[0]));
            expect(newBalanceOperator).to.equal(balanceOperator - regFine);

            // Terminate service and unbond the operator
            await serviceManager.connect(owner).serviceTerminate(serviceIds[0]);
            // Use the static call first that emulates the call, to get the return value of a refund
            const unbond = await serviceManager.connect(operator).callStatic.serviceUnbond(serviceIds[0]);
            // The refund for unbonding is the bond minus the fine
            expect(Number(unbond.refund)).to.equal(balanceOperator - regFine);

            // Do the real unbond call
            await serviceManager.connect(operator).serviceUnbond(serviceIds[0]);

            // Check the balance of the contract - it must be the total minus the slashed fine minus the deposit
            const newContractBalance = Number(await ethers.provider.getBalance(serviceRegistry.address));
            expect(newContractBalance).to.equal(contractBalance - regFine - regDeposit);
        });

        it("Reward a protocol-owned service", async function () {
            const somebody = signers[1];
            const manager = signers[2];
            const owner = signers[3];
            await agentRegistry.changeManager(manager.address);

            // Create an agent and a service
            await agentRegistry.connect(manager).create(owner.address, owner.address, componentHash,
                description, []);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.serviceCreate(owner.address, name, description, configHash, [1], [[1, regBond]], 1);

            // Should fail if nothing is sent
            await expect(
                serviceManager.connect(somebody).serviceReward(serviceIds[0])
            ).to.be.revertedWith("ZeroValue");

            // Should fail on a non-existent service
            await expect(
                serviceManager.connect(somebody).serviceReward(serviceIds[1], {value: regReward})
            ).to.be.revertedWith("ServiceDoesNotExist");

            // Should fail if trying to set the whitelisted owners with incorrect number of permissions set
            await expect(
                tokenomics.changeServiceOwnerWhiteList([owner.address], [true, false])
            ).to.be.revertedWith("WrongArrayLength");

            // Donate to a service (funds will be sent directly to the Treasury as a donation)
            await serviceManager.connect(somebody).serviceReward(serviceIds[0], {value: regReward});

            await tokenomics.changeServiceOwnerWhiteList([owner.address], [true]);
            // Deposit to a service as a protocol-owned service owner (funds will be counted towards rewards)
            const reward = await serviceManager.connect(somebody).serviceReward(serviceIds[0], {value: regReward});
            const result = await reward.wait();
            expect(result.events[1].event).to.equal("RewardService");
        });
    });
});

