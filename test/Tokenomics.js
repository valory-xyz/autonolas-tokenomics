/*global describe, beforeEach, it, context, hre*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Tokenomics", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = "0x" + "0".repeat(40);
    const maxUint96 = "79228162514264337593543950335";
    const oneYear = 86400 * 365;
    const oneWeek = 86400 * 7;

    let signers;
    let deployer;
    let olas;
    let tokenomics;
    let treasury;
    let serviceRegistry;
    let componentRegistry;
    let agentRegistry;
    let donatorBlacklist;
    let tokenomicsFactory;
    let ve;
    let attacker;
    const epochLen = oneWeek;
    const regDepositFromServices = "1" + "0".repeat(25);
    const twoRegDepositFromServices = "2" + "0".repeat(25);
    const E18 = 10**18;
    let proxyData;
    let storageLayout = false;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        const olasFactory = await ethers.getContractFactory("ERC20Token");
        tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
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
        attacker = await Attacker.deploy(AddressZero, treasury.address);
        await attacker.deployed();

        // Voting Escrow mock
        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy();
        await ve.deployed();

        // Deploy master tokenomics contract
        const tokenomicsMaster = await tokenomicsFactory.deploy();
        await tokenomicsMaster.deployed();

        // deployer.address is given to the contracts that are irrelevant in these tests
        proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
            [olas.address, treasury.address, deployer.address, deployer.address, ve.address, epochLen,
                componentRegistry.address, agentRegistry.address, serviceRegistry.address, donatorBlacklist.address]);
        // Deploy tokenomics proxy based on the needed tokenomics initialization
        const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
        const tokenomicsProxy = await TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData);
        await tokenomicsProxy.deployed();

        // Get the tokenomics proxy contract
        tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxy.address);

        // Update tokenomics address for treasury
        await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero);

        // Mint the initial balance
        await olas.mint(deployer.address, initialMint);

        // Give treasury the minter role
        await olas.changeMinter(treasury.address);

        // Storage layout
        if (storageLayout) {
            // Make sure require('hardhat-storage-layout') is enabled in hardhat.confog.js
            await hre.storageLayout.export();
            // Let it run once
            storageLayout = false;
        }
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
                tokenomics.connect(account).changeManagers(AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Changing depository, dispenser and tokenomics addresses
            await tokenomics.connect(deployer).changeManagers(account.address, deployer.address, signers[2].address);
            expect(await tokenomics.treasury()).to.equal(account.address);
            expect(await tokenomics.depository()).to.equal(deployer.address);
            expect(await tokenomics.dispenser()).to.equal(signers[2].address);

            // Trying to change to zero addresses and making sure nothing has changed
            await tokenomics.connect(deployer).changeManagers(AddressZero, AddressZero, AddressZero);
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

        it("Should fail when the epoch length is smaller than the minimum required", async function () {
            // Deploy master tokenomics contract
            const tokenomicsMaster = await tokenomicsFactory.deploy();
            await tokenomicsMaster.deployed();

            // Try to deploy Tokenomics proxy
            const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, treasury.address, deployer.address, deployer.address, ve.address, 0,
                    componentRegistry.address, agentRegistry.address, serviceRegistry.address, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;
        });

        it("Should fail when at least one of the must-be-non-zero initialization contracts has a zero address", async function () {
            // Deploy master tokenomics contract
            const tokenomicsMaster = await tokenomicsFactory.deploy();
            await tokenomicsMaster.deployed();

            // Try to deploy Tokenomics proxy
            const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [AddressZero, AddressZero, AddressZero, AddressZero, AddressZero, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, AddressZero, AddressZero, AddressZero, AddressZero, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, AddressZero, AddressZero, AddressZero, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, deployer.address, AddressZero, AddressZero, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, deployer.address, deployer.address, AddressZero, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, deployer.address, deployer.address, deployer.address, epochLen,
                    AddressZero, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, deployer.address, deployer.address, deployer.address, epochLen,
                    deployer.address, AddressZero, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
                [olas.address, deployer.address, deployer.address, deployer.address, deployer.address, epochLen,
                    deployer.address, deployer.address, AddressZero, donatorBlacklist.address]);
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;
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
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const lessThanMinEpochLen = Number(await tokenomics.MIN_EPOCH_LENGTH()) - 1;
            // Trying to change tokenomics parameters from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeTokenomicsParameters(10, 10, epochLen * 2, 10, 10, 10)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Trying to set epoch length smaller than the minimum allowed value
            await tokenomics.changeTokenomicsParameters(10, 10, lessThanMinEpochLen, 10, 10, 10);
            // Move one epoch in time and finish the epoch
            await helpers.time.increase(epochLen + 100);
            await tokenomics.checkpoint();
            // Make sure the epoch lenght didn't change
            expect(await tokenomics.epochLen()).to.equal(epochLen);

            // Change epoch length to a bigger number
            await tokenomics.changeTokenomicsParameters(10, 10, epochLen * 2, 10, 10, 10);
            // The change will take effect in the next epoch
            expect(await tokenomics.epochLen()).to.equal(epochLen);
            // Move one epoch in time and finish the epoch
            await helpers.time.increase(epochLen + 100);
            await tokenomics.checkpoint();
            expect(await tokenomics.epochLen()).to.equal(epochLen * 2);

            // Change epoch len to a smaller value
            await tokenomics.changeTokenomicsParameters(10, 10, epochLen, 10, 10, 10);
            // The change will take effect in the next epoch
            expect(await tokenomics.epochLen()).to.equal(epochLen * 2);
            // Move one epoch in time and finish the epoch
            await helpers.time.increase(epochLen * 2 + 100);
            await tokenomics.checkpoint();
            expect(await tokenomics.epochLen()).to.equal(epochLen);

            // Leave the epoch length untouched
            await tokenomics.changeTokenomicsParameters(10, 10, epochLen, 10, 10, 10);
            // And then change back to the bigger one
            await tokenomics.changeTokenomicsParameters(10, 10, epochLen + 100, 10, 10, 10);
            // The change will take effect in the next epoch
            expect(await tokenomics.epochLen()).to.equal(epochLen);
            // Move one epoch in time and finish the epoch
            await helpers.time.increase(epochLen + 100);
            await tokenomics.checkpoint();
            expect(await tokenomics.epochLen()).to.equal(epochLen + 100);

            // Trying to set epsilonRate bigger than 17e18
            await tokenomics.changeTokenomicsParameters(0, "171"+"0".repeat(17), 0, 0, 0, 0);
            expect(await tokenomics.epsilonRate()).to.equal(10);

            // Trying to set all zeros
            await tokenomics.changeTokenomicsParameters(0, 0, 0, 0, 0, 0);
            // Check that parameters were not changed
            expect(await tokenomics.epsilonRate()).to.equal(10);
            expect(await tokenomics.epochLen()).to.equal(epochLen + 100);
            expect(await tokenomics.veOLASThreshold()).to.equal(10);

            // Get the current epoch counter
            const curPoint = Number(await tokenomics.epochCounter());
            // Get the epoch point of the current epoch
            const ep = await tokenomics.getEpochPoint(curPoint);
            expect(await ep.devsPerCapital).to.equal(10);
            const up = [await tokenomics.getUnitPoint(curPoint, 0), await tokenomics.getUnitPoint(curPoint, 1)];
            expect(up[0].unitWeight).to.equal(10);
            expect(up[1].unitWeight).to.equal(10);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Changing reward fractions", async function () {
            // Trying to change tokenomics reward fractions from a non-owner account address
            await expect(
                tokenomics.connect(signers[1]).changeIncentiveFractions(50, 50, 100, 0, 0)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // The sum of first 2 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 51, 100, 0, 0)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            // The sum of last 2 must not be bigger than 100
            await expect(
                tokenomics.connect(deployer).changeIncentiveFractions(50, 40, 50, 51, 0)
            ).to.be.revertedWithCustomError(tokenomics, "WrongAmount");

            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 50, 10);
            // Try to set exactly same values again
            await tokenomics.connect(deployer).changeIncentiveFractions(30, 40, 10, 50, 10);
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
                tokenomics.connect(signers[1]).trackServiceDonations(deployer.address, [], [], 0)
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });

        it("Should fail when calling dispenser-owned functions by other addresses", async function () {
            await expect(
                tokenomics.connect(signers[1]).accountOwnerIncentives(deployer.address, [], [])
            ).to.be.revertedWithCustomError(tokenomics, "ManagerOnly");
        });

        it("Should fail when calling initializer once again", async function () {
            await expect(
                tokenomics.initializeTokenomics(AddressZero, AddressZero, AddressZero, AddressZero, AddressZero, 0,
                    AddressZero, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(tokenomics, "AlreadyInitialized");
        });

        it("Should fail when initializing tokenomics later than one year after the OLAS launch", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Move past one year in time
            await helpers.time.increase(oneYear + 100);

            // Deploy master tokenomics contract
            const tokenomicsMaster = await tokenomicsFactory.deploy();

            // Try to deploy tokenomics proxy
            const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
            await expect(
                TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData)
            ).to.be.reverted;

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Track revenue of services", async function () {
        it("Should fail when the service does not exist", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(deployer.address, AddressZero, AddressZero);

            await expect(
                tokenomics.connect(deployer).trackServiceDonations(deployer.address, [3], [regDepositFromServices], 0)
            ).to.be.revertedWithCustomError(tokenomics, "ServiceDoesNotExist");
        });

        it("Send service revenues twice for protocol-owned services and donation", async () => {
            // Only treasury can access the function, so let's change it for deployer here
            await tokenomics.changeManagers(deployer.address, AddressZero, AddressZero);

            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [1, 2],
                [regDepositFromServices, regDepositFromServices], twoRegDepositFromServices);
            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [1], [regDepositFromServices],
                regDepositFromServices);
        });
    });

    context("Tokenomics calculation", async function () {
        it("Checkpoint without any revenues", async () => {
            // Skip the number of blocks within the epoch
            const epochCounter = await tokenomics.epochCounter();
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();
            let updatedEpochCounter = await tokenomics.epochCounter();
            expect(updatedEpochCounter).to.equal(epochCounter);

            // Try to run checkpoint while the epoch length is not yet reached
            await tokenomics.connect(deployer).checkpoint();
            updatedEpochCounter = await tokenomics.epochCounter();
            expect(updatedEpochCounter).to.equal(epochCounter);
        });

        it("Checkpoint with revenues", async () => {
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the UCF and check the values with delta rounding error
            const lastEpoch = await tokenomics.epochCounter() - 1;

            // Get IDF of the last epoch
            const idf = Number(await tokenomics.getIDF(lastEpoch)) / E18;
            expect(idf).to.greaterThan(0);
            
            // Get last IDF that must match the idf of the last epoch
            const lastIDF = Number(await tokenomics.getLastIDF()) / E18;
            expect(idf).to.equal(lastIDF);

            // Get IDF of the zero (arbitrary) epoch that has a zero IDF
            // By default, if IDF is not defined, it must be set to 1
            const zeroDF = Number(await tokenomics.getIDF(0));
            expect(zeroDF).to.equal(E18);
        });

        it("Checkpoint with inability to re-balance treasury rewards", async () => {
            // Change tokenomics factors such that all the rewards are given to the treasury
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 20, 50, 30);
            // Move more than one epoch in time and move to the next epoch
            await helpers.time.increase(epochLen + 10);
            await tokenomics.checkpoint();
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Change the manager for the treasury contract and re-balance treasury before the checkpoint
            await treasury.changeManagers(deployer.address, AddressZero, AddressZero);
            // After the treasury re-balance the ETHFromServices value will be equal to zero
            await treasury.rebalanceTreasury(twoRegDepositFromServices);
            // Change the manager for the treasury back to the tokenomics
            await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero);
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
            await helpers.time.increase(epochLen + 10);
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

            // Try to get incentives for non-existent components
            await expect(
                tokenomics.connect(deployer).getOwnerIncentives(deployer.address, [0], [0])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

            // Try to get and claim owner rewards with non-existent components bigget than the total supply
            await expect(
                tokenomics.getOwnerIncentives(deployer.address, [0, 0], [3, 4])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");
            await expect(
                tokenomics.connect(deployer).accountOwnerIncentives(deployer.address, [0, 0], [3, 4])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

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
            await tokenomics.connect(deployer).changeIncentiveFractions(60, 30, 40, 40, 20);

            // Check the case when the service was not yet deployed and component / agent Ids are not set up
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([100], [regDepositFromServices],
                    {value: regDepositFromServices})
            ).to.be.revertedWithCustomError(tokenomics, "ServiceNeverDeployed");

            const accounts = await serviceRegistry.getUnitOwners();
            // Send the revenues to services
            await treasury.connect(deployer).depositServiceDonationsETH(accounts, [regDepositFromServices,
                regDepositFromServices], {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);

            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.changeManagers(treasury.address, AddressZero, AddressZero);
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.getEpochPoint(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const rewards = [
                (Number(ep.totalDonationsETH) * Number(up[0].rewardUnitFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[1].rewardUnitFraction)) / 100
            ];
            const accountRewards = rewards[0] + rewards[1];
            // Calculate top-ups based on the points information
            let topUps = [
                (Number(ep.totalTopUpsOLAS) * Number(ep.maxBondFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[0].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[1].topUpUnitFraction)) / 100
            ];
            const accountTopUps = topUps[1] + topUps[2];
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Get owner rewards (mock registry has agent and component with Id 1)
            await tokenomics.getOwnerIncentives(accounts[0], [0, 1], [1, 1]);

            // Get the top-up number per epoch
            const topUp = await tokenomics.getInflationPerEpoch();
            expect(topUp).to.greaterThan(0);
        });

        it("Changing maxBond values", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const initEffectiveBond = ethers.BigNumber.from(await tokenomics.effectiveBond());
            const initMaxBond = initEffectiveBond;
            const initMaxBondFraction = (await tokenomics.mapEpochTokenomics(await tokenomics.epochCounter())).maxBondFraction;
            console.log(initMaxBondFraction);
            console.log("initMaxBond", Number(initMaxBond));

            // Changing maxBond fraction to 100%
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 100, 0, 0);
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            // Check that the next maxBond has been updated correctly in comparison with the initial one
            const nextMaxBondFraction = (await tokenomics.mapEpochTokenomics(await tokenomics.epochCounter())).maxBondFraction;
            expect(nextMaxBondFraction).to.equal(100);
            const nextMaxBond = ethers.BigNumber.from(await tokenomics.maxBond());
            console.log("nextMaxBond", Number(nextMaxBond));
            expect((nextMaxBond.div(nextMaxBondFraction)).mul(initMaxBondFraction)).to.equal(initMaxBond);

            //            const nextEffectiveBond = ethers.BigNumber.from(await tokenomics.effectiveBond());
            //            // Changing the epoch length to 10
            //            let epochLenFactor = 10;
            //            let newEpochLen = epochLen * epochLenFactor;
            //            await tokenomics.changeTokenomicsParameters(0, 0, newEpochLen, 0, 0, 0);
            //            // Increase the time and change the epoch
            //            await helpers.time.increase(epochLen + 100);
            //            await tokenomics.checkpoint();
            //
            //            let effectiveBond = ethers.BigNumber.from(await tokenomics.effectiveBond());
            //            // Verify that the effectiveBond increased by a factor of epochLenFactor
            //            expect(initEffectiveBond.add(initEffectiveBond.mul(epochLenFactor))).to.equal(effectiveBond);
            //            return;
            //
            //            // Reserve half of the effectiveBond
            //            const halfEffectiveBond = effectiveBond.div(2);
            //            await tokenomics.connect(deployer).reserveAmountForBondProgram(halfEffectiveBond);
            //
            //            // Check that the epoch length cannot be reduced by a half or more
            //            newEpochLen = newEpochLen / 2;
            //            await expect(
            //                tokenomics.connect(deployer).changeTokenomicsParameters(0, 0, newEpochLen, 0, 0, 0)
            //            ).to.be.revertedWithCustomError(tokenomics, "RejectMaxBondAdjustment");
            //
            //            // Check in a static call that the change on a bigger value is fine
            //            await tokenomics.connect(deployer).callStatic.changeTokenomicsParameters(0, 0, newEpochLen + 1, 0, 0, 0);
            //
            //            // Check that the maxBond fraction cannot be reduced by a half or more
            //            await expect(
            //                tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 50, 0, 0)
            //            ).to.be.revertedWithCustomError(tokenomics, "RejectMaxBondAdjustment");
            //
            //            // Check in a static call that the change on a bigger maxBond fraction value is fine
            //            await tokenomics.connect(deployer).callStatic.changeIncentiveFractions(0, 0, 51, 0, 0);
            //
            //            // Check that the reserve amount can go maximum to the effectiveBond == 0
            //            let result = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(halfEffectiveBond);
            //            expect(result).to.equal(true);
            //            result = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(halfEffectiveBond.add(1));
            //            expect(result).to.equal(false);
            //
            //            // Increase the epoch length by 10 (was x1, then x10, then x5 (not executed), now will be x15)
            //            newEpochLen += epochLen * 10;
            //            await tokenomics.connect(deployer).changeTokenomicsParameters(0, 0, newEpochLen, 0, 0, 0);
            //
            //            // Now we should be able to reserve of the amount of the effectiveBond, since we increased by half of the original
            //            // Since we reserved half, we can now go no lower than one third
            //            // EffectiveBond was 100, we reserved 50, it became 100 - 50 = 50. We then added 50 more. The effectiveBond is 100.
            //            // The total effectiveBond if we returned the reserved one would be 150. So we can reduce the effectiveBond
            //            // by a maximum of 100 out of 150, which is 66%.
            //            await expect(
            //                tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 33, 0, 0)
            //            ).to.be.revertedWithCustomError(tokenomics, "RejectMaxBondAdjustment");
            //            await tokenomics.connect(deployer).callStatic.changeIncentiveFractions(0, 0, 34, 0, 0);
            //
            //            // Since 50 was reserved, the maximum we can reserve now is 100 (out of 150), or the full effectiveBond
            //            result = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(effectiveBond);
            //            expect(result).to.equal(true);
            //            result = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(effectiveBond.add(1));
            //            expect(result).to.equal(false);

            snapshot.restore();
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
            await helpers.time.increase(10 * oneYear);
            allowed = await tokenomics.connect(deployer).callStatic.reserveAmountForBondProgram(1000);
            expect(allowed).to.equal(true);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Get to the epoch before the end of the OLAS year and try to change maxBond or epochLen", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // OLAS starting time
            const timeLaunch = Number(await tokenomics.timeLaunch());
            // One year time from the launch
            const yearChangeTime = timeLaunch + oneYear;

            // Get to the time of more than one epoch length before the year change (1.5 epoch length)
            let timeEpochBeforeYearChange = yearChangeTime - epochLen - epochLen / 2;
            await helpers.time.increaseTo(timeEpochBeforeYearChange);
            await tokenomics.checkpoint();

            let snapshotInternal = await helpers.takeSnapshot();
            // Try to change the epoch length now such that the next epoch will immediately have the year change
            await tokenomics.changeTokenomicsParameters(0, 0, 2 * epochLen, 0, 0, 0);
            // Move to the end of epoch and check the updated epoch length
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();
            expect(await tokenomics.epochLen()).to.equal(2 * epochLen);
            // Restore the state of the blockchain back to the time half of the epoch before one epoch left for the current year
            snapshotInternal.restore();

            // Get to the time of the half epoch length before the year change
            // Meaning that the year does not change yet during the current epoch, but it will during the next one
            timeEpochBeforeYearChange += epochLen;
            await helpers.time.increaseTo(timeEpochBeforeYearChange);
            await tokenomics.checkpoint();

            // The maxBond lock flag must be set to true, now try to change the epochLen
            await tokenomics.changeTokenomicsParameters(0, 0, epochLen + 100, 0, 0, 0);
            // Try to change the maxBondFraction as well
            await tokenomics.changeIncentiveFractions(30, 40, 60, 40, 0);

            // Now skip one epoch
            await helpers.time.increaseTo(timeEpochBeforeYearChange + epochLen);
            await tokenomics.checkpoint();
            expect(await tokenomics.epochLen()).to.equal(epochLen + 100);

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
            await tokenomics.changeManagers(deployer.address, AddressZero, AddressZero);
            // Able to receive donations when the blacklist if turned off
            await tokenomics.connect(deployer).trackServiceDonations(deployer.address, [], [], 0);

            // Change blacklist to a non-zero address
            await tokenomics.connect(deployer).changeDonatorBlacklist(donatorBlacklist.address);
            // Blacklist the deployer
            await donatorBlacklist.connect(deployer).setDonatorsStatuses([deployer.address], [true]);

            // Try to donate from the deployer address
            await expect(
                tokenomics.connect(deployer).trackServiceDonations(deployer.address, [], [], 0)
            ).to.be.revertedWithCustomError(tokenomics, "DonatorBlacklisted");
        });

        it("Reentrancy attack via a blacklist", async function () {
            // Change blacklist to the attacker address
            await tokenomics.connect(deployer).changeDonatorBlacklist(attacker.address);
            // Send some funds to the attacker
            await attacker.setAttackMode(false);
            await deployer.sendTransaction({to: attacker.address, value: ethers.utils.parseEther("2")});

            // Try to attack via a deposit function
            await expect(
                treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices,
                    regDepositFromServices], {value: twoRegDepositFromServices})
            ).to.be.revertedWithCustomError(tokenomics, "ReentrancyGuard");
        });
    });

    context("Proxy", async function () {
        it("Should fail when calling checkpoint not via the proxy", async function () {
            const tokenomicsMaster = await tokenomicsFactory.deploy();
            await expect(
                tokenomicsMaster.connect(deployer).checkpoint()
            ).to.be.revertedWithCustomError(tokenomics, "DelegatecallOnly");
        });

        it("Change tokenomics implementation", async function () {
            // Deploy another master tokenomics contract
            const tokenomicsMaster2 = await tokenomicsFactory.deploy();

            // Get the tokenomics contract
            const currentTokenomics = await tokenomics.tokenomicsImplementation();

            // Try to change to the new tokenomics not by the owner
            await expect(
                tokenomics.connect(signers[1]).changeTokenomicsImplementation(tokenomicsMaster2.address)
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Change the tokenomics implementation
            await tokenomics.connect(deployer).changeTokenomicsImplementation(tokenomicsMaster2.address);
            const newTokenomics = await tokenomics.tokenomicsImplementation();
            // The implementation now has to be different
            expect(newTokenomics).to.not.equal(currentTokenomics);
            expect(newTokenomics).to.equal(tokenomicsMaster2.address);
        });
    });
});
