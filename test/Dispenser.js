/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Dispenser", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = "0x" + "0".repeat(40);

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
    const epochLen = 1;
    const regDepositFromServices = "1" + "0".repeat(21);
    const twoRegDepositFromServices = "2" + "0".repeat(21);
    const delta = 10**5;

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
        dispenser = await Dispenser.deploy(olas.address, deployer.address);
        await dispenser.deployed();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, deployer.address, deployer.address, dispenser.address);
        await treasury.deployed();

        // Treasury address is deployer since there are functions that require treasury only
        const tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
        tokenomics = await tokenomicsFactory.deploy(olas.address, treasury.address, deployer.address, dispenser.address,
            ve.address, epochLen, componentRegistry.address, agentRegistry.address, serviceRegistry.address);

        const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
        attacker = await Attacker.deploy(dispenser.address, treasury.address);
        await attacker.deployed();

        // Change the tokenomics address in the dispenser to the correct one
        await dispenser.changeManagers(tokenomics.address, AddressZero, AddressZero, AddressZero);

        // Update tokenomics address in treasury
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
                dispenser.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Changing treasury and tokenomics addresses
            await dispenser.connect(deployer).changeManagers(deployer.address, AddressZero, AddressZero, AddressZero);
            expect(await dispenser.tokenomics()).to.equal(deployer.address);

            // Changing the owner
            await dispenser.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                dispenser.connect(deployer).changeOwner(account.address)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");
        });
    });

    context("Get incentives", async function () {
        it("Withdraw incentives for unit owners and stakers", async () => {
            // Try to claim rewards
            await dispenser.connect(deployer).claimOwnerRewards([], []);
            await dispenser.connect(deployer).claimStakingRewards();

            // Skip the number of blocks for 2 epochs
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();

            // Calculate staking rewards with zero balances and total supply
            await ve.setBalance(0);
            await ve.setSupply(0);
            await tokenomics.calculateStakingRewards(deployer.address, 1);
            // Set the voting escrow value back
            await ve.setBalance(ethers.utils.parseEther("100"));
            // Calculate with a balance and no total supply (although not realistic)
            await tokenomics.calculateStakingRewards(deployer.address, 1);
            // Set the total supply the same as the balance, such that the full amount of incentives is given to one locker
            await ve.setSupply(ethers.utils.parseEther("100"));

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            await ve.createLock(deployer.address);

            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Change the fractions such that top-ups for stakers are not zero
            await tokenomics.connect(deployer).changeIncentiveFractions(49, 34, 17, 40, 34, 17);

            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.getEpochPoint(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const rewards = [
                (Number(ep.totalDonationsETH) * Number(ep.rewardStakerFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[0].rewardUnitFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[1].rewardUnitFraction)) / 100
            ];
            const accountRewards = rewards[0] + rewards[1] + rewards[2];
            // Calculate top-ups based on the points information
            let topUps = [
                (Number(ep.totalTopUpsOLAS) * Number(ep.maxBondFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[0].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[1].topUpUnitFraction)) / 100,
                Number(ep.totalTopUpsOLAS)
            ];
            topUps[3] -= topUps[0] + topUps[1] + topUps[2];
            const accountTopUps = topUps[1] + topUps[2] + topUps[3];
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Get the overall incentive amounts for owners
            const unitRewards = rewards[1] + rewards[2];
            const unitTopUps = topUps[1] + topUps[2];

            // Get deployer incentives information
            const result = await tokenomics.getOwnerRewards(deployer.address, [0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            const checkedReward = Number(result.reward);
            const checkedTopUp = Number(result.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            // Theoretical values must always be bigger than calculated ones (since round-off error is due to flooring)
            expect(unitRewards - checkedReward).to.lessThan(delta);
            expect(unitTopUps - checkedTopUp).to.lessThan(delta);

            // Simulate claiming rewards and top-ups for owners and check their correctness
            const claimedOwnerIncentives = await dispenser.connect(deployer).callStatic.claimOwnerRewards([0, 1], [1, 1]);
            // Get accumulated rewards and top-ups
            let claimedReward = Number(claimedOwnerIncentives.reward);
            let claimedTopUp = Number(claimedOwnerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with owner reward and top-up fractions
            expect(unitRewards - claimedReward).to.lessThan(delta);
            expect(unitTopUps - claimedTopUp).to.lessThan(delta);

            // Simulate claiming of incentives for stakers
            const claimedStakerIncentives = await dispenser.connect(deployer).callStatic.claimStakingRewards();
            // Get accumulated rewards and top-ups
            claimedReward = Number(claimedStakerIncentives.reward);
            claimedTopUp = Number(claimedStakerIncentives.topUp);
            // Check if they match with what was written to the tokenomics point with staker reward and top-up fractions
            expect(rewards[0] - claimedReward).to.lessThan(delta);
            expect(topUps[3] - claimedTopUp).to.lessThan(delta);

            // Claim rewards and top-ups
            const balanceBeforeTopUps = BigInt(await olas.balanceOf(deployer.address));
            await dispenser.connect(deployer).claimOwnerRewards([0, 1], [1, 1]);
            await dispenser.connect(deployer).claimStakingRewards();
            const balanceAfterTopUps = BigInt(await olas.balanceOf(deployer.address));

            // Check the OLAS balance after receiving incentives
            const balance = Number(balanceAfterTopUps - balanceBeforeTopUps);
            expect(accountTopUps - balance).to.lessThan(delta);
        });

        it("Should fail when trying to get incentives with incorrect inputs", async () => {
            // Try to get and claim owner rewards with the wrong array length
            await expect(
                tokenomics.getOwnerRewards(deployer.address, [0], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongArrayLength");
            await expect(
                dispenser.claimOwnerRewards([0], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "WrongArrayLength");

            // Try to get and claim owner rewards while not being the owner of components / agents
            await expect(
                tokenomics.getOwnerRewards(deployer.address, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");
            await expect(
                dispenser.claimOwnerRewards([0, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "OwnerOnly");

            // Assign component and agent ownership to a deployer
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Try to get and claim owner rewards with incorrect unit type
            await expect(
                tokenomics.getOwnerRewards(deployer.address, [2, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "Overflow");
            await expect(
                dispenser.claimOwnerRewards([2, 1], [1, 1])
            ).to.be.revertedWithCustomError(tokenomics, "Overflow");
        });

        it("Withdraw incentives for unit owners and stakers for more than one epoch", async () => {
            // Change the first service owner to the deployer (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, deployer.address);
            await componentRegistry.changeUnitOwner(1, deployer.address);
            await agentRegistry.changeUnitOwner(1, deployer.address);

            // Try to get and claim rewards
            await tokenomics.getOwnerRewards(deployer.address, [0, 1], [1, 1]);
            await dispenser.connect(deployer).claimOwnerRewards([0, 1], [1, 1]);
            await dispenser.connect(deployer).claimStakingRewards();

            // Skip the number of blocks for 2 epochs
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();

            // Calculate staking rewards with zero balances and total supply
            await ve.setBalance(0);
            await ve.setSupply(0);
            await tokenomics.calculateStakingRewards(deployer.address, 1);
            // Set the voting escrow value back
            await ve.setBalance(ethers.utils.parseEther("50"));
            await tokenomics.calculateStakingRewards(deployer.address, 1);
            await ve.setSupply(ethers.utils.parseEther("100"));

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow
            await ve.createLock(deployer.address);

            // Change the fractions such that top-ups for stakers are not zero
            await tokenomics.connect(deployer).changeIncentiveFractions(49, 34, 17, 40, 34, 17);

            // EPOCH 1 with donations
            // Consider the scenario when no service owners locks enough OLAS for component / agent owners to claim top-ups
            await ve.setWeightedBalance(0);

            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get deployer incentives information
            let result = await tokenomics.getOwnerRewards(deployer.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            // Since no service owners locked enough OLAS in veOLAS, there must be a zero top-up for owners
            expect(result.topUp).to.equal(0);

            // EPOCH 2 with donations and top-ups
            // Return the ability for the service owner to have enough veOLAS for the owner top-ups
            const minWeightedBalance = await tokenomics.veOLASThreshold();
            await ve.setWeightedBalance(minWeightedBalance.toString() + "1");

            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.getEpochPoint(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const rewards = [
                (Number(ep.totalDonationsETH) * Number(ep.rewardStakerFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[0].rewardUnitFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[1].rewardUnitFraction)) / 100
            ];
            const accountRewards = rewards[0] + rewards[1] + rewards[2];
            // Calculate top-ups based on the points information
            let topUps = [
                (Number(ep.totalTopUpsOLAS) * Number(ep.maxBondFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[0].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[1].topUpUnitFraction)) / 100,
                Number(ep.totalTopUpsOLAS)
            ];
            topUps[3] -= topUps[0] + topUps[1] + topUps[2];
            const accountTopUps = topUps[1] + topUps[2] + topUps[3];
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            // Get deployer incentives information
            result = await tokenomics.getOwnerRewards(deployer.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            expect(result.topUp).to.greaterThan(0);

            // Claim rewards and top-ups
            await dispenser.connect(deployer).claimOwnerRewards([0, 1], [1, 1]);
            await dispenser.connect(deployer).claimStakingRewards();
        });
    });

    context("Reentrancy attacks", async function () {
        it("Attacks on withdraw rewards for unit owners and stakers", async () => {
            // Skip the number of blocks for 2 epochs
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();
            await ethers.provider.send("evm_mine");
            await tokenomics.connect(deployer).checkpoint();

            // Send ETH to treasury
            const amount = ethers.utils.parseEther("1000");
            await deployer.sendTransaction({to: treasury.address, value: amount});

            // Lock OLAS balances with Voting Escrow for the attacker
            await ve.createLock(attacker.address);

            // Change the first service owner to the attacker (same for components and agents)
            await serviceRegistry.changeUnitOwner(1, attacker.address);
            await componentRegistry.changeUnitOwner(1, attacker.address);
            await agentRegistry.changeUnitOwner(1, attacker.address);

            // Send the revenues to services
            await treasury.connect(deployer).depositETHFromServices([1, 2], [regDepositFromServices, regDepositFromServices],
                {value: twoRegDepositFromServices});
            // Start new epoch and calculate tokenomics parameters and rewards
            await tokenomics.connect(deployer).checkpoint();

            // Get the last settled epoch counter
            const lastPoint = Number(await tokenomics.epochCounter()) - 1;
            // Get the epoch point of the last epoch
            const ep = await tokenomics.getEpochPoint(lastPoint);
            // Get the unit points of the last epoch
            const up = [await tokenomics.getUnitPoint(lastPoint, 0), await tokenomics.getUnitPoint(lastPoint, 1)];
            // Calculate rewards based on the points information
            const rewards = [
                (Number(ep.totalDonationsETH) * Number(ep.rewardStakerFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[0].rewardUnitFraction)) / 100,
                (Number(ep.totalDonationsETH) * Number(up[1].rewardUnitFraction)) / 100
            ];
            const accountRewards = rewards[0] + rewards[1] + rewards[2];
            // Calculate top-ups based on the points information
            let topUps = [
                (Number(ep.totalTopUpsOLAS) * Number(ep.maxBondFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[0].topUpUnitFraction)) / 100,
                (Number(ep.totalTopUpsOLAS) * Number(up[1].topUpUnitFraction)) / 100,
                Number(ep.totalTopUpsOLAS)
            ];
            topUps[3] -= topUps[0] + topUps[1] + topUps[2];
            const accountTopUps = topUps[1] + topUps[2] + topUps[3];
            expect(accountRewards).to.greaterThan(0);
            expect(accountTopUps).to.greaterThan(0);

            let result = await tokenomics.getOwnerRewards(attacker.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            expect(result.topUp).to.greaterThan(0);

            // Failing on the receive call
            await expect(
                attacker.badClaimOwnerRewards(false, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(dispenser, "TransferFailed");

            await expect(
                attacker.badClaimStakingRewards(false)
            ).to.be.revertedWithCustomError(dispenser, "TransferFailed");

            await expect(
                attacker.badClaimOwnerRewards(true, [0, 1], [1, 1])
            ).to.be.revertedWithCustomError(dispenser, "TransferFailed");

            await expect(
                attacker.badClaimStakingRewards(true)
            ).to.be.revertedWithCustomError(dispenser, "TransferFailed");

            // The funds still remain on the protocol side
            result = await tokenomics.getOwnerRewards(attacker.address, [0, 1], [1, 1]);
            expect(result.reward).to.greaterThan(0);
            expect(result.topUp).to.greaterThan(0);
        });
    });
});
