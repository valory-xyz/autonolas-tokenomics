/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceProxyMaster", function () {
    let serviceProxyMaster;
    let defaultFallbackHandler;
    let signers;
    beforeEach(async function () {
        const ServiceProxyMaster = await ethers.getContractFactory("ServiceProxyMaster");
        serviceProxyMaster = await ServiceProxyMaster.deploy();
        await serviceProxyMaster.deployed();

        const DefaultFallbackHandler = await ethers.getContractFactory("DefaultFallbackHandler");
        defaultFallbackHandler = await DefaultFallbackHandler.deploy();
        await defaultFallbackHandler.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Creation of a ServiceProxyMaster", async function () {
            const owners = [signers[1], signers[2]];
            const threshold = owners.length - 1;
            const AddressZero = "0x" + "0".repeat(40);
            await serviceProxyMaster.setup(owners, threshold, AddressZero, "0x", defaultFallbackHandler.address,
                0, 0, AddressZero);
        });
    });
});
