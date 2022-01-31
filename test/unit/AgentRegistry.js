/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let signers;
    const description = "agent description";
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
    const dependencies = [];
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await agentRegistry.name()).to.equal("agent");
            expect(await agentRegistry.symbol()).to.equal("MECH");
            expect(await agentRegistry.getBaseURI()).to.equal("https://localhost/agent/");
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await agentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the mechManager from a different address", async function () {
            await expect(
                agentRegistry.connect(signers[1]).changeManager(signers[1].address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("Setting the base URI", async function () {
            await agentRegistry.setBaseURI("https://localhost2/agent/");
            expect(await agentRegistry.getBaseURI()).to.equal("https://localhost2/agent/");
        });
    });

    context("Agent creation", async function () {
        it("Should fail when creating an agent without a mechManager", async function () {
            const user = signers[2];
            await expect(
                agentRegistry.create(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("create: MANAGER_ONLY");
        });

        it("Should fail when creating an agent with a wrong IPFS hash header", async function () {
            const wrongComponentHashes = [{hash: "0x" + "0".repeat(64), hashFunction: "0x11", size: "0x20"},
                {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x19"}];
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, wrongComponentHashes[0],
                    description, dependencies)
            ).to.be.revertedWith("create: WRONG_HASH");
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, wrongComponentHashes[1],
                    description, dependencies)
            ).to.be.revertedWith("create: WRONG_HASH");
        });

        it("Should fail when creating an agent with an empty description", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, componentHash, "",
                    dependencies)
            ).to.be.revertedWith("create: NO_DESCRIPTION");
        });

        it("Should fail when creating a second agent with the same hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                description, dependencies);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, dependencies)
            ).to.be.revertedWith("create: HASH_EXISTS");
        });

        it("Should fail when component number is less or equal to zero", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, [0])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, [1])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
        });

        it("Token Id=1 after first successful agent creation must exist ", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await agentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of an agent", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            const agent = await agentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            const result = await agent.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting agent info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            const lastDependencies = [1, 2];
            await componentRegistry.changeManager(mechManager.address);
            await agentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash1, description, dependencies);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash2, description + "2", lastDependencies);
            const agentInfo = await agentRegistry.getInfo(tokenId);
            expect(agentInfo.developer == user.address);
            expect(agentInfo.componentHash == componentHash2);
            expect(agentInfo.description == description + "2");
            expect(agentInfo.numDependencies == lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(agentInfo.dependencies[i] == lastDependencies[i]);
            }
            await expect(
                agentRegistry.getInfo(tokenId + 1)
            ).to.be.revertedWith("getComponentInfo: NO_AGENT");
        });

        //        it("Should fail when creating an agent without a single component dependency", async function () {
        //            const mechManager = signers[1];
        //            const user = signers[2];
        //            await agentRegistry.changeManager(mechManager.address);
        //            await expect(
        //                agentRegistry.connect(mechManager).create(user.address, user.address, componentHash, description,
        //                dependencies)
        //            ).to.be.revertedWith("Agent must have at least one component dependency");
        //        });
    });
});
