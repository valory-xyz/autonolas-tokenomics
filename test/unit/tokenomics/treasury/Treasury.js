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
    let olaFactory;
    let treasuryFactory;
    let tokenomicsFactory;
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let dai;
    let lpToken;
    let ola;
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
        olaFactory = await ethers.getContractFactory("OLA");
        treasuryFactory = await ethers.getContractFactory("Treasury");
        tokenomicsFactory = await ethers.getContractFactory("Tokenomics");

        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", agentRegistry.address);
        await serviceRegistry.deployed();
    });

    // These should not be in beforeEach.
    beforeEach(async () => {
        dai = await erc20Token.deploy();
        lpToken = await erc20Token.deploy();
        ola = await olaFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy(ola.address, deployer.address, deployer.address, epochLen, componentRegistry.address,
            agentRegistry.address, serviceRegistry.address);
        // Depository contract is irrelevant here, so we are using a deployer's address
        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        treasury = await treasuryFactory.deploy(ola.address, deployer.address, tokenomics.address, AddressZero);
        // Change to the correct treasury address
        await tokenomics.changeTreasury(treasury.address);
        
        await dai.mint(deployer.address, initialMint);
        await dai.approve(treasury.address, LARGE_APPROVAL);
        await treasury.changeDepository(deployer.address);
        await ola.changeTreasury(treasury.address);

        // toggle DAI as reserve token (as example)
        await treasury.enableToken(dai.address);
        // toggle liquidity depositor (as example)
        await treasury.enableToken(lpToken.address);

        // Deposit 10,000 DAI to treasury,  1,000 OLA gets minted to deployer with 9000 as excess reserves (ready to be minted)
        await treasury
            .connect(deployer)
            .depositTokenForOLA("10000000000000000000000", dai.address, "1000000000000000000000");
    });

    it("deposit ok", async () => {
        expect(await ola.totalSupply()).to.equal("1000000000000000000000");
    });

    it("withdraw ok", async () => {
        await treasury
            .connect(deployer)
            .withdraw(deployer.address, "10000000000000000000000", dai.address);
        expect(await dai.balanceOf(deployer.address)).to.equal("10000000000000000000000000"); // back to initialMint
    });
        
});
