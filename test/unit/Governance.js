/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let token;
    let timelock;
    let signers;
    const AddressZero = "0x" + "0".repeat(40);
    const safeThreshold = 7;
    const nonce =  0;
    const minDelay = 1;
    const initialVotingDelay = 1; // blocks
    const initialVotingPeriod = 45818; // blocks ±= 1 week
    const initialProposalThreshold = 0; // voting power
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
//            console.log("Safe proxy deployed to", proxyAddress);

            // Deploy Timelock
            const executors = [];
            const proposers = [proxyAddress];
            const Timelock = await ethers.getContractFactory("Timelock");
            timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();
//            console.log("Timelock deployed to", timelock.address);

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorBravoOLA");
            const governorBravo = await GovernorBravo.deploy(token.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold);
            await governorBravo.deployed();
//            console.log("Governor Bravo deployed to", governorBravo.address);

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
    });
});
