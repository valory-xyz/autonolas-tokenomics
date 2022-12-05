/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Donator Blacklist", async () => {
    const AddressZero = "0x" + "0".repeat(40);

    let signers;
    let deployer;
    let donatorBlacklist;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const DonatorBlacklist = await ethers.getContractFactory("DonatorBlacklist");
        donatorBlacklist = await DonatorBlacklist.deploy();
        await donatorBlacklist.deployed();
    });

    context("Initialization", async function () {
        it("Changing the owner", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                donatorBlacklist.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(donatorBlacklist, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                donatorBlacklist.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(donatorBlacklist, "ZeroAddress");

            // Changing the owner
            await donatorBlacklist.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                donatorBlacklist.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(donatorBlacklist, "OwnerOnly");
        });
    });

    context("Blacklisting", async function () {
        it("Set account statuses", async function () {
            const account = signers[1];

            // Trying to set account statuses not by the owner
            await expect(
                donatorBlacklist.connect(account).setDonatorsStatuses([], [])
            ).to.be.revertedWithCustomError(donatorBlacklist, "OwnerOnly");

            // Trying to set account statuses with incorrect arrays
            await expect(
                donatorBlacklist.connect(deployer).setDonatorsStatuses([deployer.address], [])
            ).to.be.revertedWithCustomError(donatorBlacklist, "WrongArrayLength");

            // Trying to set account statuses with zero addresses
            await expect(
                donatorBlacklist.connect(deployer).setDonatorsStatuses([AddressZero], [true])
            ).to.be.revertedWithCustomError(donatorBlacklist, "ZeroAddress");

            // Set account to be blacklisted
            await donatorBlacklist.connect(deployer).setDonatorsStatuses([deployer.address], [true]);

            // Check the blacklisting status
            expect(await donatorBlacklist.isDonatorBlacklisted(deployer.address)).to.equal(true);
        });
    });
});
