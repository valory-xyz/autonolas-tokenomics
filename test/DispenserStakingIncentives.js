/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe.only("DispenserStakingIncentives", async () => {
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
    const maxNumClaimingEpochs = 10;
    const maxNumStakingTargets = 100;

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
        dispenser = await Dispenser.deploy(olas.address, deployer.address, deployer.address, deployer.address,
            maxNumClaimingEpochs, maxNumStakingTargets);
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

            // Trying to add retainer as a nominee when the staking incentives is paused
            await expect(
                vw.addNominee(signers[1].address, chainId)
            ).to.be.revertedWithCustomError(dispenser, "Paused");
            // Trying to add retainer as a nominee when all is paused
            await dispenser.setPauseState(3);
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

            // Check that the target contract got OLAS
            expect(await olas.balanceOf(stakingInstance.address)).to.gt(0);

            // Set weights to a very small value
            await vw.setNomineeRelativeWeight(convertBytes32ToAddress(stakingTarget), chainId, 1);

            // Checkpoint to start the new epoch and able to claim
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            // No one will have enough staking amount, and no token deposits will be triggered
            // All the staking allocation will be returned back to inflation
            await dispenser.claimStakingIncentives(numClaimedEpochs, chainId, stakingTarget, bridgePayload);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Claim staking incentives for several nominees", async () => {
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

            // Get another staking instance
            const MockStakingProxy = await ethers.getContractFactory("MockStakingProxy");
            const stakingInstance2 = await MockStakingProxy.deploy(olas.address);
            await stakingInstance2.deployed();

            // Add a default implementation mocked as a proxy address itself
            await stakingProxyFactory.addImplementation(stakingInstance2.address, stakingInstance2.address);

            let stakingTargets = [stakingInstance.address, stakingInstance2.address];
            let chainIds = [chainId, chainId + 1];

            // Set another deposit processor for a different chain Id
            await dispenser.setDepositProcessorChainIds([ethereumDepositProcessor.address], [chainId + 1]);

            for (let i = 0; i < stakingTargets.length; i++) {
                // Add each staking instances as a nominee
                await vw.addNominee(stakingTargets[i], chainIds[i]);
                // Vote for each nominee
                await vw.setNomineeRelativeWeight(stakingTargets[i], chainIds[i], defaultWeight);
                // Change the address to bytes32 form
                stakingTargets[i] = convertAddressToBytes32(stakingTargets[i]);
            }

            // Checkpoint to apply changes
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            let stakingTargetsFinal = [[stakingTargets[0]], [stakingTargets[1]]];
            let bridgePayloads = [bridgePayload, bridgePayload];
            let valueAmounts = [0, 0];

            // Claim staking incentives
            await dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                bridgePayloads, valueAmounts);

            // Check that target contracts got OLAS
            for (let i = 0; i < stakingTargets.length; i++) {
                expect(await olas.balanceOf(convertBytes32ToAddress(stakingTargets[i]))).to.gt(0);
            }

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Should fail when claiming staking incentives for nominees with incorrect params", async () => {
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

            // Get another staking instance
            const MockStakingProxy = await ethers.getContractFactory("MockStakingProxy");
            const stakingInstance2 = await MockStakingProxy.deploy(olas.address);
            await stakingInstance2.deployed();

            // Add a default implementation mocked as a proxy address itself
            await stakingProxyFactory.addImplementation(stakingInstance2.address, stakingInstance2.address);

            // Descending order of staking contracts and chain Ids
            let stakingTargets;
            if (stakingInstance.address.toString() > stakingInstance2.address.toString()) {
                stakingTargets = [stakingInstance.address, stakingInstance2.address];
            } else {
                stakingTargets = [stakingInstance2.address, stakingInstance.address];
            }
            let chainIds = [chainId + 1, chainId];

            // Set another deposit processor for a different chain Id
            await dispenser.setDepositProcessorChainIds([ethereumDepositProcessor.address], [chainId + 1]);

            for (let i = 0; i < stakingTargets.length; i++) {
                // Add each staking instances as a nominee
                await vw.addNominee(stakingTargets[i], chainIds[i]);
                // Vote for each nominee
                await vw.setNomineeRelativeWeight(stakingTargets[i], chainIds[i], defaultWeight);
                // Change the address to bytes32 form
                stakingTargets[i] = convertAddressToBytes32(stakingTargets[i]);
            }

            // Checkpoint to apply changes
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            let stakingTargetsFinal = [[stakingTargets[0]], [stakingTargets[1]]];
            let bridgePayloads = [bridgePayload, bridgePayload];
            let valueAmounts = [0, 0];

            // Wrong array lengths
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, [], stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, [],
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    [], valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, [])
            ).to.be.revertedWithCustomError(dispenser, "WrongArrayLength");

            // Try to claim staking incentives with reverse chain Id order
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongChainId");

            // First chain Id is zero
            chainIds = [0, 1];
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongChainId");
            await expect(
                dispenser.claimStakingIncentives(numClaimedEpochs, 0, HashZero, bridgePayloads[0])
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");
            // Same in the calculation of staking incentives
            await expect(
                dispenser.calculateStakingIncentives(numClaimedEpochs, 0, HashZero, bridgingDecimals)
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");

            // Correct chain Ids
            chainIds = [chainId, chainId + 1]

            // Empty staking arrays
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, [[], []],
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");

            // Zero value staking targets
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, [[HashZero], [HashZero]],
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "WrongAccount");
            await expect(
                dispenser.claimStakingIncentives(numClaimedEpochs, chainId, HashZero, bridgePayloads[0])
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");
            // Same in the calculation of staking incentives
            await expect(
                dispenser.calculateStakingIncentives(numClaimedEpochs, chainId, HashZero, bridgingDecimals)
            ).to.be.revertedWithCustomError(dispenser, "ZeroAddress");

            // Repeating staking targets
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, [chainId], [[stakingTargets[0], stakingTargets[0]]],
                    [bridgePayloads[0]], [valueAmounts[0]])
            ).to.be.revertedWithCustomError(dispenser, "WrongAccount");

            // Descending order of staking targets
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, [chainId], [[stakingTargets[0], stakingTargets[1]]],
                    [bridgePayloads[0]], [valueAmounts[0]])
            ).to.be.revertedWithCustomError(dispenser, "WrongAccount");

            // Value amounts is incorrect
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, [0, 1])
            ).to.be.revertedWithCustomError(dispenser, "WrongAmount");

            // Change dispenser staking params
            await dispenser.changeStakingParams(1, 1);
            // Too many staking targets
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, [chainId], [[stakingTargets[1], stakingTargets[0]]],
                    [bridgePayloads[0]], [valueAmounts[0]])
            ).to.be.revertedWithCustomError(dispenser, "Overflow");

            // Too many epochs to claim for
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs + 1, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "Overflow");
            await expect(
                dispenser.claimStakingIncentives(numClaimedEpochs + 1, chainId, stakingTargets[0], bridgePayloads[0])
            ).to.be.revertedWithCustomError(dispenser, "Overflow");

            // Trying to claim when staking is paused
            await dispenser.setPauseState(2);
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "Paused");
            await expect(
                dispenser.claimStakingIncentives(numClaimedEpochs, chainId, stakingTargets[0], bridgePayloads[0])
            ).to.be.revertedWithCustomError(dispenser, "Paused");

            // Trying to claim when all is paused
            await dispenser.setPauseState(3);
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "Paused");
            await expect(
                dispenser.claimStakingIncentives(numClaimedEpochs, chainId, stakingTargets[0], bridgePayloads[0])
            ).to.be.revertedWithCustomError(dispenser, "Paused");

            // Unpause everything
            await dispenser.setPauseState(0);

            // The nominees were registered in the reverse chain Id order, and thus do not exist with the current one
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "ZeroValue");

            // Register nominees with a correct order
            for (let i = 0; i < stakingTargets.length; i++) {
                // Add each staking instances as a nominee
                await vw.addNominee(convertBytes32ToAddress(stakingTargets[i]), chainIds[i]);
                // Vote for each nominee
                await vw.setNomineeRelativeWeight(convertBytes32ToAddress(stakingTargets[i]), chainIds[i], defaultWeight);
            }

            stakingTargetsFinal = [[stakingTargets[0]], [stakingTargets[1]]];

            // Claiming in the same epoch as registering nominees is not possible
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "Overflow");

            // Checkpoint to start the new epoch and able to claim
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            // Finally able to claim
            await dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                  bridgePayloads, valueAmounts);

            // Try to claim again in this epoch
            await expect(
                dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                    bridgePayloads, valueAmounts)
            ).to.be.revertedWithCustomError(dispenser, "Overflow");

            // Set weights to a very small value
            for (let i = 0; i < stakingTargets.length; i++) {
                // Vote for each nominee
                await vw.setNomineeRelativeWeight(convertBytes32ToAddress(stakingTargets[i]), chainIds[i], 1);
            }

            // Checkpoint to start the new epoch and able to claim
            await helpers.time.increase(epochLen);
            await tokenomics.checkpoint();

            // No one will have enough staking amount, and no token deposits will be triggered
            // All the staking allocation will be returned back to inflation
            await dispenser.claimStakingIncentivesBatch(numClaimedEpochs, chainIds, stakingTargetsFinal,
                  bridgePayloads, valueAmounts);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
