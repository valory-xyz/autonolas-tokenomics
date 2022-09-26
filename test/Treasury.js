/*global describe, before, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Treasury", async () => {
    const LARGE_APPROVAL = "1" + "0".repeat(32);
    // const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    // Initial mint for Frax and DAI (10,000,000)
    const initialMint = "1" + "0".repeat(26);
    const defaultDeposit = "1" + "0".repeat(22);
    const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const AddressZero = "0x" + "0".repeat(40);

    let signers;
    let deployer;
    let erc20Token;
    let olasFactory;
    let treasuryFactory;
    let tokenomicsFactory;
    let dai;
    let olas;
    let treasury;
    let tokenomics;
    let attacker;
    const regDepositFromServices = "1" + "0".repeat(25);

    /**
     * Everything in this block is only run once before all tests.
     * This is the home for setup methodss
     */
    before(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // use dai as erc20 
        erc20Token = await ethers.getContractFactory("ERC20Token");
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        olasFactory = await ethers.getContractFactory("ERC20Token");
        treasuryFactory = await ethers.getContractFactory("Treasury");
        tokenomicsFactory = await ethers.getContractFactory("MockTokenomics");
    });

    // These should not be in beforeEach.
    beforeEach(async () => {
        dai = await erc20Token.deploy();
        olas = await olasFactory.deploy();
        tokenomics = await tokenomicsFactory.deploy();
        // Depository contract is irrelevant here, so we are using a deployer's address
        // Dispenser address is irrelevant in these tests, so we are using a deployer's address
        treasury = await treasuryFactory.deploy(olas.address, deployer.address, tokenomics.address, deployer.address);

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(AddressZero, treasury.address);
        await attacker.deployed();
        
        await dai.mint(deployer.address, initialMint);
        await dai.approve(treasury.address, LARGE_APPROVAL);
        await olas.changeMinter(treasury.address);

        // toggle DAI as reserve token (as example)
        await treasury.enableToken(dai.address);
    });

    context("Initialization", async function () {
        it("Changing managers and owners", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                treasury.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Changing tokenomics, depository and dispenser addresses
            await treasury.connect(deployer).changeManagers(signers[2].address, AddressZero, account.address, deployer.address);
            expect(await treasury.tokenomics()).to.equal(signers[2].address);
            expect(await treasury.depository()).to.equal(account.address);
            expect(await treasury.dispenser()).to.equal(deployer.address);

            // Changing the owner
            await treasury.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                treasury.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");
        });

        it("Disable and enable LP token", async () => {
            // Disable token that was never enabled does not break anything
            await treasury.disableToken(olas.address);

            // Try to enable the token not by the contract owner
            await expect(
                treasury.connect(signers[1]).enableToken(olas.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Enable the token
            await treasury.enableToken(olas.address);

            // Try to enable the same token
            await treasury.enableToken(olas.address);

            // Try to disable the token not by the contract owner
            await expect(
                treasury.connect(signers[1]).disableToken(dai.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Disable a token that was enabled
            await treasury.disableToken(dai.address);

            // Try to disable the same token again
            await treasury.disableToken(dai.address);

            // Re-enable the disabled token
            await treasury.enableToken(olas.address);
        });
    });

    context("Deposits LP tokens for OLAS", async function () {
        it("Deposit to the treasury from depository for OLAS", async () => {
            // Deposit 10,000 DAI to treasury,  1,000 OLAS gets minted to deployer with 9000 as excess reserves (ready to be minted)
            await treasury.connect(deployer).depositTokenForOLAS(defaultDeposit, dai.address, defaultDeposit);
            expect(await olas.totalSupply()).to.equal(defaultDeposit);
        });

        it("Should fail when trying to deposit for the unauthorized token", async () => {
            // Try to call the function not from depository
            await expect(
                treasury.connect(signers[1]).depositTokenForOLAS(defaultDeposit, olas.address, defaultDeposit)
            ).to.be.revertedWithCustomError(treasury, "ManagerOnly");
            // Now try with unauthorized token
            await expect(
                treasury.connect(deployer).depositTokenForOLAS(defaultDeposit, olas.address, defaultDeposit)
            ).to.be.revertedWithCustomError(treasury, "UnauthorizedToken");
        });

        it("Should fail when trying to deposit for the amount bigger than the inflation policy allows", async () => {
            await expect(
                treasury.connect(deployer).depositTokenForOLAS(defaultDeposit, dai.address, defaultDeposit.repeat(2))
            ).to.be.revertedWithCustomError(treasury, "MintRejectedByInflationPolicy");
        });

        it("Should fail when trying to disable an LP token that has reserves", async () => {
            // Try to disable token that has reserves
            await treasury.connect(deployer).depositTokenForOLAS(defaultDeposit, dai.address, defaultDeposit);
            await expect(
                treasury.disableToken(dai.address)
            ).to.be.revertedWithCustomError(treasury, "NonZeroValue");
        });
    });

    context("Deposits ETH from protocol-owned services", async function () {
        it("Should fail when depositing a zero value", async () => {
            await expect(
                treasury.connect(deployer).depositETHFromServices([], [])
            ).to.be.revertedWithCustomError(treasury, "ZeroValue");
        });

        it("Should fail when input arrays do not match", async () => {
            await expect(
                treasury.connect(deployer).depositETHFromServices([], [1], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "WrongArrayLength");
        });

        it("Should fail when the amount does not match the total input amount from services", async () => {
            await expect(
                treasury.connect(deployer).depositETHFromServices([1], [100], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "WrongAmount");
        });

        it("Should fail when the amount does not match the total input amount from services", async () => {
            await expect(
                treasury.connect(deployer).depositETHFromServices([1], [100], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "WrongAmount");
        });

        it("Deposit ETH from one protocol-owned service", async () => {
            await treasury.connect(deployer).depositETHFromServices([1], [regDepositFromServices], {value: regDepositFromServices});
        });
    });

    context("Withdraws", async function () {
        it("Withdraw specified LP tokens from reserves to a specified address", async () => {
            // Deposit
            await treasury.connect(deployer).depositTokenForOLAS(defaultDeposit + "0", dai.address, defaultDeposit);
            // Withdraw
            await treasury.connect(deployer).withdraw(deployer.address, defaultDeposit + "0", dai.address);
            // back to initialMint
            expect(await dai.balanceOf(deployer.address)).to.equal(initialMint);
        });

        it("Should fail when trying to withdraw from unauthorized token and owner", async () => {
            await treasury.connect(deployer).depositTokenForOLAS(defaultDeposit + "0", dai.address, defaultDeposit);

            await expect(
                treasury.connect(signers[1]).withdraw(deployer.address, defaultDeposit + "0", olas.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            await expect(
                treasury.connect(deployer).withdraw(deployer.address, defaultDeposit + "0", olas.address)
            ).to.be.revertedWithCustomError(treasury, "UnauthorizedToken");
        });

        it("Send ETH directly to treasury and withdraw", async () => {
            // Send ETH to treasury
            const amount = ethers.utils.parseEther("10");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Check the ETH balance of the reasury
            expect(await treasury.ETHOwned()).to.equal(amount);

            // Try to withdraw ETH to the address that cannot accept ETH
            await expect(
                treasury.withdraw(attacker.address, amount, ETHAddress)
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            // Withdraw ETH
            const success = await treasury.callStatic.withdraw(deployer.address, amount, ETHAddress);
            expect(success).to.equal(true);
        });
    });

    context("Allocate rewards", async function () {
        it("Start new epoch and allocate rewards", async () => {
            // Deposit ETH for protocol-owned services
            await treasury.connect(deployer).depositETHFromServices([1], [regDepositFromServices], {value: regDepositFromServices});

            // Try to allocate rewards not by the contract owner
            await expect(
                treasury.connect(signers[1]).allocateRewards()
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Try to allocate rewards to the dispenser that can't accept ETH
            await treasury.changeManagers(AddressZero, AddressZero, AddressZero, attacker.address);
            await expect(
                treasury.allocateRewards()
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            // Change the dispenser address back to the correct one
            await treasury.changeManagers(AddressZero, AddressZero, AddressZero, deployer.address);
            // Allocate rewards
            await treasury.connect(deployer).allocateRewards();
        });

        it("Limit the mint cap such that we can't mint more by the treasury to the dispenser", async () => {
            // Set the mint cap to be smaller than the possibility to mint for the year
            await tokenomics.changeMintCap(0);

            // Allocate empty rewards
            await treasury.connect(deployer).allocateRewards();

            // Deposit ETH for protocol-owned services
            await treasury.connect(deployer).depositETHFromServices([1], [regDepositFromServices], {value: regDepositFromServices});

            // Allocate rewards
            await treasury.connect(deployer).allocateRewards();
        });

        it("Allocate rewards with zero top-ups", async () => {
            // Change acount top-ups values
            await tokenomics.changeTopUps(0);

            // Allocate empty rewards
            await treasury.connect(deployer).allocateRewards();
        });
    });

    context("Reentrancy attacks", async function () {
        it("Proof that the attack is not possible via attacker's receive() function", async () => {
            // Send ETH to the attacker
            const amount = ethers.utils.parseEther("10");
            // Set attack mode to false to receive funds
            await attacker.setAttackMode(false);
            await deployer.sendTransaction({to: attacker.address, value: amount});

            // Try to attack via the deposit of ETH for protocol-owned services
            await attacker.setAttackMode(true);
            await attacker.badDepositETHFromServices([1], [regDepositFromServices], {value: regDepositFromServices});

            // Check that the attack did not succeed
            expect(await attacker.attackOnDepositETHFromServices()).to.equal(true);
        });
    });
});
