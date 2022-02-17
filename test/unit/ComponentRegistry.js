/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComponentRegistry", function () {
    let componentRegistry;
    let signers;
    const description = "component description";
    const componentHash = {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash1 = {hash: "0x" + "1".repeat(64), hashFunction: "0x12", size: "0x20"};
    const componentHash2 = {hash: "0x" + "2".repeat(64), hashFunction: "0x12", size: "0x20"};
    const dependencies = [];
    const AddressZero = "0x" + "0".repeat(40);
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
        it("Should fail when creating a component without a mechManager", async function () {
            const user = signers[2];
            await expect(
                componentRegistry.create(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("componentManager: MANAGER_ONLY");
        });

        it("Should fail when creating a component with a zero address of owner and / or developer", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(AddressZero, user.address, componentHash, description,
                    dependencies)
            ).to.be.revertedWith("create: ZERO_ADDRESS");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, AddressZero, componentHash, description,
                    dependencies)
            ).to.be.revertedWith("create: ZERO_ADDRESS");
            await expect(
                componentRegistry.connect(mechManager).create(AddressZero, AddressZero, componentHash, description,
                    dependencies)
            ).to.be.revertedWith("create: ZERO_ADDRESS");
        });

        it("Should fail when creating a component with a wrong IPFS hash header", async function () {
            const wrongComponentHashes = [{hash: "0x" + "0".repeat(64), hashFunction: "0x11", size: "0x20"},
                {hash: "0x" + "0".repeat(64), hashFunction: "0x12", size: "0x19"}];
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, wrongComponentHashes[0],
                    description, dependencies)
            ).to.be.revertedWith("checkHash: WRONG_HASH");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, wrongComponentHashes[1],
                    description, dependencies)
            ).to.be.revertedWith("checkHash: WRONG_HASH");
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
            ).to.be.revertedWith("checkHash: HASH_EXISTS");
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
            let compHash = componentHash;
            await componentRegistry.connect(mechManager).create(user.address, user.address, compHash, description, []);
            compHash.hash = "0x" + "0".repeat(63) + "1";
            await componentRegistry.connect(mechManager).create(user.address, user.address, compHash, description, [1]);
            compHash.hash = "0x" + "0".repeat(63) + "2";
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, compHash,
                    description, [1, 1, 1])
            ).to.be.revertedWith("create: WRONG_COMPONENT_ID");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, user.address, compHash,
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
                componentHash1, description, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash2, description + "2", lastDependencies);

            const compInfo = await componentRegistry.getInfo(tokenId);
            expect(compInfo.owner).to.equal(user.address);
            expect(compInfo.developer).to.equal(user.address);
            expect(compInfo.componentHash.hash).to.equal(componentHash2.hash);
            expect(compInfo.description).to.equal(description + "2");
            expect(compInfo.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(compInfo.dependencies[i]).to.equal(lastDependencies[i]);
            }
            await expect(
                componentRegistry.getInfo(tokenId + 1)
            ).to.be.revertedWith("getComponentInfo: NO_COMPONENT");
            
            const componentDependencies = await componentRegistry.getDependencies(tokenId);
            expect(componentDependencies.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(componentDependencies.dependencies[i]).to.equal(lastDependencies[i]);
            }
            await expect(
                componentRegistry.getDependencies(tokenId + 1)
            ).to.be.revertedWith("getDependencies: NO_COMPONENT");
        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the component does not belong to the owner or IPFS hash is invalid", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            await componentRegistry.connect(mechManager).create(user2.address, user2.address,
                componentHash1, description, dependencies);
            await expect(
                componentRegistry.connect(mechManager).updateHash(user2.address, 1, componentHash2)
            ).to.be.revertedWith("update: COMPONENT_NOT_FOUND");
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 2, componentHash2)
            ).to.be.revertedWith("update: COMPONENT_NOT_FOUND");
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);
        });

        it("Should fail when the updated hash already exists", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            await componentRegistry.connect(mechManager).create(user2.address, user2.address,
                componentHash1, description, dependencies);
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash1)
            ).to.be.revertedWith("checkHash: HASH_EXISTS");
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);
        });

        it("Should fail when getting hashes of non-existent component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);

            await expect(
                componentRegistry.getHashes(2)
            ).to.be.revertedWith("getHashes: NO_COMPONENT");
        });

        it("Update hash, get component hashes", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, user.address,
                componentHash, description, dependencies);
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash1);

            const hashes = await componentRegistry.getHashes(1);
            expect(hashes.numHashes).to.equal(2);
            expect(hashes.componentHashes[0].hash).to.equal(componentHash.hash);
            expect(hashes.componentHashes[1].hash).to.equal(componentHash1.hash);
        });
    });
});
