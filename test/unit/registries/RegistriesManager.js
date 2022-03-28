/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RegistriesManager", function () {
    let componentRegistry;
    let agentRegistry;
    let registriesManager;
    let signers;
    const description = "description";
    const componentHashes = [{hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"}];
    const agentHashes = [{hash: "0x" + "5".repeat(64), hashFunction: "0x12", size: "0x20"},
        {hash: "0x" + "6".repeat(64), hashFunction: "0x12", size: "0x20"}];
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
        await registriesManager.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await registriesManager.componentRegistry()).to.equal(componentRegistry.address);
            expect(await registriesManager.agentRegistry()).to.equal(agentRegistry.address);
        });
    });

    context("Updating hashes", async function () {
        it("Update hash, get component hashes", async function () {
            const user = signers[1];
            await componentRegistry.changeManager(registriesManager.address);
            await agentRegistry.changeManager(registriesManager.address);
            await registriesManager.mintComponent(user.address, user.address, componentHashes[0], description,
                dependencies);
            await registriesManager.connect(user).updateComponentHash(1, componentHashes[1]);

            await registriesManager.mintAgent(user.address, user.address, agentHashes[0], description,
                dependencies);
            await registriesManager.connect(user).updateAgentHash(1, agentHashes[1]);

            const cHashes = await componentRegistry.getHashes(1);
            expect(cHashes.numHashes).to.equal(2);
            expect(cHashes.componentHashes[0].hash).to.equal(componentHashes[0].hash);
            expect(cHashes.componentHashes[1].hash).to.equal(componentHashes[1].hash);

            const aHashes = await agentRegistry.getHashes(1);
            expect(aHashes.numHashes).to.equal(2);
            expect(aHashes.agentHashes[0].hash).to.equal(agentHashes[0].hash);
            expect(aHashes.agentHashes[1].hash).to.equal(agentHashes[1].hash);
        });
    });
});
