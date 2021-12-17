const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MechMinter", function () {
    let componentRegistry;
    let agentRegistry;
    let mechMinter;
    let signers;
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await ComponentRegistry.deploy("agent", "MECH", "https://localhost/agent/");
        await agentRegistry.deployed();

        const MechMinter = await ethers.getContractFactory("MechMinter");
        mechMinter = await MechMinter.deploy(componentRegistry.address, agentRegistry.address, "mech minter",
            "MECHMINTER");
        await mechMinter;
        signers = await ethers.getSigners();
    });

    context("Component creation via minter", async function () {
        const description = "component description";
        const componentHash = "0x0";
        const dependencies = [];

        it("Token Id=1 after first successful component creation must exist ", async function () {
            const user = signers[3];
            const tokenId = 1;
            await componentRegistry.changeMinter(mechMinter.address);
            await mechMinter.mintComponent(user.address, user.address, componentHash, description, dependencies);
            const balance = await componentRegistry.balanceOf(user.address);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of a component", async function () {
            const user = signers[3];
            await componentRegistry.changeMinter(mechMinter.address);
            const component = await mechMinter.mintComponent(user.address, user.address,
                    componentHash, description, dependencies);
            const result = await component.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });
    });
});

