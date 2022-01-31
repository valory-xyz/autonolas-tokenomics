/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComponentRegistry", function () {
    let componentRegistry;
    let signers;
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await componentRegistry.name()).to.equal("agent components");
            expect(await componentRegistry.symbol()).to.equal("MECHCOMP");
            expect(await componentRegistry.getBaseURI()).to.equal("https://localhost/component/");
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await componentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the mechManager from a different address", async function () {
            await expect(
                componentRegistry.connect(signers[1]).changeManager(signers[1].address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("Setting the base URI", async function () {
            await componentRegistry.setBaseURI("https://localhost2/component/");
            expect(await componentRegistry.getBaseURI()).to.equal("https://localhost2/component/");
        });
    });

    context("Component creation", async function () {
        const description = "component description";
        const componentHash = "0x0";
        const dependencies = [];
        it("Should fail when creating a component without a mechManager", async function () {
            const user = signers[2];
            await expect(
                componentRegistry.create(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("create: MANAGER_ONLY");
        });

        it("Should fail when creating a component with an empty hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, "", description,
                    dependencies)
            ).to.be.revertedWith("create: EMPTY_HASH");
        });

        it("Should fail when creating a component with an empty description", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, componentHash, "",
                    dependencies)
            ).to.be.revertedWith("create: NO_DESCRIPTION");
        });

        it("Should fail when creating a second component with the same hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                description, dependencies);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, dependencies)
            ).to.be.revertedWith("create: HASH_EXISTS");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, [0])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, componentHash,
                    description, [1])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
        });

        it("Create a components with duplicate dependencies in the list of dependencies", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address, "componentHash 0",
                description, []);
            await componentRegistry.connect(mechManager).create(user.address, user.address, "componentHash 1",
                description, [1]);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, "componentHash 2",
                    description, [1, 1, 1])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, "componentHash 3",
                    description, [2, 1, 2, 1, 1, 1, 2])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
        });

        it("Token Id=1 after first successful component creation must exist", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of a component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            const component = await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            const result = await component.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting component info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 3;
            const lastDependencies = [1, 2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash + "1", description, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash + "2", description + "2", lastDependencies);
            const compInfo = await componentRegistry.getInfo(tokenId);
            expect(compInfo.developer == user.address);
            expect(compInfo.componentHash == componentHash + "2");
            expect(compInfo.description == description + "2");
            expect(compInfo.numDependencies == lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(compInfo.dependencies[i] == lastDependencies[i]);
            }
            await expect(
                componentRegistry.getInfo(tokenId + 1)
            ).to.be.revertedWith("getComponentInfo: NO_COMPONENT");
        });
    });
});
