/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MechRegistriesManager integration", function () {
    let componentRegistry;
    let agentRegistry;
    let registriesManager;
    let signers;
    const description = "component description";
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
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

        const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
        registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
        await registriesManager;
        signers = await ethers.getSigners();
    });

    context("Component creation via manager", async function () {
        it("Should fail when creating a component / agent without a manager being white listed", async function () {
            const user = signers[3];
            await expect(
                registriesManager.mintComponent(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("ManagerOnly");
            await expect(
                registriesManager.mintAgent(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("ManagerOnly");
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
            let compHash = componentHash;
            let agHash = componentHash;
            await registriesManager.mintComponent(user.address, user.address, compHash, description, []);
            agHash.hash = "0x1" + "0".repeat(63);
            await registriesManager.mintAgent(user.address, user.address, agHash, description, [1]);
            compHash.hash = "0x" + "0".repeat(63) + "1";
            await registriesManager.mintComponent(user.address, user.address, compHash, description, [1]);
            compHash.hash = "0x" + "0".repeat(63) + "2";
            await registriesManager.mintComponent(user.address, user.address, compHash, description, [1, 2]);
            agHash.hash = "0x2" + "0".repeat(63);
            await registriesManager.mintAgent(user.address, user.address, agHash, description, [1, 2]);
            compHash.hash = "0x" + "0".repeat(63) + "3";
            await registriesManager.mintComponent(user.address, user.address, compHash, description, [1, 3]);

            expect(await componentRegistry.balanceOf(user.address)).to.equal(4);
            expect(await componentRegistry.exists(3)).to.equal(true);
            expect(await componentRegistry.exists(5)).to.equal(false);

            expect(await agentRegistry.balanceOf(user.address)).to.equal(2);
            expect(await agentRegistry.exists(1)).to.equal(true);
            expect(await agentRegistry.exists(3)).to.equal(false);
        });
    });
});

