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
    const moreThanMaxUint96 = "79228162514264337593543950337";

    let signers;
    let deployer;
    let erc20Token;
    let olasFactory;
    let treasuryFactory;
    let tokenomicsFactory;
    let serviceRegistryFactory;
    let dai;
    let olas;
    let treasury;
    let tokenomics;
    let serviceRegistry;
    let attacker;
    const oneEther = "1" + "0".repeat(18);
    const regDepositFromServices = "1" + "0".repeat(25);
    const treasuryRewards = "1" + "0".repeat(19);
    const accountRewards = "5" + "0".repeat(19);
    const accountTopUps = "4" + "0".repeat(19);

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
        serviceRegistryFactory = await ethers.getContractFactory("MockRegistry");
    });

    // These should not be in beforeEach.
    beforeEach(async () => {
        dai = await erc20Token.deploy();
        olas = await olasFactory.deploy();
        tokenomics = await tokenomicsFactory.deploy();
        serviceRegistry = await serviceRegistryFactory.deploy();
        // Depository and dispenser addresses are irrelevant in these tests, so we are using a deployer's address
        treasury = await treasuryFactory.deploy(olas.address, tokenomics.address, deployer.address, deployer.address,
            {value: ethers.utils.parseEther("1")});

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(AddressZero, treasury.address);
        await attacker.deployed();
        
        await dai.mint(deployer.address, initialMint);
        await dai.approve(treasury.address, LARGE_APPROVAL);
        await dai.connect(deployer).approve(treasury.address, LARGE_APPROVAL);
        await olas.changeMinter(treasury.address);

        // toggle DAI as reserve token (as example)
        await treasury.enableToken(dai.address);
    });

    context("Initialization", async function () {
        it("Changing managers and owners", async function () {
            const account = signers[1];

            // Trying to change managers from a non-owner account address
            await expect(
                treasury.connect(account).changeManagers(signers[2].address, account.address, deployer.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Changing tokenomics, depository and dispenser addresses
            await treasury.connect(deployer).changeManagers(signers[2].address, account.address, deployer.address);
            expect(await treasury.tokenomics()).to.equal(signers[2].address);
            expect(await treasury.depository()).to.equal(account.address);
            expect(await treasury.dispenser()).to.equal(deployer.address);

            // Trying to change owner from a non-owner account address
            await expect(
                treasury.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                treasury.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");

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

        it("Changing minimal amount of received ETH", async function () {
            const account = signers[1];

            // Trying to change the value from a non-owner account address
            await expect(
                treasury.connect(account).changeMinAcceptedETH(0)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Trying to change the value to zero
            await expect(
                treasury.connect(deployer).changeMinAcceptedETH(0)
            ).to.be.revertedWithCustomError(treasury, "ZeroValue");

            // Trying to change the value to bigger than max uint96
            await expect(
                treasury.connect(deployer).changeMinAcceptedETH(moreThanMaxUint96)
            ).to.be.revertedWithCustomError(treasury, "Overflow");

            // Changing the min accepted ETH amount
            await treasury.connect(deployer).changeMinAcceptedETH(regDepositFromServices);
            expect(await treasury.minAcceptedETH()).to.equal(regDepositFromServices);
        });

        it("Should fail when trying to enable a zero address token", async () => {
            await expect(
                treasury.enableToken(AddressZero)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");
        });

        it("Should fail if deploying a contract with a zero address", async function () {
            const Treasury = await ethers.getContractFactory("Treasury");
            await expect(
                Treasury.deploy(AddressZero, deployer.address, deployer.address, deployer.address)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");
            await expect(
                Treasury.deploy(deployer.address, AddressZero, deployer.address, deployer.address)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");
            await expect(
                Treasury.deploy(deployer.address, deployer.address, AddressZero, deployer.address)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");
            await expect(
                Treasury.deploy(deployer.address, deployer.address, deployer.address, AddressZero)
            ).to.be.revertedWithCustomError(treasury, "ZeroAddress");
        });
    });

    context("Deposits LP tokens for OLAS", async function () {
        it("Deposit to the treasury from depository for OLAS", async () => {
            // Deposit 10,000 DAI to treasury, 1,000 OLAS gets minted to deployer with 9000 as excess reserves (ready to be minted)
            await treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit, dai.address, defaultDeposit);
            expect(await olas.totalSupply()).to.equal(defaultDeposit);
        });

        it("Should fail when trying to deposit for the unauthorized token", async () => {
            // Try to call the function not from depository
            await expect(
                treasury.connect(signers[1]).depositTokenForOLAS(deployer.address, defaultDeposit, olas.address, defaultDeposit)
            ).to.be.revertedWithCustomError(treasury, "ManagerOnly");
            // Now try with unauthorized token
            await expect(
                treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit, olas.address, defaultDeposit)
            ).to.be.revertedWithCustomError(treasury, "UnauthorizedToken");
        });

        it("Should fail when trying to disable an LP token that has reserves", async () => {
            // Try to disable token that has reserves
            await treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit, dai.address, defaultDeposit);
            await expect(
                treasury.disableToken(dai.address)
            ).to.be.revertedWithCustomError(treasury, "NonZeroValue");
        });

        it("Should fail when transferring a token that fails the transferFrom() function", async () => {
            treasury.enableToken(attacker.address);
            await expect(
                treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit, attacker.address, defaultDeposit)
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");
        });
    });

    context("Deposits ETH from protocol-owned services", async function () {
        it("Should fail when depositing a zero value", async () => {
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([], [])
            ).to.be.revertedWithCustomError(treasury, "LowerThan");
        });

        it("Should fail when input arrays do not match", async () => {
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([], [1], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "WrongArrayLength");
        });

        it("Should fail when the amount does not match the total donation amounts", async () => {
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([1], [100], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "WrongAmount");
        });

        it("Should fail when there is at least one zero donation amount passed", async () => {
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([1, 2], [100, 0], {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(treasury, "ZeroValue");
        });

        it("Deposit ETH from one protocol-owned service", async () => {
            await treasury.connect(deployer).depositServiceDonationsETH([1], [regDepositFromServices], {value: regDepositFromServices});
        });
    });

    context("Withdraws", async function () {
        it("Withdraw specified LP tokens from reserves to a specified address", async () => {
            // Deposit
            await treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit + "0", dai.address, defaultDeposit);
            // Withdraw
            await treasury.connect(deployer).withdraw(deployer.address, defaultDeposit + "0", dai.address);
            // back to initialMint
            expect(await dai.balanceOf(deployer.address)).to.equal(initialMint);
        });

        it("Should fail when trying to withdraw from unauthorized token and owner", async () => {
            await treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit + "0", dai.address, defaultDeposit);

            await expect(
                treasury.connect(signers[1]).withdraw(deployer.address, defaultDeposit + "0", olas.address)
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            await expect(
                treasury.connect(deployer).withdraw(deployer.address, defaultDeposit + "0", olas.address)
            ).to.be.revertedWithCustomError(treasury, "UnauthorizedToken");
        });

        it("Send ETH directly to treasury and withdraw", async () => {
            // Try to send insufficient ETH to treasury
            await expect(
                deployer.sendTransaction({to: treasury.address, value: 100})
            ).to.be.revertedWithCustomError(treasury, "LowerThan");

            // Try to send more than uint96.max ETH to treasury
            await expect(
                deployer.sendTransaction({to: treasury.address, value: moreThanMaxUint96})
            ).to.be.revertedWithCustomError(treasury, "Overflow");

            // Send ETH to treasury
            const initBalance = ethers.BigNumber.from(await ethers.provider.getBalance(treasury.address));
            const amount = ethers.utils.parseEther("10");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Check the ETH balance of the treasury
            const finalBalance = initBalance.add(ethers.BigNumber.from(amount));
            expect(await treasury.ETHOwned()).to.equal(finalBalance);

            // Try to withdraw to the treasury address itself
            await expect(
                treasury.withdraw(treasury.address, amount, ETHAddress)
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            // Try to withdraw ETH to the address that cannot accept ETH
            await expect(
                treasury.withdraw(attacker.address, amount, ETHAddress)
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            // Withdraw ETH
            const success = await treasury.callStatic.withdraw(deployer.address, amount, ETHAddress);
            expect(success).to.equal(true);
            // Call the non-static withdraw
            await treasury.withdraw(deployer.address, amount, ETHAddress);

            // Try to withdraw zero amount
            await expect(
                treasury.withdraw(deployer.address, 0, ETHAddress)
            ).to.be.revertedWithCustomError(treasury, "ZeroValue");

            // Try to withdraw more ETH amount than treasury owns
            let moreThanAmount = await treasury.ETHOwned() + "1";
            await expect(
                treasury.withdraw(deployer.address, moreThanAmount, ETHAddress)
            ).to.be.revertedWithCustomError(treasury, "LowerThan");

            // Try to withdraw other tokens that do not have balance
            moreThanAmount = await treasury.mapTokenReserves(dai.address) + "1";
            await expect(
                treasury.withdraw(deployer.address, moreThanAmount, dai.address)
            ).to.be.revertedWithCustomError(treasury, "LowerThan");
        });

        it("Should fail when transferring a token that fails to be transferred", async () => {
            treasury.enableToken(attacker.address);
            attacker.setTransfer(true);
            // Deposit the incorrectly working token
            await treasury.connect(deployer).depositTokenForOLAS(deployer.address, defaultDeposit, attacker.address, defaultDeposit);
            attacker.setTransfer(false);
            // Try to withdraw the token that fails
            await expect(
                treasury.connect(deployer).withdraw(deployer.address, defaultDeposit, attacker.address)
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");
        });
    });

    context("Account for rewards", async function () {
        it("Start new epoch and account for treasury rewards", async () => {
            // Try to deposit more ETH than uint96.max
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([1], [moreThanMaxUint96], {value: moreThanMaxUint96})
            ).to.be.revertedWithCustomError(treasury, "Overflow");

            // Deposit ETH for protocol-owned services
            await treasury.connect(deployer).depositServiceDonationsETH([1], [regDepositFromServices], {value: regDepositFromServices});

            // Try to re-balance treasury rewards not by the contract manager (tokenomics)
            await expect(
                treasury.connect(signers[1]).rebalanceTreasury(treasuryRewards)
            ).to.be.revertedWithCustomError(treasury, "ManagerOnly");

            // Change the dispenser address back to the correct one
            await treasury.changeManagers(deployer.address, AddressZero, deployer.address);
            // Re-balance treasury with treasury rewards
            await treasury.connect(deployer).rebalanceTreasury(treasuryRewards);
        });

        it("Re-balance treasury with zero treasury rewards", async () => {
            await treasury.changeManagers(deployer.address, AddressZero, AddressZero);
            await treasury.connect(deployer).rebalanceTreasury(0);
        });

        it("Try to re-balance treasury with treasury balance been lower", async () => {
            // Change the tokenomics manager to the deployer address
            await treasury.changeManagers(deployer.address, AddressZero, AddressZero);
            // Set the amount ofr re-balance
            const amount = treasuryRewards + "0";
            const ETHFromServices = await treasury.ETHFromServices();
            // Try to re-balance from ETH from services to ETH owned with more ETH amount than available
            const result = await treasury.connect(deployer).callStatic.rebalanceTreasury(amount);
            await treasury.connect(deployer).rebalanceTreasury(amount);
            // Treasury balance of ETH from services did not change
            expect(await treasury.ETHFromServices()).to.equal(ETHFromServices);
            expect(result).to.equal(false);
        });

        it("Try to withdraw to an account not by the dispenser request", async () => {
            // Change the dispenser address
            await treasury.changeManagers(deployer.address, AddressZero, signers[1].address);

            // Try to withdraw to the deployer account address not by the dispenser request
            await expect(
                treasury.withdrawToAccount(deployer.address, accountRewards, accountTopUps)
            ).to.be.revertedWithCustomError(treasury, "ManagerOnly");
        });

        it("Withdraw zero value incentives", async () => {
            // Change the dispenser address
            await treasury.changeManagers(deployer.address, AddressZero, deployer.address);

            // Zero rewards and top-ups
            let result = await treasury.connect(deployer).callStatic.withdrawToAccount(deployer.address, 0, 0);
            expect(result).to.equal(false);

            // Zero rewards, the amount will be minted
            result = await treasury.connect(deployer).callStatic.withdrawToAccount(deployer.address, 0, 10);
            expect(result).to.equal(true);

            // Zero top-ups, will fail since there is no ETHFromServices balance
            result = await treasury.connect(deployer).callStatic.withdrawToAccount(deployer.address, 10, 0);
            expect(result).to.equal(false);
        });
    });

    context("Drain slashed funds", async function () {
        it("Should fail if the drain amount is less than the minimum value received by the Treasury", async () => {
            // Set the service registry contract address to the tokenomics
            await tokenomics.setServiceRegistry(serviceRegistry.address);
            let amount = treasury.minAcceptedETH();
            await deployer.sendTransaction({to: serviceRegistry.address, value: amount});

            // Try to drain by the non-owner
            await expect(
                treasury.connect(signers[1]).drainServiceSlashedFunds()
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Drain slashed funds
            // Static call to get the return value, the simulated version returns 1/10th of the serviceRegistry balance,
            // which will be lower than the minimum accepted amount by the Treasury
            await expect(
                treasury.connect(deployer).callStatic.drainServiceSlashedFunds()
            ).to.be.revertedWithCustomError(treasury, "LowerThan");
        });

        it("Drain slashed funds from the service registry", async () => {
            // Set the service registry contract address to the tokenomics
            await tokenomics.setServiceRegistry(serviceRegistry.address);
            let amount = ethers.utils.parseEther("10");
            await deployer.sendTransaction({to: serviceRegistry.address, value: amount});

            // Try to drain by the non-owner
            await expect(
                treasury.connect(signers[1]).drainServiceSlashedFunds()
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Drain slashed funds
            // Static call to get the return value, the simulated version returns 1/10th of the serviceRegistry balance
            amount = await treasury.connect(deployer).callStatic.drainServiceSlashedFunds();
            expect(amount).to.equal(oneEther);
            // The real call
            await treasury.connect(deployer).drainServiceSlashedFunds();
        });
    });

    context("Pausing", async function () {
        it("Pause and unpause treasury", async () => {
            // Try to pause treasury not by the owner
            await expect(
                treasury.connect(signers[1]).pause()
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Try to unpause treasury not by the owner
            await expect(
                treasury.connect(signers[1]).unpause()
            ).to.be.revertedWithCustomError(treasury, "OwnerOnly");

            // Pause the contract
            await treasury.connect(deployer).pause();

            // Try to withdraw for an account
            await expect(
                treasury.connect(deployer).withdrawToAccount(deployer.address, 0, 0)
            ).to.be.revertedWithCustomError(treasury, "Paused");

            //
            await expect(
                treasury.connect(deployer).rebalanceTreasury(treasuryRewards)
            ).to.be.revertedWithCustomError(treasury, "Paused");

            // Unpause the contract
            await treasury.connect(deployer).unpause();
        });
    });
});
