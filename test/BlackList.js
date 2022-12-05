/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("BlackList", async () => {
    const AddressZero = "0x" + "0".repeat(40);

    let signers;
    let deployer;
    let blackList;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const BlackList = await ethers.getContractFactory("BlackList");
        blackList = await BlackList.deploy();
        await blackList.deployed();
    });

    context("Initialization", async function () {
        it("Changing the owner", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                blackList.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(blackList, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                blackList.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(blackList, "ZeroAddress");

            // Changing the owner
            await blackList.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                blackList.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(blackList, "OwnerOnly");
        });
    });

    context("Blacklisting", async function () {
        it("Set account statuses", async function () {
            const account = signers[1];

            // Trying to set account statuses not by the owner
            await expect(
                blackList.connect(account).setAccountsStatuses([], [])
            ).to.be.revertedWithCustomError(blackList, "OwnerOnly");

            // Trying to set account statuses with incorrect arrays
            await expect(
                blackList.connect(deployer).setAccountsStatuses([deployer.address], [])
            ).to.be.revertedWithCustomError(blackList, "WrongArrayLength");

            // Trying to set account statuses with zero addresses
            await expect(
                blackList.connect(deployer).setAccountsStatuses([AddressZero], [true])
            ).to.be.revertedWithCustomError(blackList, "ZeroAddress");

            // Set account to be blacklisted
            await blackList.connect(deployer).setAccountsStatuses([deployer.address], [true]);

            // Check the blacklisting status
            expect(await blackList.isBlackListed(deployer.address)).to.equal(true);
        });
    });
});
