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
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await componentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the minter from a different address", async function () {
            await expect(
                componentRegistry.connect(signers[1]).changeMinter(signers[1].address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    context("Component creation", async function () {
        const description = "component description";
        const componentHash = "0x0";
        const dependencies = [];
        it("Should fail when creating a component without a minter", async function () {
            const user = signers[2];
            await expect(
                componentRegistry.createComponent(user.address, user.address, componentHash, description, dependencies)
            ).to.be.revertedWith("Only the minter has a permission to create a component");
        });

        it("Should fail when creating a component with an empty hash", async function () {
            const minter = signers[1];
            const user = signers[2];
            await componentRegistry.changeMinter(minter.address);
            await expect(
                componentRegistry.connect(minter).createComponent(user.address, user.address, "", description,
                dependencies)
            ).to.be.revertedWith("Component hash can not be empty");
        });

        it("Should fail when creating a component with an empty description", async function () {
            const minter = signers[1];
            const user = signers[2];
            await componentRegistry.changeMinter(minter.address);
            await expect(
                componentRegistry.connect(minter).createComponent(user.address, user.address, componentHash, "",
                dependencies)
            ).to.be.revertedWith("Description can not be empty");
        });

        it("Should fail when creating a second component with the same hash", async function () {
            const minter = signers[1];
            const user = signers[2];
            await componentRegistry.changeMinter(minter.address);
            await componentRegistry.connect(minter).createComponent(user.address, user.address, componentHash,
                description, dependencies);
            await expect(
                componentRegistry.connect(minter).createComponent(user.address, user.address, componentHash,
                    description, dependencies)
            ).to.be.revertedWith("The component with this hash already exists!");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const minter = signers[1];
            const user = signers[2];
            await componentRegistry.changeMinter(minter.address);
            await expect(
                componentRegistry.connect(minter).createComponent(user.address, user.address, componentHash,
                    description, [0])
            ).to.be.revertedWith("The component does not exist!");
            await expect(
                componentRegistry.connect(minter).createComponent(user.address, user.address, componentHash,
                    description, [1])
            ).to.be.revertedWith("The component does not exist!");
        });

        it("Token Id=1 after first successful component creation must exist ", async function () {
            const minter = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await componentRegistry.changeMinter(minter.address);
            await componentRegistry.connect(minter).createComponent(user.address, user.address,
                componentHash, description, dependencies);
            const balance = await componentRegistry.balanceOf(user.address);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of a component", async function () {
            const minter = signers[1];
            const user = signers[2];
            await componentRegistry.changeMinter(minter.address);
            const component = await componentRegistry.connect(minter).createComponent(user.address, user.address,
                    componentHash, description, dependencies);
            const result = await component.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });
    });
});
