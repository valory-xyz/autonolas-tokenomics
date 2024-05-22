/*global describe, before, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("StakingBridging", async () => {
    const initialMint = "1" + "0".repeat(26);
    const defaultDeposit = "1" + "0".repeat(22);
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
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
    let stakingInstance;
    let stakingProxyFactory;
    let dispenser;
    let bridgeRelayer;
    let ethereumDepositProcessor;
    let arbitrumDepositProcessorL1;
    let arbitrumTargetDispenserL2;
    let gnosisDepositProcessorL1;
    let gnosisTargetDispenserL2;
    let optimismDepositProcessorL1;
    let optimismTargetDispenserL2;
    let polygonDepositProcessorL1;
    let polygonTargetDispenserL2;
    let wormholeDepositProcessorL1;
    let wormholeTargetDispenserL2;

    // These should not be in beforeEach.
    beforeEach(async () => {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const ERC20TokenOwnerless = await ethers.getContractFactory("ERC20TokenOwnerless");
        olas = await ERC20TokenOwnerless.deploy();
        await olas.deployed();

        const MockStakingProxy = await ethers.getContractFactory("MockStakingProxy");
        stakingInstance = await MockStakingProxy.deploy(olas.address);
        await stakingInstance.deployed();

        const MockStakingFactory = await ethers.getContractFactory("MockStakingFactory");
        stakingProxyFactory = await MockStakingFactory.deploy();
        await stakingProxyFactory.deployed();

        // Add a default implementation mocked as a proxy address itself
        await stakingProxyFactory.addImplementation(stakingInstance.address, stakingInstance.address);

        const MockStakingDispenser = await ethers.getContractFactory("MockStakingDispenser");
        dispenser = await MockStakingDispenser.deploy(olas.address);
        await dispenser.deployed();

        const BridgeRelayer = await ethers.getContractFactory("BridgeRelayer");
        bridgeRelayer = await BridgeRelayer.deploy(olas.address);
        await bridgeRelayer.deployed();

        const EthereumDepositProcessor = await ethers.getContractFactory("EthereumDepositProcessor");
        ethereumDepositProcessor = await EthereumDepositProcessor.deploy(olas.address, dispenser.address,
            stakingProxyFactory.address, deployer.address);
        await ethereumDepositProcessor.deployed();

        const ArbitrumDepositProcessorL1 = await ethers.getContractFactory("ArbitrumDepositProcessorL1");
        // L2 Target Dispenser address is a bridge contract as well such that it matches the required msg.sender
        arbitrumDepositProcessorL1 = await ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId, bridgeRelayer.address, bridgeRelayer.address,
            bridgeRelayer.address);
        await arbitrumDepositProcessorL1.deployed();

        const bridgedRelayerDeAliased = await bridgeRelayer.l1ToL2AliasedSender();
        const ArbitrumTargetDispenserL2 = await ethers.getContractFactory("ArbitrumTargetDispenserL2");
        arbitrumTargetDispenserL2 = await ArbitrumTargetDispenserL2.deploy(olas.address,
            stakingProxyFactory.address, bridgeRelayer.address, bridgedRelayerDeAliased, chainId);
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
            stakingProxyFactory.address, bridgeRelayer.address, gnosisDepositProcessorL1.address, chainId,
            bridgeRelayer.address);
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
            stakingProxyFactory.address, bridgeRelayer.address, optimismDepositProcessorL1.address, chainId);
        await optimismTargetDispenserL2.deployed();

        // Set the optimismTargetDispenserL2 address in optimismDepositProcessorL1
        await optimismDepositProcessorL1.setL2TargetDispenser(optimismTargetDispenserL2.address);

        // Set optimism addresses in a bridge contract
        await bridgeRelayer.setOptimismAddresses(optimismDepositProcessorL1.address, optimismTargetDispenserL2.address);

        const PolygonDepositProcessorL1 = await ethers.getContractFactory("PolygonDepositProcessorL1");
        polygonDepositProcessorL1 = await PolygonDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId, olas.address, bridgeRelayer.address);
        await polygonDepositProcessorL1.deployed();

        const PolygonTargetDispenserL2 = await ethers.getContractFactory("PolygonTargetDispenserL2");
        polygonTargetDispenserL2 = await PolygonTargetDispenserL2.deploy(olas.address,
            stakingProxyFactory.address, bridgeRelayer.address, polygonDepositProcessorL1.address, chainId);
        await polygonTargetDispenserL2.deployed();

        // Set the polygonTargetDispenserL2 address in polygonDepositProcessorL1
        await polygonDepositProcessorL1.setL2TargetDispenser(polygonTargetDispenserL2.address);
        // Set the polygonDepositProcessorL1 address in polygonTargetDispenserL2
        await polygonTargetDispenserL2.setFxRootTunnel(polygonDepositProcessorL1.address);

        // Set polygon addresses in a bridge contract
        await bridgeRelayer.setPolygonAddresses(polygonDepositProcessorL1.address, polygonTargetDispenserL2.address);

        const WormholeDepositProcessorL1 = await ethers.getContractFactory("WormholeDepositProcessorL1");
        wormholeDepositProcessorL1 = await WormholeDepositProcessorL1.deploy(olas.address, dispenser.address,
            bridgeRelayer.address, bridgeRelayer.address, chainId, bridgeRelayer.address, chainId);
        await wormholeDepositProcessorL1.deployed();

        const WormholeTargetDispenserL2 = await ethers.getContractFactory("WormholeTargetDispenserL2");
        wormholeTargetDispenserL2 = await WormholeTargetDispenserL2.deploy(olas.address,
            stakingProxyFactory.address, bridgeRelayer.address, wormholeDepositProcessorL1.address, chainId,
            bridgeRelayer.address, bridgeRelayer.address);
        await wormholeTargetDispenserL2.deployed();

        // Set the wormholeTargetDispenserL2 address in wormholeDepositProcessorL1
        await wormholeDepositProcessorL1.setL2TargetDispenser(wormholeTargetDispenserL2.address);

        // Set wormhole addresses in a bridge contract
        await bridgeRelayer.setWormholeAddresses(wormholeDepositProcessorL1.address, wormholeTargetDispenserL2.address);
    });

    context("Ethereum", async function () {
        it("Should fail with incorrect constructor parameters for L1", async function () {
            const EthereumDepositProcessor = await ethers.getContractFactory("EthereumDepositProcessor");
            // Zero OLAS token
            await expect(
                EthereumDepositProcessor.deploy(AddressZero, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(ethereumDepositProcessor, "ZeroAddress");

            // Zero dispenser address
            await expect(
                EthereumDepositProcessor.deploy(olas.address, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(ethereumDepositProcessor, "ZeroAddress");

            // Zero staking factory address
            await expect(
                EthereumDepositProcessor.deploy(olas.address, dispenser.address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(ethereumDepositProcessor, "ZeroAddress");

            // Zero timelock address
            await expect(
                EthereumDepositProcessor.deploy(olas.address, dispenser.address, stakingProxyFactory.address, AddressZero)
            ).to.be.revertedWithCustomError(ethereumDepositProcessor, "ZeroAddress");
        });

        it("Staking deposit", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;
            const bridgePayload = "0x";

            // Try to deposit with a non-zero msg.value
            await expect(
                dispenser.mintAndSend(ethereumDepositProcessor.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive, {value: defaultMsgValue})
            ).to.be.reverted;
            await expect(
                dispenser.sendMessageBatch(ethereumDepositProcessor.address, [stakingTarget], [stakingIncentive],
                    bridgePayload, stakingIncentive, {value: defaultMsgValue})
            ).to.be.reverted;

            // Send a message not from the dispenser
            await expect(
                ethereumDepositProcessor.sendMessage(stakingTarget, stakingIncentive, bridgePayload, stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ManagerOnly");
            await expect(
                ethereumDepositProcessor.sendMessageBatch([stakingTarget], [stakingIncentive], bridgePayload, stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ManagerOnly");

            // Deposit with funds and a correct target
            await dispenser.mintAndSend(ethereumDepositProcessor.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive);

            // Deposit with funds and correct targets
            await dispenser.sendMessageBatch(ethereumDepositProcessor.address, [stakingTarget, stakingTarget],
                [stakingIncentive, stakingIncentive], bridgePayload, 2 * stakingIncentive);

            // Try to deposit to an invalid target
            await expect(
                dispenser.mintAndSend(ethereumDepositProcessor.address, deployer.address, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(ethereumDepositProcessor, "TargetEmissionsZero");
        });
    });

    context("Arbitrum", async function () {
        it("Should fail with incorrect constructor parameters for L1", async function () {
            const ArbitrumDepositProcessorL1 = await ethers.getContractFactory("ArbitrumDepositProcessorL1");
            // Zero OLAS token
            await expect(
                ArbitrumDepositProcessorL1.deploy(AddressZero, AddressZero, AddressZero, AddressZero,
                    0, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero dispenser address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, AddressZero, AddressZero, AddressZero,
                    0, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero L1 token relayer address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, AddressZero, AddressZero,
                    0, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero L1 message relayer address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address, AddressZero,
                    0, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero L2 chain Id
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, 0, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            // Overflow in L2 chain Id
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, ethers.constants.MaxUint256, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "Overflow");

            // Zero ERC20 Gateway address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero Outbox address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, bridgeRelayer.address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Zero Bridge address
            await expect(
                ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, bridgeRelayer.address, bridgeRelayer.address, AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");

            // Deploy the L1 deposit processor
            const depositProcessorL1 = await ArbitrumDepositProcessorL1.deploy(olas.address, dispenser.address,
                bridgeRelayer.address, bridgeRelayer.address, chainId, bridgeRelayer.address, bridgeRelayer.address,
                bridgeRelayer.address);

            // Try to set a zero address for the L2 target dispenser
            await expect(
                depositProcessorL1.setL2TargetDispenser(AddressZero)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroAddress");
        });

        it("Should fail with incorrect constructor parameters for L2", async function () {
            const ArbitrumTargetDispenserL2 = await ethers.getContractFactory("ArbitrumTargetDispenserL2");
            // Zero OLAS token
            await expect(
                ArbitrumTargetDispenserL2.deploy(AddressZero, AddressZero, AddressZero, AddressZero, 0)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroAddress");

            // Zero proxy factory address
            await expect(
                ArbitrumTargetDispenserL2.deploy(olas.address, AddressZero, AddressZero, AddressZero, 0)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroAddress");

            // Zero L2 message relayer address
            await expect(
                ArbitrumTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, AddressZero,
                    AddressZero, 0)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroAddress");

            // Zero L1 deposit processor address
            await expect(
                ArbitrumTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    AddressZero, 0)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroAddress");

            // Zero L1 chain Id
            await expect(
                ArbitrumTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    arbitrumDepositProcessorL1.address, 0)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroValue");

            // Overflow L1 chain Id
            await expect(
                ArbitrumTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    arbitrumDepositProcessorL1.address, ethers.constants.MaxUint256)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "Overflow");
        });

        it("Changing the owner and pausing / unpausing", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                arbitrumTargetDispenserL2.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                arbitrumTargetDispenserL2.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroAddress");

            // Changing the owner
            await arbitrumTargetDispenserL2.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                arbitrumTargetDispenserL2.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");

            // Trying to pause and unpause from a non-owner account address
            await expect(
                arbitrumTargetDispenserL2.connect(deployer).pause()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");

            await expect(
                arbitrumTargetDispenserL2.connect(deployer).unpause()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");
        });

        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero or incorrect payload
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "IncorrectDataLength");

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [deployer.address, defaultGasPrice, defaultCost, defaultGasLimit, defaultCost]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Get the current staking batch nonce
            let stakingBatchNonce = await arbitrumTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(arbitrumTargetDispenserL2.address, stakingIncentive);

            // Try to redeem funds with a wrong staking batch nonce
            await expect(
                arbitrumTargetDispenserL2.redeem(stakingTarget, stakingIncentive, 0)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "TargetAmountNotQueued");

            // Redeem funds
            await arbitrumTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(arbitrumDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await arbitrumTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingIncentive);

            // Send withheld amount from L2 to L1
            await arbitrumTargetDispenserL2.syncWithheldTokens("0x");

            // Try to send withheld amount from L2 to L1 when there is none
            await expect(
                arbitrumTargetDispenserL2.syncWithheldTokens("0x")
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            // Get the updated staking batch nonce
            stakingBatchNonce = await arbitrumTargetDispenserL2.stakingBatchNonce();

            // Process data maintenance by the owner
            const payload = ethers.utils.defaultAbiCoder.encode(["address[]", "uint256[]"],
                [[stakingTarget], [stakingIncentive * 2]]);
            await arbitrumTargetDispenserL2.processDataMaintenance(payload);

            // Try to do it not from the owner
            await expect(
                arbitrumTargetDispenserL2.connect(signers[1]).processDataMaintenance("0x")
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "OwnerOnly");

            // Try to redeem, but there are no funds
            await expect(
                arbitrumTargetDispenserL2.redeem(stakingTarget, stakingIncentive * 2, stakingBatchNonce)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "InsufficientBalance");

            // Try to send a batch message on L2 with funds
            await expect(
                arbitrumDepositProcessorL1.sendMessageBatch([], [], "0x", 0)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ManagerOnly");

            // Send a batch message on L2 with funds
            await dispenser.sendMessageBatch(arbitrumDepositProcessorL1.address, [stakingTarget, stakingTarget],
                [stakingIncentive, stakingIncentive], bridgePayload, stakingIncentive, {value: defaultMsgValue});
        });

        it("Checks during a message sending on L1", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero or incorrect payload
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "IncorrectDataLength");

            // Try executing with wrong price and gas related parameters
            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [AddressZero, 1, 0, 1, 0]);

            // Try to send a message
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [AddressZero, defaultGasPrice, 0, defaultGasLimit, defaultCost]);
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [AddressZero, defaultGasPrice, defaultCost, 1, 0]);
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [AddressZero, defaultGasPrice, defaultCost, defaultGasLimit, 0]);
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ZeroValue");

            // Not enough msg.value to cover the cost
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256", "uint256", "uint256", "uint256"],
                [AddressZero, defaultGasPrice, defaultCost, defaultGasLimit, defaultCost]);
            await expect(
                dispenser.mintAndSend(arbitrumDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "LowerThan");

            // Receiving a message not from the Bridge on L1
            await expect(
                arbitrumDepositProcessorL1.receiveMessage("0x")
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "TargetRelayerOnly");

            // Send a message not from the dispenser
            await expect(
                arbitrumDepositProcessorL1.sendMessage(stakingTarget, stakingIncentive, bridgePayload, stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ManagerOnly");
            await expect(
                arbitrumDepositProcessorL1.sendMessageBatch([stakingTarget], [stakingIncentive], bridgePayload, stakingIncentive)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "ManagerOnly");

            // Try to set the L2 dispenser address again
            await expect(
                arbitrumDepositProcessorL1.setL2TargetDispenser(arbitrumTargetDispenserL2.address)
            ).to.be.revertedWithCustomError(arbitrumDepositProcessorL1, "OwnerOnly");

            // Try to receive a message on L2 not by the aliased L1 deposit processor
            await expect(
                arbitrumTargetDispenserL2.receiveMessage("0x")
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "WrongMessageSender");
        });

        it("Drain functionality on L2", async function () {
            // Try to drain not by the owner
            await expect(
                arbitrumTargetDispenserL2.connect(signers[1]).drain()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");

            // Try to drain with the zero amount on a contract
            await expect(
                arbitrumTargetDispenserL2.drain()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ZeroValue");

            // Receive funds by ArbitrumTargetDispenserL2
            await deployer.sendTransaction({to: arbitrumTargetDispenserL2.address, value: ethers.utils.parseEther("1")});

            // Drain by the owner
            await arbitrumTargetDispenserL2.drain();
        });

        it("Migrate functionality on L2", async function () {
            // Try to migrate not by the owner
            await expect(
                arbitrumTargetDispenserL2.connect(signers[1]).migrate(AddressZero)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");

            // Try to migrate when the contract is not paused
            await expect(
                arbitrumTargetDispenserL2.migrate(AddressZero)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "Unpaused");

            // Pause the deposit processor
            await arbitrumTargetDispenserL2.pause();

            // Try to migrate not to the contract address
            await expect(
                arbitrumTargetDispenserL2.migrate(AddressZero)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "WrongAccount");

            // Try to migrate to the same contract (just to kill the contract)
            await expect(
                arbitrumTargetDispenserL2.migrate(arbitrumTargetDispenserL2.address)
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "WrongAccount");

            // Deposit some OLAS to the contract
            await olas.mint(arbitrumTargetDispenserL2.address, defaultAmount);

            // Migrate the contract to another one
            await arbitrumTargetDispenserL2.migrate(arbitrumDepositProcessorL1.address);

            // The contract is now frozen, pause is active and reentrancy revert is applied, where possible
            await expect(
                arbitrumTargetDispenserL2.drain()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "ReentrancyGuard");

            expect(await arbitrumTargetDispenserL2.owner()).to.equal(AddressZero);
            expect(await arbitrumTargetDispenserL2.paused()).to.equal(2);

            // Any ownable function is going to revert
            await expect(
                arbitrumTargetDispenserL2.unpause()
            ).to.be.revertedWithCustomError(arbitrumTargetDispenserL2, "OwnerOnly");
        });
    });

    context("Gnosis", async function () {
        it("Should fail with incorrect constructor parameters for L2", async function () {
            const GnosisTargetDispenserL2 = await ethers.getContractFactory("GnosisTargetDispenserL2");

            // Zero L2 token relayer address
            await expect(
                GnosisTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    gnosisDepositProcessorL1.address, chainId, AddressZero)
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "ZeroAddress");
        });

        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero or incorrect payload
            await expect(
                dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                    stakingIncentive)
            ).to.be.revertedWithCustomError(gnosisDepositProcessorL1, "IncorrectDataLength");

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [defaultGasLimit]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive);

            // Pause the L2 contract
            await gnosisTargetDispenserL2.pause();

            // Get the current staking batch nonce
            let stakingBatchNonce = await gnosisTargetDispenserL2.connect(deployer).stakingBatchNonce();

            // Send a message on L2 with funds when the contract is paused - it must queue the amount
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive);

            // Try to redeem
            await expect(
                gnosisTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce)
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "Paused");

            // Unpause and redeem
            await gnosisTargetDispenserL2.unpause();
            await gnosisTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Get the current staking batch nonce
            stakingBatchNonce = await gnosisTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0);

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(gnosisTargetDispenserL2.address, stakingIncentive);

            // Redeem funds
            await gnosisTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive);

            // Check the withheld amount
            const withheldAmount = await gnosisTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingIncentive);

            // Pause the L2 contract
            await gnosisTargetDispenserL2.pause();

            // Trying to sync withheld tokens when paused
            await expect(
                gnosisTargetDispenserL2.syncWithheldTokens("0x")
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "Paused");

            // Unpause and send withheld amount from L2 to L1
            await gnosisTargetDispenserL2.unpause();

            // Trying to sync withheld tokens with incorrect bridge payload
            await expect(
                gnosisTargetDispenserL2.syncWithheldTokens("0x")
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "IncorrectDataLength");

            // Send withheld token info from L2 to L1
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [0]);
            await gnosisTargetDispenserL2.syncWithheldTokens(bridgePayload);
        });

        it("Checks during a message sending on L1 and L2", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [0]);

            // Try to send a message with a zero gas limit
            await expect(
                dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(gnosisDepositProcessorL1, "ZeroValue");

            // Try to send a message with an overflow gas limit value for L2
            const overLimit = (await gnosisDepositProcessorL1.MESSAGE_GAS_LIMIT()).add(1);
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [overLimit]);
            await expect(
                dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(gnosisDepositProcessorL1, "Overflow");

            // Try to receive a message on L2 not sent by the bridge relayer
            await expect(
                gnosisTargetDispenserL2.onTokenBridged(AddressZero, 0, "0x")
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "TargetRelayerOnly");
        });

        it("Verify senders on L1 and L2", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256"], [defaultGasLimit]);

            // Set the mode for the message sender on receiving side
            await bridgeRelayer.setMode(2);

            // Message receive will fail on the L1 message sender
            await expect(
                dispenser.mintAndSend(gnosisDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "WrongMessageSender");

            // Send tokens to the wrong address to withhold it
            await dispenser.mintAndSend(gnosisDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive);

            // Try to receive a message with the wrong sender
            await expect(
                gnosisTargetDispenserL2.syncWithheldTokens(HashZero)
            ).to.be.revertedWithCustomError(gnosisDepositProcessorL1, "WrongMessageSender");


            // Deploy another bridge relayer
            const BridgeRelayer = await ethers.getContractFactory("BridgeRelayer");
            const bridgeRelayer2 = await BridgeRelayer.deploy(olas.address);
            await bridgeRelayer2.deployed();

            bridgePayload = gnosisTargetDispenserL2.interface.encodeFunctionData("receiveMessage", ["0x00"]);
            // Try to send messages via a wrong bridge relayer
            await expect(
                bridgeRelayer2.requireToPassMessage(gnosisTargetDispenserL2.address, bridgePayload, 0)
            ).to.be.revertedWithCustomError(gnosisTargetDispenserL2, "TargetRelayerOnly");

            await expect(
                bridgeRelayer2.requireToPassMessage(gnosisDepositProcessorL1.address, bridgePayload, 0)
            ).to.be.revertedWithCustomError(gnosisDepositProcessorL1, "TargetRelayerOnly");
        });
    });

    context("Optimism", async function () {
        it("Should fail with incorrect constructor parameters for L1", async function () {
            const OptimismDepositProcessorL1 = await ethers.getContractFactory("OptimismDepositProcessorL1");

            // Zero OLAS L2 address
            await expect(
                OptimismDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, AddressZero)
            ).to.be.revertedWithCustomError(optimismTargetDispenserL2, "ZeroAddress");
        });

        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero or incorrect payload
            await expect(
                dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                    stakingIncentive)
            ).to.be.revertedWithCustomError(optimismDepositProcessorL1, "IncorrectDataLength");

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"],
                [defaultCost, defaultGasLimit]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Get the current staking batch nonce
            const stakingBatchNonce = await optimismTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(optimismTargetDispenserL2.address, stakingIncentive);

            // Redeem funds
            await optimismTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await optimismTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingIncentive);

            // Send withheld amount from L2 to L1
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [defaultCost, 0]);
            await optimismTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultCost});
        });

        it("Checks during a message sending on L1 and L2", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero cost gas limit
            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [0, 0]);
            await expect(
                dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(optimismDepositProcessorL1, "ZeroValue");

            // Try to send a message with a zero gas limit
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [defaultCost, 0]);
            await expect(
                dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(optimismDepositProcessorL1, "ZeroValue");

            // Try to send a message without a proper msg.value
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [defaultCost, defaultGasLimit]);
            await expect(
                dispenser.mintAndSend(optimismDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(optimismDepositProcessorL1, "LowerThan");

            // Send a message to the wrong address such that the amount is withheld
            await dispenser.mintAndSend(optimismDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Try to sync a withheld amount with providing incorrect data
            await expect(
                optimismTargetDispenserL2.syncWithheldTokens(HashZero)
            ).to.be.revertedWithCustomError(optimismTargetDispenserL2, "IncorrectDataLength");

            // Trying to set a zero cost
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [0, 0]);
            await expect(
                optimismTargetDispenserL2.syncWithheldTokens(bridgePayload)
            ).to.be.revertedWithCustomError(optimismTargetDispenserL2, "ZeroValue");


            bridgePayload = ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [defaultCost, 0]);
            await expect(
                optimismTargetDispenserL2.syncWithheldTokens(bridgePayload)
            ).to.be.revertedWithCustomError(optimismTargetDispenserL2, "LowerThan");
        });
    });

    context("Polygon", async function () {
        it("Should fail with incorrect constructor parameters for L1", async function () {
            const PolygonDepositProcessorL1 = await ethers.getContractFactory("PolygonDepositProcessorL1");

            // Zero checkpoint manager contract address
            await expect(
                PolygonDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(polygonDepositProcessorL1, "ZeroAddress");

            // Zero ERC20 predicate contract address
            await expect(
                PolygonDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, bridgeRelayer.address, AddressZero)
            ).to.be.revertedWithCustomError(polygonDepositProcessorL1, "ZeroAddress");
        });

        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Send a message on L2 with funds
            await dispenser.mintAndSend(polygonDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                stakingIncentive);

            // Get the current staking batch nonce
            const stakingBatchNonce = await polygonTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(polygonDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x", 0);

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(polygonTargetDispenserL2.address, stakingIncentive);

            // Redeem funds
            await polygonTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(polygonDepositProcessorL1.address, deployer.address, stakingIncentive, "0x",
                stakingIncentive);

            // Check the withheld amount
            const withheldAmount = await polygonTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingIncentive);

            // Send withheld amount from L2 to L1
            await polygonTargetDispenserL2.syncWithheldTokens("0x");
        });
    });

    context("Wormhole", async function () {
        it("Should fail with incorrect constructor parameters for L1", async function () {
            const WormholeDepositProcessorL1 = await ethers.getContractFactory("WormholeDepositProcessorL1");

            // Zero L1 wormhole core contract address
            await expect(
                WormholeDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, AddressZero, 0)
            ).to.be.revertedWithCustomError(wormholeDepositProcessorL1, "ZeroAddress");

            // Zero wormhole L2 chain Id
            await expect(
                WormholeDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, bridgeRelayer.address, 0)
            ).to.be.revertedWithCustomError(wormholeDepositProcessorL1, "ZeroValue");

            // Overflow wormhole L2 chain Id
            await expect(
                WormholeDepositProcessorL1.deploy(olas.address, dispenser.address, bridgeRelayer.address,
                    bridgeRelayer.address, chainId, bridgeRelayer.address, 2**16 + 1)
            ).to.be.revertedWithCustomError(wormholeDepositProcessorL1, "Overflow");
        });

        it("Should fail with incorrect constructor parameters for L2", async function () {
            const WormholeTargetDispenserL2 = await ethers.getContractFactory("WormholeTargetDispenserL2");

            // Zero L2 wormhole core contract address
            await expect(
                WormholeTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    wormholeDepositProcessorL1.address, chainId, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "ZeroAddress");

            // Zero L2 token relayer contract address
            await expect(
                WormholeTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    wormholeDepositProcessorL1.address, chainId, bridgeRelayer.address, AddressZero)
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "ZeroAddress");

            // Overflow L1 wormhole chain Id
            await expect(
                WormholeTargetDispenserL2.deploy(olas.address, stakingProxyFactory.address, bridgeRelayer.address,
                    wormholeDepositProcessorL1.address, 2**16 + 1, bridgeRelayer.address, bridgeRelayer.address)
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "Overflow");
        });

        it("Send message with single target and amount from L1 to L2 and back", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero or incorrect payload
            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, "0x",
                    stakingIncentive)
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "IncorrectDataLength");

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [AddressZero, defaultGasLimit]);

            // Send a message on L2 with funds
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Get the current staking batch nonce
            const stakingBatchNonce = await wormholeTargetDispenserL2.stakingBatchNonce();

            // Send a message on L2 without enough funds
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                0, {value: defaultMsgValue});

            // Add more funds for the L2 target dispenser - a simulation of a late transfer incoming
            await olas.mint(wormholeTargetDispenserL2.address, stakingIncentive);

            // Redeem funds
            await wormholeTargetDispenserL2.redeem(stakingTarget, stakingIncentive, stakingBatchNonce);

            // Send a message on L2 with funds for a wrong address
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Check the withheld amount
            const withheldAmount = await wormholeTargetDispenserL2.withheldAmount();
            expect(Number(withheldAmount)).to.equal(stakingIncentive);

            // Send withheld amount from L2 to L1
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [AddressZero, 0]);
            await wormholeTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultMsgValue});
        });

        it("Checks during a message sending on L1 and L2", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            // Try to send a message with a zero cost gas limit
            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [deployer.address, 0]);
            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload, 0)
            ).to.be.revertedWithCustomError(wormholeDepositProcessorL1, "ZeroValue");

            // Try to receive a message by a wrong chain Id
            await expect(
                wormholeDepositProcessorL1.receiveWormholeMessages("0x", [], HashZero, 0, HashZero)
            ).to.be.revertedWithCustomError(wormholeDepositProcessorL1, "WrongChainId");


            // Send a message on L2 with funds for a wrong address
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [deployer.address, defaultGasLimit]);
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Try to send withheld tokens with an incorrect payload
            await expect(
                wormholeTargetDispenserL2.syncWithheldTokens("0x")
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "IncorrectDataLength");

            // Try to send withheld tokens without any msg.value covering the cost
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [deployer.address, 0]);
            await expect(
                wormholeTargetDispenserL2.syncWithheldTokens(bridgePayload)
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "LowerThan");
        });

        it("Verify senders info on L1 and L2", async function () {
            // Encode the staking data to emulate it being received on L2
            const stakingTarget = stakingInstance.address;
            const stakingIncentive = defaultAmount;

            let bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [AddressZero, defaultGasLimit]);

            // Set the bridge mode to wrong chain Id
            await bridgeRelayer.setMode(3);

            // Try to send tokens and message with the wrong chainId
            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "WrongChainId");

            // Try to send tokens and message with the wrong token
            await bridgeRelayer.setMode(4);

            const ERC20TokenOwnerless = await ethers.getContractFactory("ERC20TokenOwnerless");
            const wrongToken = await ERC20TokenOwnerless.deploy();
            await wrongToken.deployed();

            await bridgeRelayer.setWrongToken(wrongToken.address);

            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "WrongTokenAddress");

            // Try to send tokens and message with the wrong number of tokens
            await bridgeRelayer.setWrongToken(AddressZero);
            await bridgeRelayer.setMode(5);
            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, stakingTarget, stakingIncentive, bridgePayload,
                    stakingIncentive, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "WrongAmount");

            // Send a message on L2 with funds when the delivery hash was already used
            await bridgeRelayer.setMode(6);
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});
            await expect(
                dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                    stakingIncentive, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "AlreadyDelivered");

            // Send a message on L2 with funds for the wrong address
            await bridgeRelayer.setMode(0);
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});

            // Try to send withheld amount from L2 to L1 with the wrong chain Id
            await bridgeRelayer.setMode(3);
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [AddressZero, 0]);
            await expect(
                wormholeTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "WrongChainId");

            // Try to send withheld amount from L2 to L1 with already used hash
            await bridgeRelayer.setMode(6);
            // Sync withheld once with the correct nonce
            await wormholeTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultMsgValue});
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [AddressZero, defaultGasLimit]);
            // Need to create a withheld condition again by sending another staking to a wrong address
            await dispenser.mintAndSend(wormholeDepositProcessorL1.address, deployer.address, stakingIncentive, bridgePayload,
                stakingIncentive, {value: defaultMsgValue});
            // Now the delivery hash will fail
            bridgePayload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [AddressZero, 0]);
            await expect(
                wormholeTargetDispenserL2.syncWithheldTokens(bridgePayload, {value: defaultMsgValue})
            ).to.be.revertedWithCustomError(wormholeTargetDispenserL2, "AlreadyDelivered");
        });
    });
});
