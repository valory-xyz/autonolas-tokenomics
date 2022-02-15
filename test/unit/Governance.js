/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance unit", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let token;
    let signers;
    const AddressZero = "0x" + "0".repeat(40);
    const safeThreshold = 7;
    const nonce =  0;
    const minDelay = 1;
    const initialVotingDelay = 1; // blocks
    const initialVotingPeriod = 45818; // blocks ±= 1 week
    const initialProposalThreshold = ethers.utils.parseEther("10"); // voting power
    const proposalDescription = "Proposal 0";
    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const Token = await ethers.getContractFactory("veOLA");
        token = await Token.deploy();
        await token.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Governance setup: deploy token, timelock, governorBravo, drop deployer role", async function () {
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
            const governorBravo = await GovernorBravo.deploy(token.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold);
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

        it("Delegation of voting power: delegate 10 eth worth of power to address 1", async function () {
            // Get the list of delegators and a delegatee address
            const numDelegators = 10;
            const delegatee = signers[1].address;

            const balance = await token.balanceOf(signers[0].address);
            expect(ethers.utils.formatEther(balance) > 10).to.be.true;

            // Transfer initial balances to all the gelegators: 1 eth to each
            for (let i = 1; i <= numDelegators; i++) {
                await token.transfer(signers[i].address, ethers.utils.parseEther("1"));
                const balance = await token.balanceOf(signers[i].address);
                expect(ethers.utils.formatEther(balance) == 1).to.be.true;
            }

            // Delegate voting power to a chosen delegatee
            for (let i = 1; i <= numDelegators; i++) {
                await token.connect(signers[i]).delegate(delegatee);
            }

            // Given 1 eth worth of voting power from every address, the cumulative voting power must be 10
            const vPower = await token.getCurrentVotes(delegatee);
            expect(ethers.utils.formatEther(vPower) == 10).to.be.true;

            // The rest of addresses must have zero voting power
            for (let i = 2; i <= numDelegators; i++) {
                expect(await token.getCurrentVotes(signers[i].address)).to.be.equal(0);
            }
        });

        it("Should fail to propose if voting power is not enough for proposalThreshold", async function () {
            // Get the list of delegators and a delegatee address
            const numDelegators = 5;
            const delegatee = signers[1].address;

            const balance = await token.balanceOf(signers[0].address);
            expect(ethers.utils.formatEther(balance) > 10).to.be.true;

            // Transfer initial balances to all the gelegators: 1 eth to each
            for (let i = 1; i <= numDelegators; i++) {
                await token.transfer(signers[i].address, ethers.utils.parseEther("1"));
                const balance = await token.balanceOf(signers[i].address);
                expect(ethers.utils.formatEther(balance) == 1).to.be.true;
            }

            // Delegate voting power to a chosen delegatee
            for (let i = 1; i <= numDelegators; i++) {
                await token.connect(signers[i]).delegate(delegatee);
            }

            // Deploy simple version of a timelock
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

            // Initial proposal threshold is 10 eth, our delegatee voting power is 5 eth
            await expect(
                governorBravo.connect(signers[1]).propose2([AddressZero], [0], ["0x"], proposalDescription)
            ).to.be.revertedWith("GovernorCompatibilityBravo: proposer votes below proposal threshold");

            // Adding voting power, and the proposal must go through
            await token.transfer(signers[1].address, ethers.utils.parseEther("5"));
            await governorBravo.connect(signers[1]).propose2([AddressZero], [0], ["0x"], proposalDescription);
        });
    });
});
