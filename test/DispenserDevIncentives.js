/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("DispenserDevIncentives", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const oneMonth = 86400 * 30;
    const maxNumClaimingEpochs = 10;
    const maxNumStakingTargets = 100;
    const retainer = "0x" + "5".repeat(64);

    let signers;
    let deployer;
    let olas;
    let tokenomics;
    let treasury;
    let dispenser;
    let ve;
    let serviceRegistry;
    let componentRegistry;
    let agentRegistry;
    let attacker;
    const epochLen = oneMonth;
    const regDepositFromServices = "1" + "0".repeat(21);
    const twoRegDepositFromServices = "2" + "0".repeat(21);
    const delta = 100;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        const olasFactory = await ethers.getContractFactory("ERC20Token");
        olas = await olasFactory.deploy();
        await olas.deployed();

        // Service registry mock
        const ServiceRegistry = await ethers.getContractFactory("MockRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();

        // Also deploye component and agent registries
        componentRegistry = await ServiceRegistry.deploy();
        agentRegistry = await ServiceRegistry.deploy();

        // Voting Escrow mock
        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy();
        await ve.deployed();

        const Dispenser = await ethers.getContractFactory("Dispenser");
        dispenser = await Dispenser.deploy(olas.address, deployer.address, deployer.address, deployer.address,
            retainer, maxNumClaimingEpochs, maxNumStakingTargets);
        await dispenser.deployed();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, deployer.address, deployer.address, dispenser.address);
        await treasury.deployed();

        // Update for the correct treasury contract
        await dispenser.changeManagers(AddressZero, treasury.address, AddressZero);

        const tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
        // Deploy master tokenomics contract
        const tokenomicsMaster = await tokenomicsFactory.deploy();
        await tokenomicsMaster.deployed();

        const proxyData = tokenomicsMaster.interface.encodeFunctionData("initializeTokenomics",
            [olas.address, treasury.address, deployer.address, dispenser.address, ve.address, epochLen,
                componentRegistry.address, agentRegistry.address, serviceRegistry.address, AddressZero]);
        // Deploy tokenomics proxy based on the needed tokenomics initialization
        const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
        const tokenomicsProxy = await TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData);
        await tokenomicsProxy.deployed();

        // Get the tokenomics proxy contract
        tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxy.address);

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(dispenser.address, treasury.address);
        await attacker.deployed();

        // Change the tokenomics and treasury addresses in the dispenser to correct ones
        await dispenser.changeManagers(tokenomics.address, treasury.address, AddressZero);

        // Update tokenomics address in treasury
        await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero);

        // Mint the initial balance
        await olas.mint(deployer.address, initialMint);

        // Give treasury the minter role
        await olas.changeMinter(treasury.address);
    });

    context("Initialization", async function () {
        it("Changing managers and owners", async function () {
            const account = signers[1];

            // Trying to change managers from a non-owner account address
            await expect(
                dispenser.connect(account).changeManagers(deployer.address, deployer.address, deployer.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Changing treasury, tokenomics and vote weighting addresses
            await dispenser.connect(deployer).changeManagers(deployer.address, deployer.address, deployer.address);
            expect(await dispenser.tokenomics()).to.equal(deployer.address);
            expect(await dispenser.treasury()).to.equal(deployer.address);
            expect(await dispenser.voteWeighting()).to.equal(deployer.address);

            // Trying to change to zero addresses and making sure nothing has changed
            await dispenser.connect(deployer).changeManagers(AddressZero, AddressZero, AddressZero);
            expect(await dispenser.tokenomics()).to.equal(deployer.address);
            expect(await dispenser.treasury()).to.equal(deployer.address);
            expect(await dispenser.voteWeighting()).to.equal(deployer.address);

            // Trying to change owner from a non-owner account address
            await expect(
                dispenser.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                dispenser.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");

            // Changing the owner
            await dispenser.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                dispenser.connect(deployer).changeOwner(account.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");
        });

        it("Should fail if deploying a dispenser with a zero address", async function () {
            const Dispenser = await ethers.getContractFactory("Dispenser");
            await expect(
                Dispenser.deploy(AddressZero, AddressZero, AddressZero, AddressZero, HashZero, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, AddressZero, AddressZero, AddressZero, HashZero, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, deployer.address, AddressZero, AddressZero, HashZero, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, deployer.address, deployer.address, AddressZero, HashZero, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, deployer.address, deployer.address, deployer.address, HashZero, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, deployer.address, deployer.address, deployer.address, retainer, 0, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");
            await expect(
                Dispenser.deploy(deployer.address, deployer.address, deployer.address, deployer.address, retainer, 10, 0)
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");
        });

        it("Should fail when trying to claim during the paused statke", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Try to claim when dev incentives are paused
            await dispenser.setPauseState(1);
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [])
            ).to.be.revertedWithCustomError(dispenser, "Paused");

            // Try to claim when all are paused
            await dispenser.setPauseState(3);
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [])
            ).to.be.revertedWithCustomError(dispenser, "Paused");

            // Try to claim when the treasury is paused
            await dispenser.setPauseState(0);
            await treasury.pause();
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [])
            ).to.be.revertedWithCustomError(treasury, "Paused");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Get incentives", async function () {
        it("Claim incentives for unit owners", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Try to claim empty incentives
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [])
            ).to.be.revertedWithCustomError(dispenser, "ClaimIncentivesFailed");

            // Try to claim incentives for non-existent components
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([0], [0])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

            // Skip the number of seconds for 2 epochs
            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();

            // Get tokenomcis parameters from the previous epoch
            let lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            let ep = await tokenomics.mapEpochTokenomics(lastPoint);
            expect(await tokenomics.devsPerCapital()).to.greaterThan(0);
            expect(ep.idf).to.greaterThan(0);
            // Get the unit points of the last epoch
            let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            expect(up[0].rewardUnitFraction + up[1].rewardUnitFraction + ep.rewardTreasuryFraction).to.equal(100);

            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});          

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Check for the incentive balances of component and agent such that their pending relative incentives are non-zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.greaterThan(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.greaterThan(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.greaterThan(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.greaterThan(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.lessThanOrEqual(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            expect(claimedTopUp).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners when donator and service owner are different accounts", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Try to claim empty incentives
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [])
            ).to.be.revertedWithCustomError(dispenser, "ClaimIncentivesFailed");

            // Try to claim incentives for non-existent components
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([0], [0])
            ).to.be.revertedWithCustomError(tokenomics, "WrongUnitId");

            // Skip the number of seconds for 2 epochs
            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();

            // Get tokenomcis parameters from the previous epoch
            let lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            let ep = await tokenomics.mapEpochTokenomics(lastPoint);
            expect(await tokenomics.devsPerCapital()).to.greaterThan(0);
            expect(ep.idf).to.greaterThan(0);
            // Get the unit points of the last epoch
            let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            expect(up[0].rewardUnitFraction + up[1].rewardUnitFraction + ep.rewardTreasuryFraction).to.equal(100);

            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(signers[1].address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Send donations to services
            await treasury.connect(signers[1]).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Check for the incentive balances of component and agent such that their pending relative incentives are non-zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.greaterThan(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.greaterThan(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.greaterThan(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.greaterThan(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.lessThanOrEqual(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            expect(claimedTopUp).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners for more than one epoch", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // EPOCH 1 with donations
            // Consider the scenario when no service owners lock enough OLAS for component / agent owners to claim top-ups

            // Increase the time to the length of the epoch
            await helpers.time.increase(epochLen + 10);
            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            let lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            let ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];

            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Get deployer incentives information
            let result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            // Since no service owners locked enough OLAS in veOLAS, there must be a zero top-up for owners
            expect(result.topUp).to.equal(0);
            // Get accumulated rewards and top-ups
            let checkedReward = ethers.BigNumber.from(result.reward);
            let checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            // Once again, the top-up of the owner must be zero here, since the owner of the service didn't stake enough veOLAS
            expect(checkedTopUp).to.equal(0);

            // EPOCH 2 with donations and top-ups
            // Return the ability for the service owner to have enough veOLAS for the owner top-ups
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Increase the time to more than the length of the epoch
            await helpers.time.increase(epochLen + 3);
            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and incentives
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Get deployer incentives information
            result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            checkedReward = ethers.BigNumber.from(result.reward);
            checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            // Since we didn't claim rewards during the previous epoch, the expected amount is twice as big
            expect(Math.abs(Number(ethers.BigNumber.from(2).mul(accountRewards).sub(checkedReward)))).to.lessThan(delta);
            // The top-ups were zero last time, so now we are getting top-ups for the second epoch only
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(Math.abs(Number(ethers.BigNumber.from(2).mul(accountRewards).sub(claimedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim accumulated incentives for unit owners for numerous epochs", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Skip the number of blocks for 2 epochs
            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();
            await helpers.time.increase(epochLen + 10);
            await tokenomics.connect(deployer).checkpoint();

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            let totalAccountTopUps = ethers.BigNumber.from(0);
            // Define the number of epochs
            const numEpochs = 20;
            const percentFraction = ethers.BigNumber.from(100);
            // Loop over a defined number of epochs
            for (let i = 0; i < numEpochs; i++) {
                // Increase the time to the length of the epoch plus a little more every time such that
                // OALS top-up numbers are not the same every epoch
                await helpers.time.increase(epochLen + i);
                // Send donations to services
                await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                    {value: twoRegDepositFromServices});
                // Start new epoch and calculate tokenomics parameters and rewards
                await tokenomics.connect(deployer).checkpoint();

                // Get the last settled epoch counter
                let lastPoint = Number(await tokenomics.epochCounter()) - 1;
                // Get the epoch point of the last epoch
                let ep = await tokenomics.mapEpochTokenomics(lastPoint);
                // Get the unit points of the last epoch
                let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
                // Calculate top-ups based on the points information
                let topUps = [
                    ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                    ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                    ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
                ];
                let accountTopUps = topUps[1].add(topUps[2]);
                totalAccountTopUps = totalAccountTopUps.add(accountTopUps);
            }

            let lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            let ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            let totalAccountRewards = accountRewards.mul(ethers.BigNumber.from(numEpochs));

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            // Static calls for incentive value returns
            const ownerReward = await dispenser.callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Real contract calls
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the ETH reward
            expect(Math.abs(Number(totalAccountRewards.sub(ownerReward.reward)))).to.lessThan(delta);

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(Math.abs(Number(totalAccountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners: component and agent reward fractions are zero", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Change the component and agent fractions to zero
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 40, 40, 20, 0);
            // Changes will take place in the next epoch, need to move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch
            await tokenomics.connect(deployer).checkpoint();

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.equal(0);
            expect(accountTopUps).to.greaterThan(0);

            // Check for the incentive balances of component and agent such that their pending rewards are zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.equal(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.greaterThan(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.equal(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.greaterThan(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.lessThanOrEqual(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            expect(claimedTopUp).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners: component incentive fractions are zero", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Change the component fractions to zero
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 100, 40, 0, 60, 0);
            // Changes will take place in the next epoch, need to move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch
            await tokenomics.connect(deployer).checkpoint();

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Check for the incentive balances such that pending relative incentives are zero for components
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.equal(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.equal(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.greaterThan(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.greaterThan(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.lessThanOrEqual(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            expect(claimedTopUp).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners: component and agent top-ups fractions are zero", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Change the component and agent to-up fractions to zero
            await tokenomics.connect(deployer).changeIncentiveFractions(50, 30, 100, 0, 0, 0);
            // Changes will take place in the next epoch, need to move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch
            await tokenomics.connect(deployer).checkpoint();

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.equal(0);

            // Check for the incentive balances of component and agent such that their pending relative top-ups are zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.greaterThan(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.equal(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.greaterThan(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.equal(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerIncentives([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.lessThanOrEqual(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            expect(claimedTopUp).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners: incentives are not zero at first, but then zero towards end of epoch", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Change the fractions such that rewards and top-ups are now zero. However, they will be updated for the next epoch only
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 100, 0, 0, 0);
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            let lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            let ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            let up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Check for the incentive balances such that their pending relative incentives are not zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.greaterThan(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.greaterThan(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.greaterThan(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.greaterThan(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1]);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Send donations to services for the next epoch where all the fractions are zero
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.equal(0);
            expect(accountTopUps).to.equal(0);

            // Try to claim rewards and top-ups for owners which are essentially zero as all the fractions were set to zero
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1])
            ).to.be.revertedWithCustomError(dispenser, "ClaimIncentivesFailed");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim incentives for unit owners: all incentive fractions are zero", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Change the fractions such that rewards and top-ups are not zero
            await tokenomics.connect(deployer).changeIncentiveFractions(0, 0, 100, 0, 0, 0);
            // Changes will take place in the next epoch, need to move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch
            await tokenomics.connect(deployer).checkpoint();

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const percentFraction = ethers.BigNumber.from(100);
            let rewards = [
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[0].rewardUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalDonationsETH).mul(ethers.BigNumber.from(up[1].rewardUnitFraction)).div(percentFraction)
            ];
            let accountRewards = rewards[0].add(rewards[1]);
            // Calculate top-ups based on the points information
            let topUps = [
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(ep.maxBondFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[0].topUpUnitFraction)).div(percentFraction),
                ethers.BigNumber.from(ep.totalTopUpsOLAS).mul(ethers.BigNumber.from(up[1].topUpUnitFraction)).div(percentFraction)
            ];
            let accountTopUps = topUps[1].add(topUps[2]);
            expect(accountRewards).to.equal(0);
            expect(accountTopUps).to.equal(0);

            // Check for the incentive balances such that their pending relative incentives are not zero
            let incentiveBalances = await tokenomics.mapUnitIncentives(0, 1);
            expect(Number(incentiveBalances.pendingRelativeReward)).to.equal(0);
            expect(Number(incentiveBalances.pendingRelativeTopUp)).to.equal(0);
            incentiveBalances = await tokenomics.mapUnitIncentives(1, 1);
            expect(incentiveBalances.pendingRelativeReward).to.equal(0);
            expect(incentiveBalances.pendingRelativeTopUp).to.equal(0);

            // Get deployer incentives information
            const result = await tokenomics.getOwnerIncentives(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = ethers.BigNumber.from(result.reward);
            const checkedTopUp = ethers.BigNumber.from(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(Math.abs(Number(accountRewards.sub(checkedReward)))).to.lessThan(delta);
            expect(Math.abs(Number(accountTopUps.sub(checkedTopUp)))).to.lessThan(delta);

            // Try to claim rewards and top-ups for owners when all the incentives are zeros
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([0, 1], [1, 1])
            ).to.be.revertedWithCustomError(dispenser, "ClaimIncentivesFailed");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Reentrancy attacks", async function () {
        it("Attacks on withdraw rewards for unit owners", async () => {
            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow for the attacker
            await ve.createLock(attacker.address);

            // Change the first service owner to the attacker (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, attacker.address);
            await componentRegistry.changeUnitOwner(1, attacker.address);
            await agentRegistry.changeUnitOwner(1, attacker.address);

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Move more than one epoch in time
            await helpers.time.increase(epochLen + 10);
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.mapEpochTokenomics(lastPoint);
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

            let result = await tokenomics.getOwnerIncentives(attacker.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            expect(result.topUp).to.greaterThan(0);

            // Failing on the receive call
            await expect(
                attacker.badClaimOwnerIncentives(false, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            await expect(
                attacker.badClaimOwnerIncentives(true, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(treasury, "TransferFailed");

            // The funds still remain on the protocol side
            result = await tokenomics.getOwnerIncentives(attacker.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            expect(result.topUp).to.greaterThan(0);
        });
    });
});
