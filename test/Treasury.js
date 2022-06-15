/*global describe, before, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Treasury", async () => {
    const LARGE_APPROVAL = "100000000000000000000000000000000";
    // const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    // Initial mint for Frax and DAI (10,000,000)
    const initialMint = "10000000000000000000000000";
    const AddressZero = "0x" + "0".repeat(40);

    let deployer;
    let erc20Token;
    let olasFactory;
    let treasuryFactory;
    let tokenomicsFactory;
    let dai;
    let lpToken;
    let olas;
    let treasury;
    let tokenomics;
    const epochLen = 100;

    /**
     * Everything in this block is only run once before all tests.
     * This is the home for setup methodss
     */
    before(async () => {
        // [deployer, alice, bob, carol] = await ethers.getSigners();
        [deployer] = await ethers.getSigners();
        // use dai as erc20 
        erc20Token = await ethers.getContractFactory("ERC20Token");
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        olasFactory = await ethers.getContractFactory("ERC20Token");
        treasuryFactory = await ethers.getContractFactory("Treasury");
        tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
    });

    // These should not be in beforeEach.
    beforeEach(async () => {
        dai = await erc20Token.deploy();
        lpToken = await erc20Token.deploy();
        olas = await olasFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy(olas.address, deployer.address, deployer.address, deployer.address,
            deployer.address, epochLen, AddressZero, AddressZero, AddressZero);
        // Depository contract is irrelevant here, so we are using a deployer's address
        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        treasury = await treasuryFactory.deploy(olas.address, deployer.address, tokenomics.address, AddressZero);
        // Change to the correct treasury address
        await tokenomics.changeManagers(treasury.address, AddressZero, AddressZero, AddressZero);
        
        await dai.mint(deployer.address, initialMint);
        await dai.approve(treasury.address, LARGE_APPROVAL);
        await olas.changeMinter(treasury.address);

        // toggle DAI as reserve token (as example)
        await treasury.enableToken(dai.address);
        // toggle liquidity depositor (as example)
        await treasury.enableToken(lpToken.address);

        // Deposit 10,000 DAI to treasury,  1,000 OLAS gets minted to deployer with 9000 as excess reserves (ready to be minted)
        await treasury
            .connect(deployer)
            .depositTokenForOLA("10000000000000000000000", dai.address, "1000000000000000000000");
    });

    it("Deposit", async () => {
        expect(await olas.totalSupply()).to.equal("1000000000000000000000");
    });

    it("Withdraw", async () => {
        await treasury
            .connect(deployer)
            .withdraw(deployer.address, "10000000000000000000000", dai.address, true);
        expect(await dai.balanceOf(deployer.address)).to.equal("10000000000000000000000000"); // back to initialMint
    });
        
});
