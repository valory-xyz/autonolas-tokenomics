/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance unit", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let token;
    let escrow;
    let signers;
    const oneWeek = 7 * 86400;
    const oneETHBalance = ethers.utils.parseEther("1");
    const twoETHBalance = ethers.utils.parseEther("2");
    const fiveETHBalance = ethers.utils.parseEther("5");
    const tenETHBalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);
    const safeThreshold = 7;
    const nonce =  0;
    const minDelay = 1;
    const initialVotingDelay = 1; // blocks
    const initialVotingPeriod = 45818; // blocks ±= 1 week
    const initialProposalThreshold = fiveETHBalance; // required voting power
    const quorum = 1; // quorum factor
    const proposalDescription = "Proposal 0";
    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const Token = await ethers.getContractFactory("OLA");
        token = await Token.deploy();
        await token.deployed();

        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
        escrow = await VotingEscrow.deploy(token.address, "Governance OLA", "veOLA", "0.1", AddressZero);
        await escrow.deployed();

        signers = await ethers.getSigners();

        // Mint 10 ETH worth of OLA tokens by default
        await token.mint(signers[0].address, tenETHBalance);
        const balance = await token.balanceOf(signers[0].address);
        expect(ethers.utils.formatEther(balance) == 10).to.be.true;
    });

    context("Initialization", async function () {
        it("Governance setup: deploy escrow, timelock, governorBravo, drop deployer role", async function () {
            // Deploy Safe multisig
            const safeSigners = signers.slice(1, 10).map(
                function (currentElement) {
                    return currentElement.address;
                }
            );

            const setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );

            // Create Safe proxy
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);

            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            // console.log("Safe proxy deployed to", proxyAddress);

            // Deploy Timelock
            const executors = [];
            const proposers = [proxyAddress];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();
            // console.log("Timelock deployed to", timelock.address);

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
            const governorBravo = await GovernorBravo.deploy(escrow.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governorBravo.deployed();
            // console.log("Governor Bravo deployed to", governorBravo.address);

            // Change the admin from deployer to governorBravo
            const deployer = signers[0];
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.connect(deployer).grantRole(adminRole, governorBravo.address);
            await timelock.connect(deployer).renounceRole(adminRole, deployer.address);
            // Check that the deployer does not have rights anymore
            await expect(
                timelock.connect(deployer).revokeRole(adminRole, governorBravo.address)
            ).to.be.revertedWith("AccessControl: account ");
        });

        it("Deposit for voting power: deposit 10 eth worth of escrow to address 1", async function () {
            // Get the list of delegators and a delegatee address
            const numDelegators = 10;
            const delegatee = signers[1].address;

            // Transfer initial balances to all the gelegators: 1 eth to each
            for (let i = 1; i <= numDelegators; i++) {
                await token.transfer(signers[i].address, oneETHBalance);
                const balance = await token.balanceOf(signers[i].address);
                expect(ethers.utils.formatEther(balance) == 1).to.be.true;
            }

            // Approve signers[1]-signers[10] for 1 ETH by voting escrow
            for (let i = 1; i <= numDelegators; i++) {
                await token.connect(signers[i]).approve(escrow.address, oneETHBalance);
            }

            // Define 1 week for the lock duration
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + oneWeek;

            // Deposit tokens as a voting power to a chosen delegatee
            await escrow.connect(signers[1]).createLock(oneETHBalance, lockDuration);
            for (let i = 2; i <= numDelegators; i++) {
                await escrow.connect(signers[i]).depositFor(delegatee, oneETHBalance);
            }

            // Given 1 eth worth of voting power from every address, the cumulative voting power must be 10
            const vPower = await escrow.getVotes(delegatee);
            expect(ethers.utils.formatEther(vPower) > 0).to.be.true;

            // The rest of addresses must have zero voting power
            for (let i = 2; i <= numDelegators; i++) {
                expect(await escrow.getVotes(signers[i].address)).to.be.equal(0);
            }
        });

        it("Should fail to propose if voting power is not enough for proposalThreshold", async function () {
            const balance = await token.balanceOf(signers[0].address);
            expect(ethers.utils.formatEther(balance) == 10).to.be.true;

            // Approve signers[0] for 10 ETH by voting escrow
            await token.connect(signers[0]).approve(escrow.address, tenETHBalance);

            // Define 4 years for the lock duration.
            // This will result in voting power being almost exactly as ETH amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const fourYears = 4 * 365 * oneWeek / 7;
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const lockDuration = block.timestamp + fourYears;

            // Lock 5 ETH, which is lower than the initial proposal threshold by a bit
            await escrow.connect(signers[0]).createLock(fiveETHBalance, lockDuration);

            // Deploy simple version of a timelock
            const executors = [];
            const proposers = [];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
            const governorBravo = await GovernorBravo.deploy(escrow.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governorBravo.deployed();

            // Initial proposal threshold is 10 eth, our delegatee voting power is 5 eth
            await expect(
                // Solidity overridden functions must be explicitly declared
                governorBravo.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                    ["0x"], proposalDescription)
            ).to.be.revertedWith("GovernorCompatibilityBravo: proposer votes below proposal threshold");

            // Adding voting power, and the proposal must go through, 4 + 2 of ETH in voting power is almost 6 > 5 required
            await escrow.connect(signers[0]).increaseAmount(twoETHBalance);
            await governorBravo.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                ["0x"], proposalDescription);
        });
    });
});
