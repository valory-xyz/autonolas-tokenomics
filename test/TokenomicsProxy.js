/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("TokenomicsProxy", async () => {
    const AddressZero = "0x" + "0".repeat(40);

    let TokenomicsProxy;
    let tokenomicsProxy;
    let mockTokenomics;
    let tokenomics;
    let proxyData;

    // These should not be in beforeEach.
    beforeEach(async () => {
        const MockTokenomics = await ethers.getContractFactory("MockTokenomics");
        mockTokenomics = await MockTokenomics.deploy();
        await mockTokenomics.deployed();

        proxyData = mockTokenomics.interface.encodeFunctionData("initialize", []);
        TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
        tokenomicsProxy = await TokenomicsProxy.deploy(mockTokenomics.address, proxyData);
        await tokenomicsProxy.deployed();

        tokenomics = await ethers.getContractAt("MockTokenomics", tokenomicsProxy.address);
    });

    context("Initialization", async function () {
        it("Incorrect initialization parameters", async function () {
            // Try to initialize with the zero master copy address
            await expect(
                TokenomicsProxy.deploy(AddressZero, proxyData)
            ).to.be.revertedWithCustomError(tokenomicsProxy, "ZeroTokenomicsAddress");

            // Try to initialize with the zero data
            await expect(
                TokenomicsProxy.deploy(mockTokenomics.address, "0x")
            ).to.be.revertedWithCustomError(tokenomicsProxy, "ZeroTokenomicsData");
        });


        it("Checking the implementation address", async function () {
            expect(await tokenomics.tokenomicsImplementation()).to.equal(mockTokenomics.address);
        });

        it("Should fail if the initialization is reverted", async function () {
            const proxyData = mockTokenomics.interface.encodeFunctionData("simulateFailure", []);
            await expect(
                TokenomicsProxy.deploy(mockTokenomics.address, proxyData)
            ).to.be.reverted;
        });
    });
});
