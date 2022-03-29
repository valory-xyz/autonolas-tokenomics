/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance integration", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let testServiceRegistry;
    let token;
    let signers;
    const addressZero = "0x" + "0".repeat(40);
    const bytes32Zero = "0x" + "0".repeat(64);
    const minDelay = 1;
    const initialVotingDelay = 0; // blocks
    const initialVotingPeriod = 1; // blocks
    const initialProposalThreshold = ethers.utils.parseEther("10"); // voting power
    const proposalDescription = "Proposal to change value";
    const controlValue = 20;
    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const TestServiceRegistry = await ethers.getContractFactory("TestServiceRegistry");
        testServiceRegistry = await TestServiceRegistry.deploy("service registry", "SERVICE", addressZero);
        await testServiceRegistry.deployed();

        const Token = await ethers.getContractFactory("veOLA");
        token = await Token.deploy();
        await token.deployed();

        signers = await ethers.getSigners();
    });

    context("Controlling other contracts", async function () {
        it("Governance setup and control via proposal roles", async function () {
            // Deploy Timelock
            const executors = [signers[0].address];
            const proposers = [signers[0].address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();
            // console.log("Timelock deployed to", timelock.address);

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
            const governorBravo = await GovernorBravo.deploy(token.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold);
            await governorBravo.deployed();
            // console.log("Governor Bravo deployed to", governorBravo.address);

            // Setting the governor of a controlled contract
            testServiceRegistry.changeManager(timelock.address);

            // Schedule an operation from timelock via a proposer (deployer by default)
            const callData = testServiceRegistry.interface.encodeFunctionData("executeByGovernor", [controlValue]);
            await timelock.schedule(testServiceRegistry.address, 0, callData, bytes32Zero, bytes32Zero, minDelay);

            // Waiting for the next minDelay blocks to pass
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + minDelay * 86460]);

            // Execute the proposed operation and check the execution result
            await timelock.execute(testServiceRegistry.address, 0, callData, bytes32Zero, bytes32Zero);
            const newValue = await testServiceRegistry.getControlValue();
            expect(newValue).to.be.equal(controlValue);
        });

        it("Governance setup and control via delegator proposal", async function () {
            // Delegate the voting power
            await token.delegate(signers[0].address);

            // Deploy Timelock
            const executors = [];
            const proposers = [];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
            const governorBravo = await GovernorBravo.deploy(token.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold);
            await governorBravo.deployed();

            // Grand governorBravo an admin, proposer and executor role in the timelock
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.grantRole(adminRole, governorBravo.address);
            const proposerRole = ethers.utils.id("PROPOSER_ROLE");
            await timelock.grantRole(proposerRole, governorBravo.address);
            const executorRole = ethers.utils.id("EXECUTOR_ROLE");
            await timelock.grantRole(executorRole, governorBravo.address);

            // Setting the governor of a controlled contract
            testServiceRegistry.changeManager(timelock.address);

            // Schedule an operation from timelock via a proposer (deployer by default)
            const callData = testServiceRegistry.interface.encodeFunctionData("executeByGovernor", [controlValue]);
            // Solidity overridden functions must be explicitly declared
            // https://github.com/ethers-io/ethers.js/issues/407
            await governorBravo["propose(address[],uint256[],bytes[],string)"]([testServiceRegistry.address], [0],
                [callData], proposalDescription);

            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governorBravo.hashProposal([testServiceRegistry.address], [0], [callData],
                descriptionHash);

            // If initialVotingDelay is greater than 0 we have to wait that many blocks before the voting starts
            // Casting votes for the proposalId: 0 - Against, 1 - For, 2 - Abstain
            await governorBravo.castVote(proposalId, 1);
            await governorBravo["queue(address[],uint256[],bytes[],bytes32)"]([testServiceRegistry.address], [0],
                [callData], descriptionHash);

            // Waiting for the next minDelay blocks to pass
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + minDelay * 86460]);

            // Execute the proposed operation and check the execution result
            await governorBravo["execute(uint256)"](proposalId);
            const newValue = await testServiceRegistry.getControlValue();
            expect(newValue).to.be.equal(controlValue);
        });
    });
});
