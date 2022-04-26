/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VotingEscrow", function () {
    let token;
    let ve;
    let dispenser;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;
    const oneETHBalance = ethers.utils.parseEther("1");
    const twoETHBalance = ethers.utils.parseEther("2");
    const tenETHBalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);

    beforeEach(async function () {
        const Token = await ethers.getContractFactory("OLA");
        token = await Token.deploy(0, AddressZero);
        await token.deployed();

        signers = await ethers.getSigners();
        await token.mint(signers[0].address, initialMint);

        const VE = await ethers.getContractFactory("VotingEscrow");
        ve = await VE.deploy(token.address, "name", "symbol", "0.1", signers[0].address);
        await ve.deployed();

        // Tokenomics and Treasury contract addresses are irrelevant for these tests
        const Dispenser = await ethers.getContractFactory("Dispenser");
        dispenser = await Dispenser.deploy(token.address, ve.address, AddressZero, AddressZero);
        await dispenser.deployed();
        await ve.changeDispenser(dispenser.address);
    });

    context("Locks", async function () {
        it("Should fail when creating a lock with zero value or wrong duration", async function () {
            await token.approve(ve.address, oneETHBalance);

            await expect(
                ve.createLock(0, 0)
            ).to.be.revertedWith("ZeroValue");

            await expect(
                ve.createLock(oneETHBalance, 0)
            ).to.be.revertedWith("UnlockTimeIncorrect");
        });

        it("Create lock", async function () {
            // Transfer 10 eth to signers[1]
            const owner = signers[1];
            await token.transfer(owner.address, tenETHBalance);

            // Approve signers[0] and signers[1] for 1eth by voting escrow
            await token.approve(ve.address, oneETHBalance);
            await token.connect(owner).approve(ve.address, oneETHBalance);

            // Define 1 week for the lock duration
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + 7 * 86400; // 1 week

            // Balance should be zero before the lock
            expect(await ve.getVotes(owner.address)).to.equal(0);
            await ve.createLock(oneETHBalance, lockDuration);
            await ve.connect(owner).createLock(oneETHBalance, lockDuration);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use the second address for locked funds to compare
            const balanceDeployer = await ve.getVotes(signers[0].address);
            const balanceOwner = await ve.getVotes(owner.address);
            expect(balanceDeployer > 0).to.be.true;
            expect(balanceDeployer).to.equal(balanceOwner);
        });

        it("Should fail when creating a lock for more than 4 years", async function () {
            const fourYears = 4 * 365 * oneWeek / 7;
            await token.approve(ve.address, oneETHBalance);

            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + fourYears + oneWeek; // 4 years and 1 week

            await expect(
                ve.createLock(oneETHBalance, lockDuration)
            ).to.be.revertedWith("MaxUnlockTimeReached");
        });

        it("Should fail when creating a lock with already locked value", async function () {
            await token.approve(ve.address, oneETHBalance);

            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + oneWeek;

            ve.createLock(oneETHBalance, lockDuration);
            await expect(
                ve.createLock(oneETHBalance, lockDuration)
            ).to.be.revertedWith("LockedValueNotZero");
        });

        it("Increase amount of lock", async function () {
            await token.approve(ve.address, tenETHBalance);

            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + oneWeek;

            // Should fail if requires are not satisfied
            // No previous lock
            await expect(
                ve.increaseAmount(oneETHBalance)
            ).to.be.revertedWith("NoValueLocked");

            // Now lock 1 eth
            ve.createLock(oneETHBalance, lockDuration);
            // Increase by more than a zero
            await expect(
                ve.increaseAmount(0)
            ).to.be.revertedWith("ZeroValue");

            // Add 1 eth more
            await ve.increaseAmount(oneETHBalance);

            // Time forward to the lock expiration
            ethers.provider.send("evm_increaseTime", [oneWeek]);
            ethers.provider.send("evm_mine");

            // Not possible to add to the expired lock
            await expect(
                ve.increaseAmount(oneETHBalance)
            ).to.be.revertedWith("LockExpired");
        });

        it("Increase amount of unlock time", async function () {
            await token.approve(ve.address, tenETHBalance);

            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + oneWeek;

            // Should fail if requires are not satisfied
            // Nothing is locked
            await expect(
                ve.increaseUnlockTime(oneWeek)
            ).to.be.revertedWith("NoValueLocked");

            // Lock 1 eth
            await ve.createLock(oneETHBalance, lockDuration);
            // Try to decrease the unlock time
            await expect(
                ve.increaseUnlockTime(lockDuration - 1)
            ).to.be.revertedWith("UnlockTimeIncorrect");

            await ve.increaseUnlockTime(lockDuration + oneWeek);

            // Time forward to the lock expiration
            ethers.provider.send("evm_increaseTime", [oneWeek + oneWeek]);
            ethers.provider.send("evm_mine");

            // Not possible to add to the expired lock
            await expect(
                ve.increaseUnlockTime(oneETHBalance)
            ).to.be.revertedWith("LockExpired");
        });
    });

    context("Withdraw", async function () {
        it("Withdraw", async function () {
            // Transfer 2 eth to signers[1] and approve the voting escrow for 1 eth
            const owner = signers[1];
            await token.transfer(owner.address, tenETHBalance);
            await token.connect(owner).approve(ve.address, oneETHBalance);

            // Lock 1 eth
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + oneWeek;
            await ve.connect(owner).createLock(oneETHBalance, lockDuration);

            // Try withdraw early
            await expect(ve.connect(owner).withdraw()).to.be.revertedWith("LockNotExpired");
            // Now try withdraw after the time has expired
            ethers.provider.send("evm_increaseTime", [oneWeek]);
            ethers.provider.send("evm_mine"); // mine the next block
            await ve.connect(owner).withdraw();
            expect(await token.balanceOf(owner.address)).to.equal(tenETHBalance);
        });
    });

    context("Balance and supply", async function () {
        it("Supply at", async function () {
            // Transfer 10 eth to signers[1]
            const owner = signers[1];
            await token.transfer(owner.address, tenETHBalance);

            // Approve signers[0] and signers[1] for 1eth by voting escrow
            await token.approve(ve.address, oneETHBalance);
            await token.connect(owner).approve(ve.address, tenETHBalance);

            // Initial total supply must be 0
            expect(await ve.totalSupply()).to.equal(0);

            // Define 1 week for the lock duration
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + 7 * 86400; // 1 week

            // Create locks for both addresses signers[0] and signers[1]
            await ve.createLock(oneETHBalance, lockDuration);
            await ve.connect(owner).createLock(twoETHBalance, lockDuration);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use both balances to check for the supply
            const balanceDeployer = await ve.getVotes(signers[0].address);
            const balanceOwner = await ve.getVotes(owner.address);
            const supply = await ve.totalSupplyLocked();
            const sumBalance = BigInt(balanceOwner) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());
        });
    });
});
