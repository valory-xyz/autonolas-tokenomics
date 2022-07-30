/*global describe, beforeEach, it*/
const { ethers, network } = require("hardhat");
const { expect } = require("chai");
//const { helpers } = require("@nomicfoundation/hardhat-network-helpers");

describe("Depository LP", async () => {
    const decimals = "0".repeat(18);
    // 1 million token
    const LARGE_APPROVAL = "1" + "0".repeat(6) + decimals;
    // Initial mint for OLAS and DAI (40,000)
    const initialMint = "4" + "0".repeat(4) + decimals;

    const AddressZero = "0x" + "0".repeat(40);

    let deployer, alice, bob;
    let erc20Token;
    let olasFactory;
    let depositoryFactory;
    let tokenomicsFactory;
    let router;

    let dai;
    let olas;
    let pairODAI;
    let depository;
    let treasury;
    let treasuryFactory;
    let tokenomics;
    let epochLen = 100;

    // 2,000
    let supplyProductOLA =  "2" + "0".repeat(3) + decimals;
    let pseudoFlashLoan = "2"  + "0".repeat(2) + decimals;

    let vesting = 60 * 60 * 24;
    let timeToConclusion = 60 * 60 * 24;
    let conclusion;

    var bid = 0;
    let first;
    let id;

    let attackDepositFactory;
    let attackDeposit;

    /**
     * Everything in this block is only run once before all tests.
     * This is the home for setup methods
     */

    beforeEach(async () => {
        [deployer, alice, bob] = await ethers.getSigners();
        // Note: this is not a real OLAS token, just an ERC20 mock-up
        olasFactory = await ethers.getContractFactory("ERC20Token");
        erc20Token = await ethers.getContractFactory("ERC20Token");
        depositoryFactory = await ethers.getContractFactory("Depository");
        treasuryFactory = await ethers.getContractFactory("Treasury");
        tokenomicsFactory = await ethers.getContractFactory("Tokenomics");
        attackDepositFactory = await ethers.getContractFactory("AttackDeposit");

        dai = await erc20Token.deploy();
        olas = await olasFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy(olas.address, deployer.address, deployer.address, deployer.address,
            deployer.address, epochLen, AddressZero, AddressZero, AddressZero);
        // Correct depository address is missing here, it will be defined just one line below
        treasury = await treasuryFactory.deploy(olas.address, deployer.address, tokenomics.address, AddressZero);
        // Change bond fraction to 100% in these tests
        await tokenomics.changeRewardFraction(50, 33, 17, 0, 0);
        // Change to the correct depository address
        depository = await depositoryFactory.deploy(olas.address, treasury.address, tokenomics.address);
        // Deploy Attack example
        attackDeposit = await attackDepositFactory.deploy();

        // Change to the correct addresses
        await treasury.changeManagers(depository.address, AddressZero, AddressZero);
        await tokenomics.changeManagers(treasury.address, depository.address, AddressZero, AddressZero);

        // Airdrop from the deployer :)
        await dai.mint(deployer.address, initialMint);
        await olas.mint(deployer.address, initialMint);
        await olas.mint(alice.address, initialMint);

        // Airdrop to Attacker
        await olas.mint(attackDeposit.address, pseudoFlashLoan);

        // Change the minter to treasury
        await olas.changeMinter(treasury.address);

        const wethFactory = await ethers.getContractFactory("WETH9");
        const weth = await wethFactory.deploy();
        // Deploy Uniswap factory
        const Factory = await ethers.getContractFactory("UniswapV2Factory");
        const factory = await Factory.deploy(deployer.address);
        await factory.deployed();
        // console.log("Uniswap factory deployed to:", factory.address);

        // Deploy Router02
        const Router = await ethers.getContractFactory("UniswapV2Router02");
        router = await Router.deploy(factory.address, weth.address);
        await router.deployed();
        // console.log("Uniswap router02 deployed to:", router.address);

        //var json = require("../../../artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json");
        //const actual_bytecode1 = json["bytecode"];
        //const COMPUTED_INIT_CODE_HASH1 = ethers.utils.keccak256(actual_bytecode1);
        //console.log("init hash:", COMPUTED_INIT_CODE_HASH1, "in UniswapV2Library :: hash:0xe9d807835bf1c75fb519759197ec594400ca78aa1d4b77743b1de676f24f8103");

        //const pairODAItxReceipt = await factory.createPair(olas.address, dai.address);
        await factory.createPair(olas.address, dai.address);
        // const pairODAIdata = factory.interface.decodeFunctionData("createPair", pairODAItxReceipt.data);
        // console.log("olas[%s]:DAI[%s] pool", pairODAIdata[0], pairODAIdata[1]);
        let pairAddress = await factory.allPairs(0);
        // console.log("olas - DAI address:", pairAddress);
        pairODAI = await ethers.getContractAt("UniswapV2Pair", pairAddress);
        // let reserves = await pairODAI.getReserves();
        // console.log("olas - DAI reserves:", reserves.toString());
        // console.log("balance dai for deployer:",(await dai.balanceOf(deployer.address)));

        // Add liquidity
        //const amountOLAS = await olas.balanceOf(deployer.address);
        const amountOLAS = "5"  + "0".repeat(3) + decimals;
        const amountDAI = "5" + "0".repeat(3) + decimals;
        const minAmountOLA =  "5" + "0".repeat(2) + decimals;
        const minAmountDAI = "1" + "0".repeat(3) + decimals;
        const deadline = Date.now() + 1000;
        const toAddress = deployer.address;
        await olas.approve(router.address, LARGE_APPROVAL);
        await dai.approve(router.address, LARGE_APPROVAL);

        await router.connect(deployer).addLiquidity(
            dai.address,
            olas.address,
            amountDAI,
            amountOLAS,
            minAmountDAI,
            minAmountOLA,
            toAddress,
            deadline
        );

        //console.log("deployer LP balance:", await pairODAI.balanceOf(deployer.address));
        //console.log("LP total supplyProductOLA:", await pairODAI.totalSupply());
        // send half of the balance from deployer
        const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
        await pairODAI.connect(deployer).transfer(bob.address, amountTo);
        //console.log("balance LP for bob:", (await pairODAI.balanceOf(bob.address)));
        //console.log("deployer LP new balance:", await pairODAI.balanceOf(deployer.address));

        await olas.connect(alice).approve(depository.address, LARGE_APPROVAL);
        await dai.connect(bob).approve(depository.address, LARGE_APPROVAL);
        await pairODAI.connect(bob).approve(depository.address, LARGE_APPROVAL);
        await dai.connect(alice).approve(depository.address, supplyProductOLA);

        await treasury.enableToken(pairODAI.address);

        await depository.create(pairODAI.address, supplyProductOLA, vesting);

        const block = await ethers.provider.getBlock("latest");
        conclusion = block.timestamp + timeToConclusion;
    });

    it("should create product", async () => {
        expect(await depository.isActive(pairODAI.address, bid)).to.equal(true);
    });

    it("should conclude in correct amount of time", async () => {
        let [, , , concludes] = await depository.getProduct(pairODAI.address, bid);
        // console.log(concludes,conclusion);
        // timestamps are a bit inaccurate with tests
        var upperBound = conclusion * 1.0033;
        var lowerBound = conclusion * 0.9967;
        expect(Number(concludes)).to.be.greaterThan(lowerBound);
        expect(Number(concludes)).to.be.lessThan(upperBound);
    });

    it("should return IDs of all products", async () => {
        // create a second bond
        await depository.create(pairODAI.address, supplyProductOLA, vesting);
        let [first, second] = await depository.getActiveProductsForToken(pairODAI.address);
        expect(Number(first)).to.equal(0);
        expect(Number(second)).to.equal(1);
    });

    it("should update IDs of products", async () => {
        // create a second bond
        await depository.create(pairODAI.address, supplyProductOLA, vesting);
        // close the first bond
        await depository.close(pairODAI.address, 0);
        [first] = await depository.getActiveProductsForToken(pairODAI.address);
        expect(Number(first)).to.equal(1);
    });

    it("should include ID in live products for quote token", async () => {
        [id] = await depository.getActiveProductsForToken(pairODAI.address);
        expect(Number(id)).to.equal(bid);
    });

    it("should allow a deposit", async () => {
        await olas.approve(router.address, LARGE_APPROVAL);
        await dai.approve(router.address, LARGE_APPROVAL);

        const bamount = (await pairODAI.balanceOf(bob.address));
        await depository
            .connect(bob)
            .deposit(pairODAI.address, bid, bamount, bob.address);
        expect(Array(await depository.getPendingBonds(bob.address)).length).to.equal(1);
        const res = await depository.getBondStatus(bob.address, 0);
        // 1250 * 1.5 = 1875 * e18 =  1.875 * e21
        expect(Number(res.payout)).to.equal(1.875e+21);
    });

    it("should not allow a deposit with insufficient allowance", async () => {
        let amount = (await pairODAI.balanceOf(bob.address));
        await expect(
            depository.deposit(pairODAI.address, bid, amount, bob.address)
        ).to.be.revertedWithCustomError(depository, "InsufficientAllowance");
    });

    it("should not allow a deposit greater than max payout", async () => {
        const amount = (await pairODAI.balanceOf(deployer.address));

        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);

        await expect(
            depository.connect(deployer).deposit(pairODAI.address, bid, amount, deployer.address)
        ).to.be.revertedWithCustomError(depository, "ProductSupplyLow");
    });

    it("proof of protect against attack via smart-contract use deposit", async () => {
        const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(bob.address));
        // Transfer all LP tokens back to deployer
        // await pairODAI.connect(bob).transfer(deployer.address, amountTo);
        await pairODAI.connect(bob).transfer(attackDeposit.address, amountTo);

        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        //await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        //depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        const payout = await attackDeposit.callStatic.flashAttackDepositImmune(depository.address, pairODAI.address, olas.address,
            bid, amountTo, router.address);

        // Try to attack via flash loan
        await attackDeposit.flashAttackDepositImmune(depository.address, pairODAI.address, olas.address,
            bid, amountTo, router.address);

        // Check that the flash attack did not do anything but obtained the same bond as everybody
        const res = await depository.getBondStatus(attackDeposit.address, 0);
        expect(res.payout).to.equal(payout);

        // We know that the payout for any account under these parameters must be 1.875 * e21
        expect(Number(res.payout)).to.equal(1.875e+21);
    });

    it("should not redeem before vested", async () => {
        let balance = await olas.balanceOf(bob.address);
        let bamount = (await pairODAI.balanceOf(bob.address)); 
        // console.log("bob LP:%s depoist:%s",bamount,amount);
        await depository
            .connect(bob)
            .deposit(pairODAI.address, bid, bamount, bob.address);
        await depository.connect(bob).redeemAll(bob.address);
        expect(await olas.balanceOf(bob.address)).to.equal(balance);
    });
    // ok test 11-03-22
    it("should redeem after vested", async () => {
        let amount = (await pairODAI.balanceOf(bob.address));
        let [expectedPayout,,] = await depository
            .connect(bob)
            .callStatic.deposit(pairODAI.address, bid, amount, bob.address);
        // console.log("[expectedPayout, expiry, index]:",[expectedPayout, expiry, index]);
        await depository
            .connect(bob)
            .deposit(pairODAI.address, bid, amount, bob.address);

        // TODO: Change that to helpers.time.increase(vesting+60)
        await network.provider.send("evm_increaseTime", [vesting+60]);
        await depository.redeemAll(bob.address);
        const bobBalance = Number(await olas.balanceOf(bob.address));
        expect(bobBalance).to.greaterThanOrEqual(Number(expectedPayout));
        expect(bobBalance).to.lessThan(Number(expectedPayout * 1.0001));
    });
    // ok test 11-03-22
    it("should close a product", async () => {
        let product = await depository.getProduct(pairODAI.address, bid);
        expect(Number(product.supply)).to.be.greaterThan(0);
        await depository.close(pairODAI.address, bid);
        product = await depository.getProduct(pairODAI.address, bid);
        expect(Number(product.supply)).to.equal(0);
    });
});
