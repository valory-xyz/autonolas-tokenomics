/*global describe, beforeEach, it, context*/
const { ethers, network } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

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
    let genericBondCalculator;
    let router;
    let factory;

    let dai;
    let olas;
    let pairODAI;
    let depository;
    let treasury;
    let treasuryFactory;
    let tokenomics;
    let epochLen = 100;
    let defaultPriceLP = "2" + decimals;

    // 2,000
    let supplyProductOLAS =  "2" + "0".repeat(3) + decimals;
    let pseudoFlashLoan = "2"  + "0".repeat(2) + decimals;
    const maxUint96 = "79228162514264337593543950335";
    const maxUint32 = "4294967295";

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
        await tokenomics.changeIncentiveFractions(50, 33, 17, 100, 0, 0);

        // Deploy generic bond calculator contract
        const GenericBondCalculator = await ethers.getContractFactory("GenericBondCalculator");
        genericBondCalculator = await GenericBondCalculator.deploy(olas.address, tokenomics.address);
        await genericBondCalculator.deployed();
        // Deploy depository contract
        depository = await depositoryFactory.deploy(olas.address, treasury.address, tokenomics.address,
            genericBondCalculator.address);
        // Deploy Attack example
        attackDeposit = await attackDepositFactory.deploy();

        // Change to the correct addresses
        await treasury.changeManagers(AddressZero, AddressZero, depository.address, AddressZero);
        await tokenomics.changeManagers(AddressZero, treasury.address, depository.address, AddressZero);

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
        factory = await Factory.deploy(deployer.address);
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

        const block = await ethers.provider.getBlock("latest");
        conclusion = block.timestamp + timeToConclusion;
    });

    context("Initialization", async function () {
        it("Changing managers and owners", async function () {
            const account = alice;

            // Trying to change owner from a non-owner account address
            await expect(
                depository.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Changing treasury and tokenomics addresses
            await depository.connect(deployer).changeManagers(deployer.address, account.address, AddressZero, AddressZero);
            expect(await depository.treasury()).to.equal(account.address);
            expect(await depository.tokenomics()).to.equal(deployer.address);

            // Changing the owner
            await depository.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                depository.connect(deployer).changeOwner(account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");
        });

        it("Changing Bond Calculator contract", async function () {
            const account = alice;

            // Trying to change bond calculator from a non-owner account address
            await expect(
                depository.connect(account).changeBondCalculator(account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Trying to change bond calculator to a zero address that results in no change
            await depository.connect(deployer).changeBondCalculator(AddressZero);
            expect(await depository.bondCalculator()).to.equal(genericBondCalculator.address);

            // Change bond calculator address
            await depository.connect(deployer).changeBondCalculator(account.address);
            expect(await depository.bondCalculator()).to.equal(account.address);
        });
    });

    context("Bond products", async function () {
        it("Should fail when the LP token is not authorized for the product", async () => {
            // Token address is not enabled
            await expect(
                depository.create(alice.address, defaultPriceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "UnauthorizedToken");

            // Token address is enabled but is not an LP token
            await treasury.enableToken(olas.address);
            await expect(
                depository.create(olas.address, defaultPriceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "UnauthorizedToken");

            // Token is not a contract, so the LP price will not be calculated as the Uniswap pair will fail
            await expect(
                depository.getCurrentPriceLP(alice.address)
            ).to.be.reverted;
        });

        it("Create a product", async () => {
            // Trying to create a product not by the contract owner
            await expect(
                depository.connect(alice).create(pairODAI.address, defaultPriceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Try to give the overflow vesting value
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, supplyProductOLAS, maxUint32)
            ).to.be.revertedWithCustomError(depository, "Overflow");

            // Create a second product, the first one is already created
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Check for the product being active
            expect(await depository.isActiveProduct(bid)).to.equal(true);
            expect(await depository.isActiveProduct(bid + 1)).to.equal(true);
            expect(await depository.isActiveProduct(bid + 2)).to.equal(false);
        });

        it("Should fail when creating a product with a bigger amount than the allowed bond", async () => {
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, maxUint96, vesting)
            ).to.be.revertedWithCustomError(depository, "AmountLowerThan");
        });

        it("Should return IDs of all products", async () => {
            // Create a second bond
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            let [first, second] = await depository.getActiveProducts();
            expect(Number(first)).to.equal(0);
            expect(Number(second)).to.equal(1);
        });

        it("Should include product Id in active products set for the LP token", async () => {
            [id] = await depository.getActiveProducts();
            expect(Number(id)).to.equal(bid);
        });

        it("Get correct active product Ids when closing others", async () => {
            // Create a second bonding product
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Close the first bonding product
            await depository.close(0);
            [first] = await depository.getActiveProducts();
            expect(Number(first)).to.equal(1);
        });

        it("The program should expire in a specified amount of time", async () => {
            const product = await depository.mapBondProducts(bid);
            // timestamps are a bit inaccurate with tests
            var upperBound = conclusion * 1.0033;
            var lowerBound = conclusion * 0.9967;
            expect(Number(product.expiry)).to.be.greaterThan(lowerBound);
            expect(Number(product.expiry)).to.be.lessThan(upperBound);
        });

        it("Should fail when there is no liquidity in the LP token pool", async () => {
            // Create one more ERC20 token
            const ercToken = await olasFactory.deploy();

            // Create an LP token
            await factory.createPair(olas.address, ercToken.address);
            const pAddress = await factory.allPairs(1);
            const pairDOLAS = await ethers.getContractAt("UniswapV2Pair", pAddress);

            // Enable the new LP token without liquidity
            await treasury.enableToken(pairDOLAS.address);

            // Try to create a bonding product with it
            const priceLP = await depository.getCurrentPriceLP(pairDOLAS.address);
            await expect(
                depository.create(pairDOLAS.address, priceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "ZeroValue");
        });

        it("Should fail when there is no OLAS in the LP token", async () => {
            // Create one more ERC20 token
            const ercToken1 = await erc20Token.deploy();
            ercToken1.mint(deployer.address, initialMint);
            const ercToken2 = await erc20Token.deploy();
            ercToken2.mint(deployer.address, initialMint);

            // Create an LP token
            await factory.createPair(ercToken1.address, ercToken2.address);
            const pAddress = await factory.allPairs(1);
            const pairDOLAS = await ethers.getContractAt("UniswapV2Pair", pAddress);

            const amountToken1 = "5"  + "0".repeat(3) + decimals;
            const amountToken2 = "5" + "0".repeat(3) + decimals;
            const minAmountToken1 =  "5" + "0".repeat(2) + decimals;
            const minAmountToken2 = "1" + "0".repeat(3) + decimals;
            const deadline = Date.now() + 1000;
            const toAddress = deployer.address;
            await ercToken1.approve(router.address, LARGE_APPROVAL);
            await ercToken2.approve(router.address, LARGE_APPROVAL);

            await router.connect(deployer).addLiquidity(
                ercToken1.address,
                ercToken2.address,
                amountToken1,
                amountToken2,
                minAmountToken1,
                minAmountToken2,
                toAddress,
                deadline
            );

            // Enable the new LP token without liquidity
            await treasury.enableToken(pairDOLAS.address);

            // Try to create a bonding product with it
            const priceLP = await depository.getCurrentPriceLP(pairDOLAS.address);
            await expect(
                depository.create(pairDOLAS.address, priceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "ZeroValue");
        });

        it("Price LP check for unbalanced pools", async () => {
            // Create one more ERC20 token
            const ercToken = await erc20Token.deploy();
            ercToken.mint(deployer.address, initialMint);

            // Create an LP token
            await factory.createPair(olas.address, ercToken.address);
            const pAddress = await factory.allPairs(1);
            const pairDOLAS = await ethers.getContractAt("UniswapV2Pair", pAddress);

            // 10 vs 10k
            const amountToken1 = "10" + decimals;
            const amountToken2 = "1" + "0".repeat(4) + decimals;
            const minAmountToken1 =  "5" + decimals;
            const minAmountToken2 = "1" + "0".repeat(3) + decimals;
            const deadline = Date.now() + 1000;
            const toAddress = deployer.address;
            await olas.approve(router.address, LARGE_APPROVAL);
            await ercToken.approve(router.address, LARGE_APPROVAL);

            await router.connect(deployer).addLiquidity(
                olas.address,
                ercToken.address,
                amountToken1,
                amountToken2,
                minAmountToken1,
                minAmountToken2,
                toAddress,
                deadline
            );

            // Enable the new LP token without liquidity
            await treasury.enableToken(pairDOLAS.address);

            // Try to create a bonding product with it
            const priceLP = await depository.getCurrentPriceLP(pairDOLAS.address);
            expect(Number(priceLP)).to.greaterThan(0);
        });

        it("Crate several programs", async () => {
            // Create a second product, the first one is already created
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Create a third product
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);

            // Check for the product being active
            expect(await depository.isActiveProduct(bid)).to.equal(true);
            expect(await depository.isActiveProduct(bid + 1)).to.equal(true);
            expect(await depository.isActiveProduct(bid + 2)).to.equal(true);

            // Get active bond programs
            let activePrograms = await depository.getActiveProducts();
            expect(activePrograms.length).to.equal(3);
            for (let i = 0; i < activePrograms.length; i++) {
                expect(activePrograms[i]).to.equal(bid + i);
            }

            // Close the first program
            await depository.close(bid + 1);
            // Check for active programs
            activePrograms = await depository.getActiveProducts();
            expect(activePrograms.length).to.equal(2);
            expect(activePrograms[0]).to.equal(bid);
            expect(activePrograms[1]).to.equal(bid + 2);
        });
    });

    context("Bond deposits", async function () {
        it("Deposit to a bonding product for the OLAS payout", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(bid, bamount);
            expect(Array(await depository.getPendingBonds(bob.address)).length).to.equal(1);
            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 = 1250 * e18 =  1.25 * e21
            expect(Number(res.payout)).to.equal(1.25e+21);
        });

        it("Should not allow to deposit after the bonding product is expired", async () => {
            const bamount = (await pairODAI.balanceOf(bob.address));
            await network.provider.send("evm_increaseTime", [vesting+60]);
            await expect(
                depository.connect(bob).deposit(bid, bamount)
            ).to.be.revertedWithCustomError(depository, "ProductExpired");
        });

        it("Should not allow a deposit with insufficient allowance", async () => {
            let amount = (await pairODAI.balanceOf(bob.address));
            await expect(
                depository.connect(deployer).deposit(bid, amount)
            ).to.be.revertedWithCustomError(treasury, "InsufficientAllowance");
        });

        it("Should not allow a deposit greater than max payout", async () => {
            const amount = (await pairODAI.balanceOf(deployer.address));

            // Trying to deposit the amount that would result in an overflow payout for the LP supply
            await pairODAI.connect(deployer).approve(treasury.address, LARGE_APPROVAL);

            await expect(
                depository.connect(deployer).deposit(bid, amount)
            ).to.be.revertedWithCustomError(depository, "ProductSupplyLow");
        });
    });

    context("Redeem", async function () {
        it("Should not redeem before the product is vested", async () => {
            let balance = await olas.balanceOf(bob.address);
            let bamount = (await pairODAI.balanceOf(bob.address));
            // console.log("bob LP:%s depoist:%s",bamount,amount);
            await depository.connect(bob).deposit(bid, bamount);
            await expect(
                depository.connect(bob).redeem([0])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Check that the OLAS balance was not changed
            expect(await olas.balanceOf(bob.address)).to.equal(balance);
        });

        it("Redeem OLAS after the product is vested", async () => {
            let amount = (await pairODAI.balanceOf(bob.address));
            let [expectedPayout,,] = await depository.connect(bob).callStatic.deposit(bid, amount);
            // console.log("[expectedPayout, expiry, index]:",[expectedPayout, expiry, index]);
            await depository.connect(bob).deposit(bid, amount);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            await depository.connect(bob).redeem([0]);
            const bobBalance = Number(await olas.balanceOf(bob.address));
            expect(bobBalance).to.greaterThanOrEqual(Number(expectedPayout));
            expect(bobBalance).to.lessThan(Number(expectedPayout * 1.0001));
            // Check for pending bonds after the redeem
            const pendingBonds = await depository.getPendingBonds(bob.address);
            expect(pendingBonds.bondIds).to.deep.equal([]);
            expect(pendingBonds.payout).to.equal(0);
        });

        it("Close a product", async () => {
            let product = await depository.mapBondProducts(bid);
            expect(Number(product.supply)).to.be.greaterThan(0);

            // Trying to close a product not by the contract owner
            await expect(
                depository.connect(alice).close(bid)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            await depository.close(bid);

            // Try to close the bond product again
            await expect(
                depository.close(bid)
            ).to.be.revertedWithCustomError(depository, "ProductClosed");
            product = await depository.mapBondProducts(bid);
            expect(Number(product.supply)).to.equal(0);
        });

        it("Create a bond product, deposit, then close it", async () => {
            // Transfer more LP tokens to Bob
            const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);
            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            await depository.connect(bob).deposit(bid, bamount);
            await depository.close(bid);
        });

        it("Create a bond product, deposit, then close via redeem", async () => {
            // Transfer more LP tokens to Bob
            const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);

            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            await depository.connect(bob).deposit(bid, bamount);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            // Redeem the bond
            await depository.connect(bob).redeem([0]);
            // Try to close the already closed bond program
            await expect(
                depository.close(bid)
            ).to.be.revertedWithCustomError(depository, "ProductClosed");
        });

        it("Create a bond product, deposit, then close the product right away and try to redeem after", async () => {
            const amountOLASBefore = ethers.BigNumber.from(await olas.balanceOf(bob.address));

            // Transfer more LP tokens to Bob
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);

            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            let [expectedPayout,,] = await depository.connect(bob).callStatic.deposit(bid, bamount);
            await depository.connect(bob).deposit(bid, bamount);

            // Close the program right away
            await depository.close(bid);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            // Redeem the bond
            await depository.connect(bob).redeem([0]);
            // Check the balance after redeem
            const amountOLASAfter = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            expect(amountOLASAfter.sub(amountOLASBefore)).to.equal(expectedPayout);
        });

        it("Manipulate with different bonds", async () => {
            // Make two deposits for the same program
            const amount = ethers.BigNumber.from(await pairODAI.balanceOf(bob.address)).div(4);
            const deviation = ethers.BigNumber.from(await pairODAI.balanceOf(bob.address)).div(20);
            const amounts = [amount.add(deviation), amount, amount.add(deviation).add(deviation)];

            // Deposit a bond for bob (bondId == 0)
            await depository.connect(bob).deposit(bid, amounts[0]);
            // Transfer LP tokens from bob to alice
            await pairODAI.connect(bob).transfer(alice.address, amount);
            // Deposit from alice to the same program (bondId == 1)
            await depository.connect(alice).deposit(bid, amounts[1]);
            // Deposit to another bond for bob (bondId == 2)
            await depository.connect(bob).deposit(bid, amounts[2]);

            // Check for the active products
            let activeProducts = await depository.getActiveProducts();
            expect(activeProducts.length).to.equal(1);
            expect(activeProducts[0]).to.equal(bid);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);

            // Try to redeem the same bond twice
            await expect(
                depository.connect(bob).redeem([0, 0, 2])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Try to redeem the bond that does not exist
            await expect(
                depository.connect(bob).redeem([0, 2, 3])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Try to redeem the bond that belongs to another account
            await expect(
                depository.connect(bob).redeem([0, 1, 2])
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Get all redeemable bonds for bob
            let bondsToRedeem = await depository.getPendingBonds(bob.address);
            expect(bondsToRedeem.bondIds.length).to.equal(2);
            expect(bondsToRedeem.bondIds[0]).to.equal(0);
            expect(bondsToRedeem.bondIds[1]).to.equal(2);

            // Redeem all bonds for bob and verify the obtained OLAS result
            const amountOLASBefore = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            await depository.connect(bob).redeem([0, 2]);
            const amountOLASAfter = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            expect(amountOLASAfter.sub(amountOLASBefore)).to.equal(bondsToRedeem.payout);

            // Check that the bond product is not active
            expect(await depository.isActiveProduct(bid)).to.equal(false);
            activeProducts = await depository.getActiveProducts();
            expect(activeProducts).to.deep.equal([]);

            // Try to get redeemable bonds for bob once again
            bondsToRedeem = await depository.getPendingBonds(bob.address);
            expect(bondsToRedeem.bondIds).to.deep.equal([]);
            expect(bondsToRedeem.payout).to.equal(0);

            // Try to redeem already redeemed bonds
            await expect(
                depository.connect(bob).redeem([0])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");
            await expect(
                depository.connect(bob).redeem([2])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Get pending bonds for alice
            bondsToRedeem = await depository.getPendingBonds(alice.address);
            expect(bondsToRedeem.bondIds.length).to.equal(1);
            expect(bondsToRedeem.bondIds[0]).to.equal(1);

            // Redeem alice bonds
            await depository.connect(alice).redeem([1]);

            // Try to close the already closed bond program
            await expect(
                depository.close(bid)
            ).to.be.revertedWithCustomError(depository, "ProductClosed");
        });
    });

    context("Attacks", async function () {
        it("Proof of protect against attack via smart-contract use deposit", async () => {
            const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(bob.address));
            // Transfer all LP tokens back to deployer
            // await pairODAI.connect(bob).transfer(deployer.address, amountTo);
            await pairODAI.connect(bob).transfer(attackDeposit.address, amountTo);

            // Trying to deposit the amount that would result in an overflow payout for the LP supply
            const payout = await attackDeposit.callStatic.flashAttackDepositImmune(depository.address, treasury.address,
                pairODAI.address, olas.address, bid, amountTo, router.address);

            // Try to attack via flash loan
            await attackDeposit.flashAttackDepositImmune(depository.address, treasury.address, pairODAI.address, olas.address,
                bid, amountTo, router.address);

            // Check that the flash attack did not do anything but obtained the same bond as everybody
            const res = await depository.getBondStatus(0);
            expect(res.payout).to.equal(payout);

            // We know that the payout for any account under these parameters must be 1.25 * e21
            expect(Number(res.payout)).to.equal(1.25e+21);
        });
    });
});
