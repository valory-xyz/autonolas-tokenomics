/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");

describe("Dispenser Merkle", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = "0x" + "0".repeat(40);
    const Bytes32Zero = "0x" + "0".repeat(64);
    const defaultHashIPSF = "0x" + "5".repeat(64);
    const oneMonth = 86400 * 30;

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

        const Dispenser = await ethers.getContractFactory("DispenserMerkle");
        dispenser = await Dispenser.deploy(deployer.address, deployer.address);
        await dispenser.deployed();

        const Treasury = await ethers.getContractFactory("TreasuryMerkle");
        treasury = await Treasury.deploy(olas.address, deployer.address, deployer.address, dispenser.address);
        await treasury.deployed();

        // Update for the correct treasury contract
        await dispenser.changeManagers(AddressZero, treasury.address);

        const tokenomicsFactory = await ethers.getContractFactory("TokenomicsMerkle");
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
        await dispenser.changeManagers(tokenomics.address, treasury.address);

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
                dispenser.connect(account).changeManagers(deployer.address, deployer.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Changing treasury and tokenomics addresses
            await dispenser.connect(deployer).changeManagers(deployer.address, deployer.address);
            expect(await dispenser.tokenomics()).to.equal(deployer.address);
            expect(await dispenser.treasury()).to.equal(deployer.address);

            // Trying to change to zero addresses and making sure nothing has changed
            await dispenser.connect(deployer).changeManagers(AddressZero, AddressZero);
            expect(await dispenser.tokenomics()).to.equal(deployer.address);
            expect(await dispenser.treasury()).to.equal(deployer.address);

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
                Dispenser.deploy(AddressZero, deployer.address)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            await expect(
                Dispenser.deploy(deployer.address, AddressZero)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
        });
    });

    context("Get incentives", async function () {
        it.only("Claim incentives for unit owners", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Try to claim empty incentives
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([], [], [[[]]], [])
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");

            // Try to claim incentives for non-existent components
            const zeroMultiProof = {merkleProof: [Bytes32Zero], proofFlags: [false]};
            await expect(
                dispenser.connect(deployer).claimOwnerIncentives([0], [0], [[[0, 0, 0]]], [zeroMultiProof])
            ).to.be.revertedWithCustomError(dispenser, "WrongUnitId");

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

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Create a donation Merkle tree
            // We have 2 services, each of them has 1 component and 1 agent
            // Divide donations between components and agents equally
            const amount = ethers.BigNumber.from(regDepositFromServices).div(2);
            const donations = [[[0, 1, amount], [1, 1, amount]], [[0, 1, amount], [1, 1, amount]]];
            const merkleTrees = new Array();
            merkleTrees.push(StandardMerkleTree.of(donations[0], ["uint256", "uint256", "uint256"]));
            merkleTrees.push(StandardMerkleTree.of(donations[1], ["uint256", "uint256", "uint256"]));

            // Send donations to services
            await treasury.connect(deployer).depositServiceDonationsETH([1, 2], [regDepositFromServices, regDepositFromServices],
                [merkleTrees[0].root, merkleTrees[1].root], [defaultHashIPSF, defaultHashIPSF], {value: twoRegDepositFromServices});

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

            // Claim incentives
            const roundIds = [0, 0];
            const serviceIds = [1, 2];
            // Each claim consists of a triplet: [unitType, unitId, amount]
            const claims = [
                [[donations[0][0][0], donations[0][0][1], donations[0][0][2]],
                    [donations[0][1][0], donations[0][1][1], donations[0][1][2]]],
                [[donations[1][0][0], donations[1][0][1], donations[1][0][2]],
                    [donations[1][1][0], donations[1][1][1], donations[1][1][2]]]
            ];
            const proofStructs = [merkleTrees[0].getMultiProof(donations[0]), merkleTrees[1].getMultiProof(donations[1])];
            const multiProofs = [{merkleProof: proofStructs[0].proof, proofFlags: proofStructs[0].proofFlags},
                {merkleProof: proofStructs[1].proof, proofFlags: proofStructs[1].proofFlags}];

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.callStatic.claimOwnerIncentives(roundIds, serviceIds, claims, multiProofs);
            // Get accumulated rewards and top-ups
            let claimedReward = ethers.BigNumber.from(claimedOwnerIncentives.reward);
            let claimedTopUp = ethers.BigNumber.from(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(claimedReward).to.equal(accountRewards);
            expect(Math.abs(Number(accountRewards.sub(claimedReward)))).to.lessThan(delta);
            //expect(claimedTopUp).to.equal(accountTopUps);
            //expect(Math.abs(Number(accountTopUps.sub(claimedTopUp)))).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));
            await dispenser.callStatic.claimOwnerIncentives(roundIds, serviceIds, claims, multiProofs);
            const balanceAfterTopUps = ethers.BigNumber.from(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = balanceAfterTopUps.sub(balanceBeforeTopUps);
            expect(balance).to.lessThanOrEqual(accountTopUps);
            //expect(balance).to.equal(accountTopUps);
            //expect(Math.abs(Number(accountTopUps.sub(balance)))).to.lessThan(delta);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Donate incentives for the service with a bigger number of units (gas estimation)", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock OLAS balances with Voting Escrow
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString());
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            const numUnits = 30;
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            for (let i = 1; i <= numUnits; i++) {
                await componentRegistry.changeUnitOwner(i, deployer.address);
                await agentRegistry.changeUnitOwner(i, deployer.address);
            }

            // Create a donation Merkle tree
            // We have 2 services, each of them has 1 component and 1 agent
            // Divide donations between components and agents equally
            const amount = ethers.BigNumber.from(regDepositFromServices).div(numUnits);
            const donations = new Array();
            for (let i = 1; i <= numUnits; i++) {
                donations.push([0, 1, amount]);
                donations.push([1, 1, amount]);
            }
            const merkleTree = StandardMerkleTree.of(donations, ["uint256", "uint256", "uint256"]);

            // Send donations to services
            const serviceId = await serviceRegistry.MORE_UNITS_SERVICE_ID();
            await treasury.connect(deployer).depositServiceDonationsETH([serviceId], [regDepositFromServices],
                [merkleTree.root], [defaultHashIPSF], {value: regDepositFromServices});

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

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
