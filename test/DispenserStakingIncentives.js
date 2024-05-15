/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("DispenserStakingIncentives", async () => {
    const initialMint = "1" + "0".repeat(26);
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const oneMonth = 86400 * 30;
    const chainId = 31337;
    const defaultWeight = 1000;
    const numClaimedEpochs = 1;
    const bridgingDecimals = 18;
    const bridgePayload = "0x";
    const epochLen = oneMonth;
    const delta = 100;

    let signers;
    let deployer;
    let olas;
    let stakingInstance;
    let stakingProxyFactory;
    let tokenomics;
    let treasury;
    let dispenser;
    let vw;
    let ethereumDepositProcessor;

    function convertAddressToBytes32(account) {
        return ("0x" + "0".repeat(24) + account.slice(2)).toLowerCase();
    }

    function convertBytes32ToAddress(account) {
        return "0x" + account.slice(26);
    }

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        const olasFactory = await ethers.getContractFactory("ERC20Token");
        olas = await olasFactory.deploy();
        await olas.deployed();

        const MockStakingProxy = await ethers.getContractFactory("MockStakingProxy");
        stakingInstance = await MockStakingProxy.deploy(olas.address);
        await stakingInstance.deployed();

        const MockStakingFactory = await ethers.getContractFactory("MockStakingFactory");
        stakingProxyFactory = await MockStakingFactory.deploy();
        await stakingProxyFactory.deployed();

        // Add a default implementation mocked as a proxy address itself
        await stakingProxyFactory.addImplementation(stakingInstance.address, stakingInstance.address);

        const Dispenser = await ethers.getContractFactory("Dispenser");
        dispenser = await Dispenser.deploy(olas.address, deployer.address, deployer.address, deployer.address);
        await dispenser.deployed();

        // Vote Weighting mock
        const VoteWeighting = await ethers.getContractFactory("MockVoteWeighting");
        vw = await VoteWeighting.deploy(dispenser.address);
        await vw.deployed();

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
            [olas.address, treasury.address, deployer.address, dispenser.address, deployer.address, epochLen,
                deployer.address, deployer.address, deployer.address, AddressZero]);
        // Deploy tokenomics proxy based on the needed tokenomics initialization
        const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
        const tokenomicsProxy = await TokenomicsProxy.deploy(tokenomicsMaster.address, proxyData);
        await tokenomicsProxy.deployed();

        // Get the tokenomics proxy contract
        tokenomics = await ethers.getContractAt("Tokenomics", tokenomicsProxy.address);

        // Change the tokenomics and treasury addresses in the dispenser to correct ones
        await dispenser.changeManagers(tokenomics.address, treasury.address, vw.address);

        // Update tokenomics address in treasury
        await treasury.changeManagers(tokenomics.address, AddressZero, AddressZero);

        // Mint the initial balance
        await olas.mint(deployer.address, initialMint);

        // Give treasury the minter role
        await olas.changeMinter(treasury.address);

        // Default Deposit Processor
        const EthereumDepositProcessor = await ethers.getContractFactory("EthereumDepositProcessor");
        ethereumDepositProcessor = await EthereumDepositProcessor.deploy(olas.address, dispenser.address,
            stakingProxyFactory.address);
        await ethereumDepositProcessor.deployed();

        // Whitelist a default deposit processor
        await dispenser.setDepositProcessorChainIds([ethereumDepositProcessor.address], [chainId]);
    });

    context("Initialization", async function () {
        it("Should fail when trying to add and remove nominees not by the Vote Weighting contract", async () => {
            await expect(
                dispenser.connect(deployer).addNominee(HashZero)
            ).to.be.revertedWithCustomError(dispenser, "ManagerOnly");

            await expect(
                dispenser.connect(deployer).removeNominee(HashZero)
            ).to.be.revertedWithCustomError(dispenser, "ManagerOnly");
        });

        it("Changing staking parameters", async () => {
            // Should fail when not called by the owner
            await expect(
                dispenser.connect(signers[1]).changeStakingParams(0, 0)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Set arbitrary parameters
            await dispenser.changeStakingParams(10, 10);

            // No action when trying to set parameters to zero
            await dispenser.changeStakingParams(0, 0);
            expect(await dispenser.maxNumClaimingEpochs()).to.equal(10);
            expect(await dispenser.maxNumStakingTargets()).to.equal(10);
        });

        it("Changing retainer from a zero initial address", async () => {
            // Should fail when not called by the owner
            await expect(
                dispenser.connect(signers[1]).changeRetainer(HashZero)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Trying to set a zero address retainer
            await expect(
                dispenser.changeRetainer(HashZero)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");

            // Trying to set a retainer address that is not added as a nominee
            await expect(
                dispenser.changeRetainer(convertAddressToBytes32(signers[1].address))
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");

            // Trying to add retainer as a nominee when the contract is paused
            await expect(
                vw.addNominee(signers[1].address, chainId)
            ).to.be.revertedWithCustomError(dispenser, "Paused");

            // Try to unpause the dispenser not by the owner
            await expect(
                dispenser.connect(signers[1]).setPauseState(0)
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Unpause the dispenser
            await dispenser.setPauseState(0);

            // Add retainer as a nominee
            await vw.addNominee(signers[1].address, chainId);

            // Change the retainer
            await dispenser.changeRetainer(convertAddressToBytes32(signers[1].address));
        });

        it("Should fail when setting deposit processors and chain Ids with incorrect parameters", async () => {
            // Should fail when not called by the owner
            await expect(
                dispenser.connect(signers[1]).setDepositProcessorChainIds([],[])
            ).to.be.revertedWithCustomError(dispenser, "OwnerOnly");

            // Should fail when array lengths are zero
            await expect(
                dispenser.setDepositProcessorChainIds([],[])
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");

            // Should fail when array lengths do not match
            await expect(
                dispenser.setDepositProcessorChainIds([ethereumDepositProcessor.address],[])
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");

            // Should fail when chain Id is zero
            await expect(
                dispenser.setDepositProcessorChainIds([ethereumDepositProcessor.address],[0])
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");
        });
    });

    context("Staking incentives", async function () {
        it("Claim staking incentives for a single nominee", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Set staking fraction to 100%
            await tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 100);
            // Changing staking parameters
            await tokenomics.changeStakingParams(50, 10);

            // Checkpoint to apply changes
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            // Unpause the dispenser
            await dispenser.setPauseState(0);

            // Add a staking instance as a nominee
            await vw.addNominee(stakingInstance.address, chainId);

            // Vote for the nominee
            await vw.setNomineeRelativeWeight(stakingInstance.address, chainId, defaultWeight);

            // Checkpoint to apply changes
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            const stakingTarget = convertAddressToBytes32(stakingInstance.address);
            // Calculate staking incentives
            const stakingAmounts = await dispenser.callStatic.calculateStakingIncentives(numClaimedEpochs, chainId,
                stakingTarget, bridgingDecimals);
            // We deliberately setup the voting such that there is staking amount and return amount
            expect(stakingAmounts.totalStakingAmount).to.gt(0);
            expect(stakingAmounts.totalReturnAmount).to.gt(0);

            // Claim staking incentives
            await dispenser.claimStakingIncentives(numClaimedEpochs, chainId, stakingTarget, bridgePayload);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
