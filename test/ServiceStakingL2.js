/*global describe, before, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ServiceStakingL2", async () => {
    const initialMint = "1" + "0".repeat(26);
    const defaultDeposit = "1" + "0".repeat(22);
    const AddressZero = ethers.constants.AddressZero;
    const moreThanMaxUint96 = "79228162514264337593543950337";
    const chainId = 1;
    const defaultAmount = 100;

    let signers;
    let deployer;
    let olas;
    let serviceStakingInstance;
    let serviceStakingProxyFactory;
    let arbitrumTargetDispenserL2;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const ERC20TokenOwnerless = await ethers.getContractFactory("ERC20TokenOwnerless");
        olas = await ERC20TokenOwnerless.deploy();
        await olas.deployed();

        const MockServiceStakingProxy = await ethers.getContractFactory("MockServiceStakingProxy");
        serviceStakingInstance = await MockServiceStakingProxy.deploy();
        await serviceStakingInstance.deployed();

        const MockServiceStakingFactory = await ethers.getContractFactory("MockServiceStakingFactory");
        serviceStakingProxyFactory = await MockServiceStakingFactory.deploy();
        await serviceStakingProxyFactory.deployed();

        const ArbitrumTargetDispenserL2 = await ethers.getContractFactory("ArbitrumTargetDispenserL2");
        arbitrumTargetDispenserL2 = await ArbitrumTargetDispenserL2.deploy(olas.address,
            serviceStakingProxyFactory.address, deployer.address, deployer.address, deployer.address, chainId);
        await arbitrumTargetDispenserL2.deployed();
    });

    context("Receive messages", async function () {
        it("Receive message with single target and amount", async function () {
            await serviceStakingProxyFactory.addImplementation(serviceStakingInstance.address,
                serviceStakingInstance.address);

            // Encode the staking data to emulate it being received on L2
            const stakingTargets = [serviceStakingInstance.address];
            const stakingAmounts = [defaultAmount];
            let payloadData = ethers.utils.defaultAbiCoder.encode(["address[]","uint256[]"],
                [stakingTargets, stakingAmounts]);

            // Receive a message on L2 where the funds are not delivered yet
            await arbitrumTargetDispenserL2.receiveMessage(payloadData);

            // Simulate sending tokens from L1 to L2 by just minting them
            await olas.mint(arbitrumTargetDispenserL2.address, defaultAmount);

            // Receive a message on L2 with the funds available
            await arbitrumTargetDispenserL2.receiveMessage(payloadData);

            // Finish receiving a previous message
            await arbitrumTargetDispenserL2.redeem(stakingTargets[0], stakingAmounts[0], 0);

            await expect(
                arbitrumTargetDispenserL2.redeem(stakingTargets[0], stakingAmounts[0], 0)
            ).to.be.reverted;
        });
    });
});
