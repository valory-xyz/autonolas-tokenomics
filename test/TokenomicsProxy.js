/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("TokenomicsProxy", async () => {
    let tokenomicsProxy;
    let mockTokenomics;
    let tokenomics;

    // These should not be in beforeEach.
    beforeEach(async () => {
        const MockTokenomics = await ethers.getContractFactory("MockTokenomics");
        mockTokenomics = await MockTokenomics.deploy();
        await mockTokenomics.deployed();

        const proxyData = mockTokenomics.interface.encodeFunctionData("initialize", []);
        const TokenomicsProxy = await ethers.getContractFactory("TokenomicsProxy");
        tokenomicsProxy = await TokenomicsProxy.deploy(mockTokenomics.address, proxyData);
        await tokenomicsProxy.deployed();

        tokenomics = await ethers.getContractAt("MockTokenomics", tokenomicsProxy.address);
    });

    context("Initialization", async function () {
        it("Checking the implementation address", async function () {
            expect(await tokenomics.tokenomicsImplementation()).to.equal(mockTokenomics.address);
        });
    });
});
