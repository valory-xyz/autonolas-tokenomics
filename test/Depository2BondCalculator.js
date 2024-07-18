/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Depository LP 2 Bond Calculator", async () => {
    // 1 million token
    const LARGE_APPROVAL = ethers.utils.parseEther("1000000");
    // Initial mint for OLAS and DAI (40,000)
    const initialMint = ethers.utils.parseEther("40000");
    const AddressZero = ethers.constants.AddressZero;
    const oneWeek = 86400 * 7;
    const baseURI = "https://localhost/depository/";

    let deployer, alice, bob;
    let erc20Token;
    let olasFactory;
    let depositoryFactory;
    let tokenomicsFactory;
    let bondCalculator;
    let router;
    let factory;

    let dai;
    let olas;
    let pairODAI;
    let depository;
    let treasury;
    let treasuryFactory;
    let tokenomics;
    let ve;
    let epochLen = 86400 * 10;
    let defaultPriceLP = ethers.utils.parseEther("2");

    // 2,000
    let supplyProductOLAS =  ethers.utils.parseEther("2000");
    const maxUint96 = "79228162514264337593543950335";
    const maxUint32 = "4294967295";

    let vesting = 2 * oneWeek;

    let productId = 0;
    let first;
    let id;

    const discountParams = {
        targetVotingPower: ethers.utils.parseEther("10"),
        targetNewUnits: 10,
        weightFactors: new Array(4).fill(100)
    };

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

        dai = await erc20Token.deploy();
        olas = await olasFactory.deploy();

        // Voting Escrow mock
        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy();
        await ve.deployed();

        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy();
        await tokenomics.initializeTokenomics(olas.address, deployer.address, deployer.address, deployer.address,
            ve.address, epochLen, deployer.address, deployer.address, deployer.address, AddressZero);
        // Correct depository address is missing here, it will be defined just one line below
        treasury = await treasuryFactory.deploy(olas.address, tokenomics.address, deployer.address, deployer.address);
        // Change bond fraction to 100% in these tests
        await tokenomics.changeIncentiveFractions(66, 34, 100, 0, 0, 0);

        // Deploy bond calculator contract
        const BondCalculator = await ethers.getContractFactory("BondCalculator");
        bondCalculator = await BondCalculator.deploy(olas.address, tokenomics.address, ve.address, discountParams);
        await bondCalculator.deployed();
        // Deploy depository contract
        depository = await depositoryFactory.deploy("Depository", "OLAS_BOND", baseURI, olas.address,
            tokenomics.address, treasury.address, bondCalculator.address);

        // Change to the correct addresses
        await treasury.changeManagers(AddressZero, depository.address, AddressZero);
        await tokenomics.changeManagers(treasury.address, depository.address, AddressZero);

        // Airdrop from the deployer :)
        await dai.mint(deployer.address, initialMint);
        await olas.mint(deployer.address, initialMint);
        await olas.mint(alice.address, initialMint);

        // Change the minter to treasury
        await olas.changeMinter(treasury.address);

        // Deploy Uniswap factory
        const Factory = await ethers.getContractFactory("ZuniswapV2Factory");
        factory = await Factory.deploy();
        await factory.deployed();
        // console.log("Uniswap factory deployed to:", factory.address);

        // Deploy Uniswap V2 library
        const ZuniswapV2Library = await ethers.getContractFactory("ZuniswapV2Library");
        const zuniswapV2Library = await ZuniswapV2Library.deploy();
        await zuniswapV2Library.deployed();

        // Deploy Router02
        const Router = await ethers.getContractFactory("ZuniswapV2Router", {
            libraries: {
                ZuniswapV2Library: zuniswapV2Library.address,
            },
        });

        router = await Router.deploy(factory.address);
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
        pairODAI = await ethers.getContractAt("ZuniswapV2Pair", pairAddress);
        // let reserves = await pairODAI.getReserves();
        // console.log("olas - DAI reserves:", reserves.toString());
        // console.log("balance dai for deployer:",(await dai.balanceOf(deployer.address)));

        // Add liquidity
        //const amountOLAS = await olas.balanceOf(deployer.address);
        const amountOLAS = ethers.utils.parseEther("5000");
        const amountDAI = ethers.utils.parseEther("5000");
        const minAmountOLA =  ethers.utils.parseEther("500");
        const minAmountDAI = ethers.utils.parseEther("1000");
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
            toAddress
        );

        //console.log("deployer LP balance:", await pairODAI.balanceOf(deployer.address));
        //console.log("LP total supplyProductOLAS:", await pairODAI.totalSupply());
        // send half of the balance from deployer
        const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
        await pairODAI.connect(deployer).transfer(bob.address, amountTo);
        //console.log("balance LP for bob:", (await pairODAI.balanceOf(bob.address)));
        //console.log("deployer LP new balance:", await pairODAI.balanceOf(deployer.address));

        await pairODAI.connect(bob).approve(treasury.address, LARGE_APPROVAL);
        await pairODAI.connect(alice).approve(treasury.address, LARGE_APPROVAL);

        await treasury.enableToken(pairODAI.address);
        const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
        await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
    });

    context("Initialization", async function () {
        it("Changing Bond Calculator owner", async function () {
            const account = alice;

            // Trying to change owner from a non-owner account address
            await expect(
                bondCalculator.connect(alice).changeOwner(alice.address)
            ).to.be.revertedWithCustomError(bondCalculator, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                bondCalculator.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroAddress");

            // Changing the owner
            await bondCalculator.connect(deployer).changeOwner(alice.address);

            // Trying to change owner from the previous owner address
            await expect(
                bondCalculator.connect(deployer).changeOwner(alice.address)
            ).to.be.revertedWithCustomError(bondCalculator, "OwnerOnly");
        });

        it("Should fail when initializing with incorrect values", async function () {
            const defaultDiscountParams = {
                targetVotingPower: 0,
                targetNewUnits: 0,
                weightFactors: new Array(4).fill(2550)
            };

            // Trying to deploy with the zero veOLAS address
            const BondCalculator = await ethers.getContractFactory("BondCalculator");
            await expect(
                BondCalculator.deploy(olas.address, tokenomics.address, AddressZero, defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroAddress");

            // Trying to deploy with the zero targetNewUnits
            await expect(
                BondCalculator.deploy(olas.address, tokenomics.address, ve.address, defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroValue");

            defaultDiscountParams.targetNewUnits = 10;

            // Trying to deploy with the zero targetVotingPower
            await expect(
                BondCalculator.deploy(olas.address, tokenomics.address, ve.address, defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroValue");

            defaultDiscountParams.targetVotingPower = 10;

            // Trying to deploy with the overflow weights
            await expect(
                BondCalculator.deploy(olas.address, tokenomics.address, ve.address, defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "Overflow");
        });

        it("Should fail when changing discount parameters for incorrect values", async function () {
            const defaultDiscountParams = {
                targetVotingPower: 0,
                targetNewUnits: 0,
                weightFactors: new Array(4).fill(2550)
            };

            // Trying to change discount params not by the owner
            await expect(
                bondCalculator.connect(alice).changeDiscountParams(defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "OwnerOnly");

            // Trying to change discount params with the zero targetNewUnits
            await expect(
                bondCalculator.changeDiscountParams(defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroValue");

            defaultDiscountParams.targetNewUnits = 10;

            // Trying to change discount params with the zero targetVotingPower
            await expect(
                bondCalculator.changeDiscountParams(defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "ZeroValue");

            defaultDiscountParams.targetVotingPower = 10;

            // Trying to change discount params with the overflow weights
            await expect(
                bondCalculator.changeDiscountParams(defaultDiscountParams)
            ).to.be.revertedWithCustomError(bondCalculator, "Overflow");

            defaultDiscountParams.weightFactors[3] = 1000;
            // Now able to change discount params
            await bondCalculator.changeDiscountParams(defaultDiscountParams);
        });
    });

    context("Bond deposits", async function () {
        it("Should not allow a deposit with incorrect vesting time", async () => {
            const amount = (await pairODAI.balanceOf(bob.address));

            await expect(
                depository.connect(deployer).deposit(productId, amount, 0)
            ).to.be.revertedWithCustomError(treasury, "LowerThan");

            await expect(
                depository.connect(deployer).deposit(productId, amount, vesting + 1)
            ).to.be.revertedWithCustomError(treasury, "Overflow");
        });

        it("Should not allow a deposit greater than max payout", async () => {
            const amount = (await pairODAI.balanceOf(deployer.address));

            // Trying to deposit the amount that would result in an overflow payout for the LP supply
            await pairODAI.connect(deployer).approve(treasury.address, LARGE_APPROVAL);

            await expect(
                depository.connect(deployer).deposit(productId, amount, vesting)
            ).to.be.revertedWithCustomError(depository, "ProductSupplyLow");
        });

        it("Deposit to a bonding product for the OLAS payout with a full vesting time", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            // Get the full amount of LP tokens and deposit them
            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(productId, bamount, vesting);

            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 = 1250 * e18 =  1.25 * e21
            // The calculated IDF must be bigger
            expect(Number(res.payout)).to.gt(1.25e+21);
        });

        it("Deposit to a bonding product for several amounts", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            // Get the full amount of LP tokens and deposit them
            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(productId, bamount.div(2), vesting);
            await depository.connect(bob).deposit(productId, bamount.div(2), vesting);

            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 / 2 = 1250 * e18 / 2 = 6.25 * e20
            // The calculated IDF must be bigger
            expect(Number(res.payout)).to.gt(6.25e+20);

            const res2 = await depository.getBondStatus(1);
            expect(Number(res2.payout)).to.gt(6.25e+20);

            // The second deposit amount must be smaller as the first one gets a bigger discount factor
            expect(res.payout).to.gt(res2.payout);
        });

        it("Deposit to a bonding product for the OLAS payout with a half vesting time", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            // Get the full amount of LP tokens and deposit them
            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(productId, bamount, oneWeek);

            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 = 1250 * e18 =  1.25 * e21
            // The calculated IDF must be bigger
            expect(Number(res.payout)).to.gt(1.25e+21);
        });

        it("Deposit to a bonding product for the OLAS payout with partial veOLAS limit", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            // Lock OLAS balances with Voting Escrow
            await ve.setWeightedBalance(ethers.utils.parseEther("50"));
            await ve.createLock(bob.address);

            // Get the full amount of LP tokens and deposit them
            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(productId, bamount, oneWeek);

            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 = 1250 * e18 =  1.25 * e21
            // The calculated IDF must be bigger
            expect(Number(res.payout)).to.gt(1.25e+21);
        });
    });
});
