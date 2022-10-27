/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Tokenomics", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = "0x" + "0".repeat(40);
    const maxUint96 = "79228162514264337593543950335";
    const oneYear = 86400 * 365;

    let signers;
    let deployer;
    let olas;
    let tokenomics;
    let treasury;
    let serviceRegistry;
    let attacker;
    const epochLen = 1;
    const regDepositFromServices = "1" + "0".repeat(25);
    const twoRegDepositFromServices = "2" + "0".repeat(25);
    const E18 = 10**18;
    const delta = 1.0 / 10**10;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        const olasFactory = await ethers.getContractFactory("ERC20Token");
        const tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
        olas = await olasFactory.deploy();
        await olas.deployed();

        // Service registry mock
        const ServiceRegistry = await ethers.getContractFactory("MockRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();

        const componentRegistry = await ServiceRegistry.deploy();
        const agentRegistry = await ServiceRegistry.deploy();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, deployer.address, deployer.address, deployer.address);
        await treasury.deployed();

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(AddressZero, AddressZero);
        await attacker.deployed();

        // deployer.address is given to the contracts that are irrelevant in these tests
        tokenomics = await tokenomicsFactory.deploy(olas.address, treasury.address, deployer.address, deployer.address,
            deployer.address, epochLen, componentRegistry.address, agentRegistry.address, serviceRegistry.address);

        // Update tokenomics address for treasury
        await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero, AddressZero);

        // Mint the initial balance
        await olas.mint(deployer.address, initialMint);

        // Give treasury the minter role
        await olas.changeMinter(treasury.address);
    });

    context("Initialization", async function () {
        it("Changing managers and owners", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                tokenomics.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Trying to change owner to the zero address
            await expect(
                tokenomics.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "ZeroAddress");

            // Trying to change managers from a non-owner account address
            await expect(
                tokenomics.connect(account).changeManagers(AddressZero, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Changing depository, dispenser and tokenomics addresses
            await tokenomics.connect(deployer).changeManagers(AddressZero, account.address, deployer.address, signers[2].address);
            expect(await tokenomics.treasury()).to.equal(account.address);
            expect(await tokenomics.depository()).to.equal(deployer.address);
            expect(await tokenomics.dispenser()).to.equal(signers[2].address);

            // Changing the owner
            await tokenomics.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                tokenomics.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");
        });

        it("Get inflation numbers", async function () {
            const fiveYearSupplyCap = await tokenomics.getSupplyCapForYear(5);
            expect(fiveYearSupplyCap).to.equal("8718353429" + "0".repeat(17));

            const elevenYearSupplyCap = await tokenomics.getSupplyCapForYear(11);
            expect(elevenYearSupplyCap).to.equal("10404" + "0".repeat(23));

            const fiveYearInflationAmount = await tokenomics.getInflationForYear(5);
            expect(fiveYearInflationAmount).to.equal("488771339" + "0".repeat(17));

            const elevenYearInflationAmount = await tokenomics.getInflationForYear(11);
            expect(elevenYearInflationAmount).to.equal("204" + "0".repeat(23));
        });

        it("Changing tokenomics parameters", async function () {
            // Trying to change tokenomics parameters from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 10)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 10);
            // Change epoch len to a smaller value
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 1);
            // Leave the epoch length untouched
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 1);
            // And then change back to the bigger one
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 8);
            // Try to set the epochLen to zero that must fail due to effectiveBond going to zero
            await expect(
                tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 0)
            ).to.be.revertedWithCustomError(tokenomics, "RejectMaxBondAdjustment");

            // Trying to set epsilonRate bigger than 17e18
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, "171"+"0".repeat(17), 10);
            expect(await tokenomics.epsilonRate()).to.equal(10);
        });

        it("Changing reward fractions", async function () {
            // Trying to change tokenomics reward fractions from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeIncentiveFractions(50, 50, 50, 100, 0)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // The sum of first 3 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 50, 50, 100, 0)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            // The sum of last 2 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 40, 10, 50, 51)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 10, 50);
            // Try to set exactly same values again
            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 10, 50);
        });

        it("Changing registries addresses", async function () {
            // Trying to change tokenomics parameters from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeRegistries(AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Leaving everything unchanged
            await tokenomics.changeRegistries(AddressZero, AddressZero, AddressZero);
            // Change registries addresses
            await tokenomics.changeRegistries(signers[1].address, signers[2].address, signers[3].address);
            expect(await tokenomics.componentRegistry()).to.equal(signers[1].address);
            expect(await tokenomics.agentRegistry()).to.equal(signers[2].address);
            expect(await tokenomics.serviceRegistry()).to.equal(signers[3].address);
        });

        it("Should fail when calling depository-owned functions by other addresses", async function () {
            await expect(
                tokenomics.connect(signers[1]).reserveAmountForBondProgram(0)
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");

            await expect(
                tokenomics.connect(signers[1]).refundFromBondProgram(0)
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });

        it("Should fail when calling treasury-owned functions by other addresses", async function () {
            await expect(
                tokenomics.connect(signers[1]).trackServicesETHRevenue([], [])
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });

        it("Should fail when calling dispenser-owned functions by other addresses", async function () {
            await expect(
                tokenomics.connect(signers[1]).accountOwnerRewards(deployer.address)
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });
    });

    context("Track revenue of services", async function () {
        it("Should fail when the service does not exist", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(AddressZero, deployer.address, AddressZero, AddressZero);

            await expect(
                tokenomics.connect(deployer).trackServicesETHRevenue([3], [regDepositFromServices])
            ).to.be.revertedWithCustomError(tokenomics, "ServiceDoesNotExist");
        });

        it("Send service revenues twice for protocol-owned services and donation", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(AddressZero, deployer.address, AddressZero, AddressZero);

            await tokenomics.connect(deployer).trackServicesETHRevenue([1, 2], [regDepositFromServices, regDepositFromServices]);
            await tokenomics.connect(deployer).trackServicesETHRevenue([1], [regDepositFromServices]);
        });
    });

    context("Tokenomics calculation", async function () {
        it("Checkpoint without any revenues", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();

            // Try to run checkpoint while the epoch length is not yet reached
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 10);
            await tokenomics.connect(deployer).checkpoint();
        });

        it("Checkpoint with revenues", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices([1, 2], [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the UCF and check the values with delta rounding error
            const lastEpoch = await tokenomics.epochCounter() - 1;
            const ucf = Number(await tokenomics.getUCF(lastEpoch)) * 1.0 / E18;
            expect(Math.abs(ucf - 0.5)).to.lessThan(delta);
            // Get the epochs data
            // Get the very first point
            await tokenomics.getPoint(1);
            // Get the last point
            await tokenomics.getLastPoint();

            // Get IDF of the last epoch
            const idf = Number(await tokenomics.getIDF(lastEpoch)) / E18;
            expect(idf).to.greaterThan(1);
            
            // Get last IDF that must match the idf of the last epoch
            const lastIDF = Number(await tokenomics.getLastIDF()) / E18;
            expect(idf).to.equal(lastIDF);

            // Get IDF of the zero (arbitrary) epoch
            const defaultEpsRate = Number(await tokenomics.epsilonRate()) + E18;
            const zeroDF = Number(await tokenomics.getIDF(0));
            expect(zeroDF).to.equal(defaultEpsRate);

            // Get UCF of the zero (arbitrary) epoch
            const zeroUCF = Number(await tokenomics.getUCF(0));
            expect(zeroUCF).to.equal(0);

        });

        it("Get IDF based on the epsilonRate", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            const accounts = await serviceRegistry.getUnitOwners();
            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices(accounts, [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10, 10, 10, 10);
            await tokenomics.connect(deployer).checkpoint();

            // Get IDF
            const lastEpoch = await tokenomics.epochCounter() - 1;
            const idf = Number(await tokenomics.getIDF(lastEpoch)) / E18;
            expect(idf).to.greaterThan(Number(await tokenomics.epsilonRate()) / E18);
        });
    });

    context("Rewards", async function () {
        it("Calculate rewards", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            const accounts = await serviceRegistry.getUnitOwners();
            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices(accounts, [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});

            // Try to fail the reward allocation
            await tokenomics.changeManagers(AddressZero, attacker.address, AddressZero, AddressZero);
            await expect(
                tokenomics.connect(deployer).checkpoint()
            ).to.be.revertedWithCustomError(tokenomics, "RewardsAllocationFailed");

            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.changeManagers(AddressZero, treasury.address, AddressZero, AddressZero);
            await tokenomics.connect(deployer).checkpoint();
            // Get the rewards data
            const pe = await tokenomics.getLastPoint();
            const accountRewards = Number(pe.stakerRewards) + Number(pe.ucfc.unitRewards) + Number(pe.ucfa.unitRewards);
            const accountTopUps = Number(pe.ownerTopUps) + Number(pe.stakerTopUps);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Calculate staking rewards
            const result = await tokenomics.calculateStakingRewards(accounts[0], 1);
            // Get owner rewards
            await tokenomics.getOwnerRewards(accounts[0]);
            expect(result.endEpochNumber).to.equal(2);

            // Get the top-up number per epoch
            const topUp = await tokenomics.getTopUpPerEpoch();
            expect(topUp).to.greaterThan(0);
        });
    });

    context("Time sensitive tests", async function () {
        it("Check if the OLAS amount bond is available for the bond program", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Trying to get a new bond amount more than the inflation remainder for the year
            let allowed = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(maxUint96);
            expect(allowed).to.equal(false);

            allowed = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(1000);
            expect(allowed).to.equal(true);

            // Check the same condition after 10 years
            await helpers.time.increase(3153600000);
            allowed = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(1000);
            expect(allowed).to.equal(true);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Get to the epoch before the end of the OLAS year and try to change maxBond or epochLen", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Set epochLen to 10 seconds
            const currentEpochLen = 10;
            await tokenomics.changeTokenomicsParameters(1, 1, 1, 1, 1, 1, currentEpochLen);

            // OLAS starting time
            const timeLaunch = Number(await tokenomics.timeLaunch());
            // One year time from the launch
            const yearChangeTime = timeLaunch + Number(oneYear);

            // Get to the time of more than one epoch length before the year change (1.5 epoch length)
            let timeEpochBeforeYearChange = yearChangeTime - currentEpochLen - 5;
            await helpers.time.increaseTo(timeEpochBeforeYearChange);
            await tokenomics.checkpoint();
            // Try to change the epoch length now such that the next epoch will immediately have the year change
            await expect(
                tokenomics.changeTokenomicsParameters(1, 1, 1, 1, 1, 1, 20)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");

            // Get to the time of the half epoch length before the year change
            // Meaning that the year does not change yet during the current epoch, but it will during the next one
            timeEpochBeforeYearChange += currentEpochLen;
            await helpers.time.increaseTo(timeEpochBeforeYearChange);
            await tokenomics.checkpoint();

            // The maxBond lock flag must be set to true, now try to change the epochLen
            await expect(
                tokenomics.changeTokenomicsParameters(1, 1, 1, 1, 1, 1, 1)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");
            // Try to change the maxBondFraction as well
            await expect(
                tokenomics.changeIncentiveFractions(30, 40, 10, 50, 50)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");

            // Now skip one epoch
            await helpers.time.increaseTo(timeEpochBeforeYearChange + currentEpochLen);
            await tokenomics.checkpoint();

            // Change parameters now
            await tokenomics.changeTokenomicsParameters(1, 1, 1, 1, 1, 1, 1);
            await tokenomics.changeIncentiveFractions(30, 40, 10, 50, 50);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
