/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MechMinter", function () {
    let componentRegistry;
    let agentRegistry;
    let mechMinter;
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const MechMinter = await ethers.getContractFactory("MechMinter");
        mechMinter = await MechMinter.deploy(componentRegistry.address, agentRegistry.address);
        await mechMinter.deployed();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await mechMinter.componentRegistry()).to.equal(componentRegistry.address);
            expect(await mechMinter.agentRegistry()).to.equal(agentRegistry.address);
        });
    });
});
