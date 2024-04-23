/*global describe, before, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ServiceStakingBridging", async () => {
    const initialMint = "1" + "0".repeat(26);
    const defaultDeposit = "1" + "0".repeat(22);
    const AddressZero = ethers.constants.AddressZero;
    const moreThanMaxUint96 = "79228162514264337593543950337";
    const chainId = 1;
    const defaultAmount = 100;
    const defaultCost = 100;
    const defaultGasPrice = 100;
    const defaultGasLimit = "2000000";
    const defaultMsgValue = "1" + "0".repeat(16);

    let signers;
    let deployer;
    let olas;
    let serviceStakingInstance;
    let serviceStakingProxyFactory;
    let dispenser;
    let bridgeRelayer;
    let arbitrumDepositProcessorL1;
    let arbitrumTargetDispenserL2;
    let gnosisDepositProcessorL1;
    let gnosisTargetDispenserL2;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const ERC20TokenOwnerless = await ethers.getContractFactory("ERC20TokenOwnerless");
        olas = await ERC20TokenOwnerless.deploy();
        await olas.deployed();

        const MockServiceStakingProxy = await ethers.getContractFactory("MockServiceStakingProxy");
        serviceStakingInstance = await MockServiceStakingProxy.deploy(olas.address);
        await serviceStakingInstance.deployed();

        const MockServiceStakingFactory = await ethers.getContractFactory("MockServiceStakingFactory");
        serviceStakingProxyFactory = await MockServiceStakingFactory.deploy();
        await serviceStakingProxyFactory.deployed();

        // Add a default implementation mocked as a proxy address itself
        await serviceStakingProxyFactory.addImplementation(serviceStakingInstance.address,
            serviceStakingInstance.address);

        const MockServiceStakingDispenser = await ethers.getContractFactory("MockServiceStakingDispenser");
        dispenser = await MockServiceStakingDispenser.deploy(olas.address);
        await dispenser.deployed();

        const BridgeRelayer = await ethers.getContractFactory("BridgeRelayer");
        bridgeRelayer = await BridgeRelayer.deploy(olas.address);
        await bridgeRelayer.deployed();

        const ArbitrumDepositProcessorL1 = await ethers.getContractFactory("ArbitrumDepositProcessorL1");
        arbitrumDepositProcessorL1 = await ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId, bridgeRelayer.address, bridgeRelayer.address);
        await arbitrumDepositProcessorL1.deployed();

        const ArbitrumTargetDispenserL2 = await ethers.getContractFactory("ArbitrumTargetDispenserL2");
        arbitrumTargetDispenserL2 = await ArbitrumTargetDispenserL2.deploy(olas.address,
            serviceStakingProxyFactory.address, deployer.address, bridgeRelayer.address,
            bridgeRelayer.address, chainId);
        await arbitrumTargetDispenserL2.deployed();

        // Set the arbitrumTargetDispenserL2 address in arbitrumDepositProcessorL1
        await arbitrumDepositProcessorL1.setL2TargetDispenser(arbitrumTargetDispenserL2.address);

        // Set arbitrum addresses in a bridge contract
        await bridgeRelayer.setArbitrumAddresses(arbitrumDepositProcessorL1.address, arbitrumTargetDispenserL2.address);

        const GnosisDepositProcessorL1 = await ethers.getContractFactory("GnosisDepositProcessorL1");
        gnosisDepositProcessorL1 = await GnosisDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId);
        await gnosisDepositProcessorL1.deployed();

        const GnosisTargetDispenserL2 = await ethers.getContractFactory("GnosisTargetDispenserL2");
        gnosisTargetDispenserL2 = await GnosisTargetDispenserL2.deploy(olas.address,
            serviceStakingProxyFactory.address, deployer.address, bridgeRelayer.address,
            gnosisDepositProcessorL1.address, chainId, bridgeRelayer.address);
        await gnosisTargetDispenserL2.deployed();

        // Set the gnosisTargetDispenserL2 address in gnosisDepositProcessorL1
        await gnosisDepositProcessorL1.setL2TargetDispenser(gnosisTargetDispenserL2.address);

        // Set gnosis addresses in a bridge contract
        await bridgeRelayer.setGnosisAddresses(gnosisDepositProcessorL1.address, gnosisTargetDispenserL2.address);

        const OptimismDepositProcessorL1 = await ethers.getContractFactory("OptimismDepositProcessorL1");
        optimismDepositProcessorL1 = await OptimismDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId, olas.address);
        await optimismDepositProcessorL1.deployed();

        const OptimismTargetDispenserL2 = await ethers.getContractFactory("OptimismTargetDispenserL2");
        optimismTargetDispenserL2 = await OptimismTargetDispenserL2.deploy(olas.address,
            serviceStakingProxyFactory.address, deployer.address, bridgeRelayer.address,
            optimismDepositProcessorL1.address, chainId);
        await optimismTargetDispenserL2.deployed();

        // Set the optimismTargetDispenserL2 address in optimismDepositProcessorL1
        await optimismDepositProcessorL1.setL2TargetDispenser(optimismTargetDispenserL2.address);

        // Set optimism addresses in a bridge contract
        await bridgeRelayer.setOptimismAddresses(optimismDepositProcessorL1.address, optimismTargetDispenserL2.address);
    });

    context("Arbitrum", async function () {
        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = serviceStakingInstance.address;
            const stakingAmount = defaultAmount;
            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [deployer.address, defaultGasPrice, defaultCost, defaultGasLimit, defaultCost]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Get the current staking batch nonce
            const stakingBatchNonce = await arbitrumTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(arbitrumTargetDispenserL2.address, stakingAmount);

            // Redeem funds
            await arbitrumTargetDispenserL2.redeem(stakingTarget, stakingAmount, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, deployer.address, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await arbitrumTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingAmount);

            // Send withheld amount from L2 to L1
            await arbitrumTargetDispenserL2.syncWithheldTokens("0x");
        });
    });

    context("Gnosis", async function () {
        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = serviceStakingInstance.address;
            const stakingAmount = defaultAmount;

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [defaultGasLimit]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Get the current staking batch nonce
            const stakingBatchNonce = await gnosisTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(gnosisTargetDispenserL2.address, stakingAmount);

            // Redeem funds
            await gnosisTargetDispenserL2.redeem(stakingTarget, stakingAmount, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, deployer.address, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await gnosisTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingAmount);

            // Send withheld amount from L2 to L1
            await gnosisTargetDispenserL2.syncWithheldTokens("0x");
        });
    });

    context("Optimism", async function () {
        it.only("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = serviceStakingInstance.address;
            const stakingAmount = defaultAmount;

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"],
                [defaultCost, defaultGasLimit]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Get the current staking batch nonce
            const stakingBatchNonce = await optimismTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingAmount, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(optimismTargetDispenserL2.address, stakingAmount);

            // Redeem funds
            await optimismTargetDispenserL2.redeem(stakingTarget, stakingAmount, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, deployer.address, stakingAmount, bridgePayload,
                stakingAmount, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await optimismTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingAmount);

            // Send withheld amount from L2 to L1
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [defaultCost]);
            await optimismTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultCost});
        });
    });
});
