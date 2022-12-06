/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Tokenomics with Staking", async () => {
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
    let componentRegistry;
    let agentRegistry;
    let donatorBlacklist;
    let ve;
    let attacker;
    const epochLen = 1;
    const regDepositFromServices = "1" + "0".repeat(25);
    const twoRegDepositFromServices = "2" + "0".repeat(25);
    const E18 = 10**18;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        const olasFactory = await ethers.getContractFactory("ERC20Token");
        const tokenomicsFactory = await ethers.getContractFactory("TokenomicsStaking");
        olas = await olasFactory.deploy();
        await olas.deployed();

        // Service registry mock
        const ServiceRegistry = await ethers.getContractFactory("MockRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();

        componentRegistry = await ServiceRegistry.deploy();
        agentRegistry = await ServiceRegistry.deploy();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, deployer.address, deployer.address, deployer.address);
        await treasury.deployed();

        const DonatorBlacklist = await ethers.getContractFactory("DonatorBlacklist");
        donatorBlacklist = await DonatorBlacklist.deploy();
        await donatorBlacklist.deployed();

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(AddressZero, AddressZero);
        await attacker.deployed();

        // Voting Escrow mock
        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy();
        await ve.deployed();

        // deployer.address is given to the contracts that are irrelevant in these tests
        tokenomics = await tokenomicsFactory.deploy();
        await tokenomics.initialize(olas.address, treasury.address, deployer.address, deployer.address,
            ve.address, epochLen, componentRegistry.address, agentRegistry.address, serviceRegistry.address, donatorBlacklist.address);

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
                tokenomics.connect(signers[1]).changeTokenomicsParameters(10, 10, 10, 10)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10);
            // Change epoch len to a smaller value
            await tokenomics.changeTokenomicsParameters(10, 10, 1, 10);
            // Leave the epoch length untouched
            await tokenomics.changeTokenomicsParameters(10, 10, 1, 10);
            // And then change back to the bigger one
            await tokenomics.changeTokenomicsParameters(10, 10, 8, 10);
            // Try to set the epochLen to a time where it fails due to effectiveBond going below zero
            // since part of the effectiveBond is already reserved
            await tokenomics.reserveAmountForBondProgram("1" + "0".repeat(18));
            await expect(
                tokenomics.changeTokenomicsParameters(10, 10, 1, 10)
            ).to.be.revertedWithCustomError(tokenomics, "RejectMaxBondAdjustment");

            // Trying to set epsilonRate bigger than 17e18
            await tokenomics.changeTokenomicsParameters(10, "171"+"0".repeat(17), 10, 10);
            expect(await tokenomics.epsilonRate()).to.equal(10);

            // Trying to set all zeros
            await tokenomics.changeTokenomicsParameters(0, 0, 0, 0);
            // Check that parameters were not changed
            expect(await tokenomics.epsilonRate()).to.equal(10);
            expect(await tokenomics.epochLen()).to.equal(10);
            expect(await tokenomics.veOLASThreshold()).to.equal(10);

            // Get the current epoch counter
            const curPoint = Number(await tokenomics.epochCounter());
            // Get the epoch point of the current epoch
            const ep = await tokenomics.getEpochPoint(curPoint);
            expect(await ep.devsPerCapital).to.equal(10);
        });

        it("Changing reward fractions", async function () {
            // Trying to change tokenomics reward fractions from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeIncentiveFractions(50, 50, 50, 100, 0, 0)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // The sum of first 3 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 50, 50, 100, 0, 0)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            // The sum of last 2 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 40, 10, 50, 51, 0)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 10, 50, 20);
            // Try to set exactly same values again
            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 10, 50, 20);
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
                tokenomics.connect(signers[1]).trackServiceDonations(deployer.address, [], [])
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });

        it("Should fail when calling dispenser-owned functions by other addresses", async function () {
            await expect(
                tokenomics.connect(signers[1]).accountOwnerIncentives(deployer.address, [], [])
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });
    });

    context("Track revenue of services", async function () {
        it("Should fail when the service does not exist", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(AddressZero, deployer.address, AddressZero, AddressZero);

            await expect(
                tokenomics.connect(deployer).trackServiceDonations(deployer.address, [3], [regDepositFromServices])
            ).to.be.revertedWithCustomError(tokenomics, "ServiceDoesNotExist");
        });

        it("Send service revenues twice for protocol-owned services and donation", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(AddressZero, deployer.address, AddressZero, AddressZero);

            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [1, 2], [regDepositFromServices, regDepositFromServices]);
            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [1], [regDepositFromServices]);
        });
    });

    context("Tokenomics calculation", async function () {
        it("Checkpoint without any revenues", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();

            // Try to run checkpoint while the epoch length is not yet reached
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10);
            await tokenomics.connect(deployer).checkpoint();
        });

        it("Checkpoint with revenues", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the UCF and check the values with delta rounding error
            const lastEpoch = await tokenomics.epochCounter() - 1;

            // Get IDF of the last epoch
            const idf = Number(await tokenomics.getIDF(lastEpoch)) / E18;
            expect(idf).to.greaterThan(1);
            
            // Get last IDF that must match the idf of the last epoch
            const lastIDF = Number(await tokenomics.getLastIDF()) / E18;
            expect(idf).to.equal(lastIDF);

            // Get IDF of the zero (arbitrary) epoch that has a zero IDF
            // By default, if IDF is not defined, it must be set to 1
            const zeroDF = Number(await tokenomics.getIDF(0));
            expect(zeroDF).to.equal(E18);
        });

        it("Checkpoint with inability to re-balance treasury rewards", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            // Change tokenomics factors such that all the rewards are given to the treasury
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 0, 10, 50, 20);
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Change the manager for the treasury contract and re-balance treasury before the checkpoint
            await treasury.changeManagers(deployer.address, AddressZero, AddressZero, AddressZero);
            // After the treasury re-balance the ETHFromServices value will be equal to zero
            await treasury.rebalanceTreasury(twoRegDepositFromServices);
            // Change the manager for the treasury back to the tokenomics
            await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero, AddressZero);
            // Start new epoch and calculate tokenomics parameters and rewards
            await expect(
                tokenomics.connect(deployer).checkpoint()
            ).to.be.revertedWithCustomError(tokenomics, "TreasuryRebalanceFailed");
        });

        it("Get IDF based on the epsilonRate", async () => {
            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            const accounts = await serviceRegistry.getUnitOwners();
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH(accounts, [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.changeTokenomicsParameters(10, 10, 10, 10);
            await helpers.time.increase(10);
            await tokenomics.connect(deployer).checkpoint();

            // Get IDF
            const lastEpoch = await tokenomics.epochCounter() - 1;
            const idf = Number(await tokenomics.getIDF(lastEpoch)) / E18;
            expect(idf).to.greaterThan(Number(await tokenomics.epsilonRate()) / E18);
        });
    });

    context("Incentives", async function () {
        it("Should fail when trying to get incentives with incorrect inputs", async () => {
            // Try to get and claim owner rewards with the wrong array length
            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [0], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongArrayLength");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongArrayLength");

            // Try to get and claim owner rewards while not being the owner of components / agents
            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Assign component and agent ownership to a deployer
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Try to get and claim owner rewards with incorrect unit type
            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [2, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "Overflow");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [2, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "Overflow");

            await componentRegistry.changeUnitOwner(2, deployer.address);
            await agentRegistry.changeUnitOwner(2, deployer.address);

            // Try to get incentives with the incorrect unit order
            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [0, 0, 1, 1], [2, 1, 1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0, 0, 1, 1], [2, 1, 1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [0, 0, 1, 1], [1, 2, 1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0, 0, 1, 1], [1, 2, 2, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

            await tokenomics.getOwnerIncentives(deployer.address, [0, 0, 1, 1], [1, 2, 1, 2]);
            await tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0, 0, 1, 1], [1, 2, 1, 2]);
        });

        it("Calculate incentives", async () => {
            // Change tokenomics factors such that the rewards are given to the treasury as well
            await tokenomics.connect(deployer).changeIncentiveFractions(50, 30, 15, 40, 34, 17);

            // Skip the number of blocks within the epoch
            await ethers.provider.send("evm_mine");
            const accounts = await serviceRegistry.getUnitOwners();
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH(accounts, [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});

            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.changeManagers(AddressZero, treasury.address, AddressZero, AddressZero);
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.getEpochPoint(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Get the staker point
            const sp = await tokenomics.mapEpochStakerPoints(lastPoint);
            // Calculate rewards based on the points information
            const rewards = [
                (Number(ep.totalDonationsETH) * Number(sp.rewardStakerFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[0].rewardUnitFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[1].rewardUnitFraction)) / 100
            ];
            const accountRewards = rewards[0] + rewards[1] + rewards[2];
            // Calculate top-ups based on the points information
            let topUps = [
                (Number(ep.totalTopUpsOLAS) * Number(ep.maxBondFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[0].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[1].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(sp.topUpStakerFraction)) / 100
            ];
            const accountTopUps = topUps[1] + topUps[2] + topUps[3];
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Calculate staking rewards
            const result = await tokenomics.getStakingIncentives(accounts[0], 1);
            // Get owner rewards (mock registry has agent and component with Id 1)
            await tokenomics.getOwnerIncentives(accounts[0], [0, 1], [1, 1]);
            expect(result.endEpochNumber).to.equal(2);

            // Get the top-up number per epoch
            const topUp = await tokenomics.getInflationPerEpoch();
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
            await tokenomics.changeTokenomicsParameters(1, 1, currentEpochLen, 1);

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
                tokenomics.changeTokenomicsParameters(1, 1, 20, 1)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");

            // Get to the time of the half epoch length before the year change
            // Meaning that the year does not change yet during the current epoch, but it will during the next one
            timeEpochBeforeYearChange += currentEpochLen;
            await helpers.time.increaseTo(timeEpochBeforeYearChange);
            await tokenomics.checkpoint();

            // The maxBond lock flag must be set to true, now try to change the epochLen
            await expect(
                tokenomics.changeTokenomicsParameters(1, 1, 1, 1)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");
            // Try to change the maxBondFraction as well
            await expect(
                tokenomics.changeIncentiveFractions(30, 40, 10, 60, 40, 0)
            ).to.be.revertedWithCustomError(tokenomics, "MaxBondUpdateLocked");

            // Now skip one epoch
            await helpers.time.increaseTo(timeEpochBeforeYearChange + currentEpochLen);
            await tokenomics.checkpoint();

            // Change parameters now
            await tokenomics.changeTokenomicsParameters(1, 1, 1, 1);
            await tokenomics.changeIncentiveFractions(30, 40, 10, 50, 50, 0);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Blacklist usage", async function () {
        it("Change blacklist address", async function () {
            // Try to change not by the owner
            await expect(
                tokenomics.connect(signers[1]).changeDonatorBlacklist(AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Change blacklist to a different address
            await tokenomics.connect(deployer).changeDonatorBlacklist(signers[1].address);
            expect(await tokenomics.donatorBlacklist()).to.equal(signers[1].address);

            // Change blacklist to a zero address (turn it off)
            await tokenomics.connect(deployer).changeDonatorBlacklist(AddressZero);
            expect(await tokenomics.donatorBlacklist()).to.equal(AddressZero);
        });

        it("Deposit donations with the blacklist", async function () {
            // Change blacklist to a zero address (turn it off)
            await tokenomics.connect(deployer).changeDonatorBlacklist(AddressZero);
            expect(await tokenomics.donatorBlacklist()).to.equal(AddressZero);

            // Change the treasury address to deployer
            await tokenomics.changeManagers(AddressZero, deployer.address, AddressZero, AddressZero);
            // Able to receive donations when the blacklist if turned off
            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [], []);

            // Change blacklist to a non-zero address
            await tokenomics.connect(deployer).changeDonatorBlacklist(donatorBlacklist.address);
            // Blacklist the deployer
            await donatorBlacklist.connect(deployer).setDonatorsStatuses([deployer.address], [true]);

            // Try to donate from the deployer address
            await expect(
                tokenomics.connect(deployer).trackServiceDonations(deployer.address, [], [])
            ).to.be.revertedWithCustomError(tokenomics, "DonatorBlacklisted");
        });
    });
});
