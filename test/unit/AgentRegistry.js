const { expect } = require("chai");
const { ethers } = require("hardhat");

//describe("AgentRegistry", function () {
//    let agentRegistry;
//    let signers;
//    beforeEach(async function () {
//        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
//        agentRegistry = await AgentRegistry.deploy("agent", "MECH",
//            "https://localhost/agent/");
//        await agentRegistry.deployed();
//        signers = await ethers.getSigners();
//    });
//
//    context("Initialization", async function () {
//        it("Checking for arguments passed to the constructor", async function () {
//            expect(await agentRegistry.name()).to.equal("agent");
//            expect(await agentRegistry.symbol()).to.equal("MECH");
//        });
//
//        it("Should fail when checking for the token id existence", async function () {
//            const tokenId = 0;
//            expect(await agentRegistry.exists(tokenId)).to.equal(false);
//        });
//
//        it("Should fail when trying to change the minter from a different address", async function () {
//            await expect(
//                agentRegistry.connect(signers[1]).changeMinter(signers[1].address)
//            ).to.be.revertedWith("Ownable: caller is not the owner");
//        });
//    });
//
//    context("Agent creation", async function () {
//        const description = "agent description";
//        const componentHash = "0x0";
//        const dependencies = [];
//        it("Should fail when creating an agent without a minter", async function () {
//            const user = signers[2];
//            await expect(
//                agentRegistry.createAgent(user.address, user.address, componentHash, description, dependencies)
//            ).to.be.revertedWith("Only the minter has a permission to create a agent");
//        });
//
//        it("Should fail when creating an agent with an empty hash", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            await agentRegistry.changeMinter(minter.address);
//            await expect(
//                agentRegistry.connect(minter).createAgent(user.address, user.address, "", description,
//                dependencies)
//            ).to.be.revertedWith("Agent hash can not be empty");
//        });
//
//        it("Should fail when creating a agent with an empty description", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            await agentRegistry.changeMinter(minter.address);
//            await expect(
//                agentRegistry.connect(minter).createAgent(user.address, user.address, componentHash, "",
//                dependencies)
//            ).to.be.revertedWith("Description can not be empty");
//        });
//
//        it("Should fail when creating a second agent with the same hash", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            await agentRegistry.changeMinter(minter.address);
//            await agentRegistry.connect(minter).createAgent(user.address, user.address, componentHash,
//                description, dependencies);
//            await expect(
//                agentRegistry.connect(minter).createAgent(user.address, user.address, componentHash,
//                    description, dependencies)
//            ).to.be.revertedWith("The agent with this hash already exists!");
//        });
//
//        it("Should fail when creating a non-existent component dependency", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            await agentRegistry.changeMinter(minter.address);
//            await expect(
//                agentRegistry.connect(minter).createAgent(user.address, user.address, componentHash,
//                    description, [0])
//            ).to.be.revertedWith("The component is not found!");
//            await expect(
//                agentRegistry.connect(minter).createAgent(user.address, user.address, componentHash,
//                    description, [1])
//            ).to.be.revertedWith("The agent does not exist!");
//        });
//
//        it("Token Id=1 after first successful agent creation must exist ", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            const tokenId = 1;
//            await agentRegistry.changeMinter(minter.address);
//            await agentRegistry.connect(minter).createAgent(user.address, user.address,
//                componentHash, description, dependencies);
//            const balance = await agentRegistry.balanceOf(user.address);
//            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
//            expect(await agentRegistry.exists(tokenId)).to.equal(true);
//        });
//
//        it("Catching \"Transfer\" event log after successful creation of an agent", async function () {
//            const minter = signers[1];
//            const user = signers[2];
//            await agentRegistry.changeMinter(minter.address);
//            const agent = await agentRegistry.connect(minter).createAgent(user.address, user.address,
//                    componentHash, description, dependencies);
//            const result = await agent.wait();
//            expect(result.events[0].event).to.equal("Transfer");
//        });
//    });
//});
