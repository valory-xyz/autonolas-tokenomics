/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VotingEscrow", function () {
    let token;
    let ve;
    let signers;

    beforeEach(async function () {
        const Token = await ethers.getContractFactory("veOLA");
        token = await Token.deploy();
        await token.deployed();

        const VE = await ethers.getContractFactory("VotingEscrow");
        ve = await VE.deploy(token.address, "name", "symbol", "0.1");
        await ve.deployed();

        signers = await ethers.getSigners();
    });

    context("Basic functions", async function () {
        it("create lock", async function () {
            const owner = signers[0];
            await token.approve(ve.address, ethers.utils.parseEther("10"));
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + 7 * 86400; // 1 week

            // Balance should be zero before and 1 after creating the lock
            expect(await ve.balanceOf(owner.address)).to.equal(0);
            await ve.create_lock(ethers.utils.parseEther("1"), lockDuration);
            const balance = await ve.balanceOf(owner.address);
            console.log(balance);
        });
    });

    context("Time sensitive functions", async function () {
    });
});
