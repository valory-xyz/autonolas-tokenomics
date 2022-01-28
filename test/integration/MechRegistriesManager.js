/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MechRegistriesManager integration", function () {
    let componentRegistry;
    let agentRegistry;
    let registriesManager;
    let signers;
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
        registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
        await registriesManager;
        signers = await ethers.getSigners();
    });

    context("Component creation via manager", async function () {
        const description = "component description";
        const componentHash = "0x0";
        const dependencies = [];
        it("Should fail when creating a component / agent without a manager being white listed", async function () {
            const user = signers[3];
            await expect(
                registriesManager.mintComponent(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("create: MANAGER_ONLY");
            await expect(
                registriesManager.mintAgent(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("create: MANAGER_ONLY");
        });

        it("Token Id=1 after first successful component creation must exist", async function () {
            const user = signers[3];
            const tokenId = 1;
            await componentRegistry.changeManager(registriesManager.address);
            await registriesManager.mintComponent(user.address, user.address, componentHash, description, dependencies);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });
    });

    context("Several components and agents interaction", async function () {
        const description = "component description";
        it("Create components and agents", async function () {
            const user = signers[3];
            await componentRegistry.changeManager(registriesManager.address);
            await agentRegistry.changeManager(registriesManager.address);
            await registriesManager.mintComponent(user.address, user.address, "componentHash 0", description, []);
            await registriesManager.mintAgent(user.address, user.address, "agentHash 0", description, [1]);
            await registriesManager.mintComponent(user.address, user.address, "componentHash 1", description, [1]);
            await registriesManager.mintComponent(user.address, user.address, "componentHash 2", description, [1, 2]);
            await registriesManager.mintAgent(user.address, user.address, "agentHash 1", description, [1, 2]);
            await registriesManager.mintComponent(user.address, user.address, "componentHash 3", description, [1, 3]);

            expect(await componentRegistry.balanceOf(user.address)).to.equal(4);
            expect(await componentRegistry.exists(3)).to.equal(true);
            expect(await componentRegistry.exists(5)).to.equal(false);

            expect(await agentRegistry.balanceOf(user.address)).to.equal(2);
            expect(await agentRegistry.exists(1)).to.equal(true);
            expect(await agentRegistry.exists(3)).to.equal(false);
        });
    });
});

