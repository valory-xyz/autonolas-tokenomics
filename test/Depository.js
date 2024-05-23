/*global describe, beforeEach, it, context*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Depository LP", async () => {
    const decimals = "0".repeat(18);
    // 1 million token
    const LARGE_APPROVAL = "1" + "0".repeat(10) + decimals;
    // Initial mint for OLAS and DAI (40,000)
    const initialMint = "1" + "0".repeat(6) + decimals;
    const AddressZero = "0x" + "0".repeat(40);
    const oneWeek = 86400 * 7;

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
    let epochLen = 86400 * 10;
    let defaultPriceLP = "2" + decimals;

    // 2,000
    let supplyProductOLAS =  "2" + "0".repeat(3) + decimals;
    let pseudoFlashLoan = "2"  + "0".repeat(2) + decimals;
    const maxUint96 = "79228162514264337593543950335";
    const maxUint160 = "1461501637330902918203684832716283019655932542976";
    const maxUint32 = "4294967295";

    let vesting = oneWeek;

    let productId = 0;
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
        attackDepositFactory = await ethers.getContractFactory("DepositAttacker");

        dai = await erc20Token.deploy();
        olas = await olasFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy();
        await tokenomics.initializeTokenomics(olas.address, deployer.address, deployer.address, deployer.address,
            deployer.address, epochLen, deployer.address, deployer.address, deployer.address, AddressZero);
        // Correct depository address is missing here, it will be defined just one line below
        treasury = await treasuryFactory.deploy(olas.address, tokenomics.address, deployer.address, deployer.address);
        // Change bond fraction to 100% in these tests
        await tokenomics.changeIncentiveFractions(66, 34, 100, 0, 0, 0);

        // Deploy generic bond calculator contract
        const GenericBondCalculator = await ethers.getContractFactory("GenericBondCalculator");
        genericBondCalculator = await GenericBondCalculator.deploy(olas.address, tokenomics.address);
        await genericBondCalculator.deployed();
        // Deploy depository contract
        depository = await depositoryFactory.deploy(olas.address, tokenomics.address, treasury.address,
            genericBondCalculator.address);
        // Deploy Attack example
        attackDeposit = await attackDepositFactory.deploy();

        // Change to the correct addresses
        await treasury.changeManagers(AddressZero, depository.address, AddressZero);
        await tokenomics.changeManagers(treasury.address, depository.address, AddressZero);

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

        //const json = require("../../../artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json");
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
        const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
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
        it("Changing managers and owners", async function () {
            const account = alice;

            // Trying to change managers from a non-owner account address
            await expect(
                depository.connect(account).changeManagers(deployer.address, account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Changing treasury and tokenomics addresses
            await depository.connect(deployer).changeManagers(deployer.address, account.address);
            expect(await depository.treasury()).to.equal(account.address);
            expect(await depository.tokenomics()).to.equal(deployer.address);

            // Trying to change to zero addresses and making sure nothing has changed
            await depository.connect(deployer).changeManagers(AddressZero, AddressZero);
            expect(await depository.treasury()).to.equal(account.address);
            expect(await depository.tokenomics()).to.equal(deployer.address);

            // Trying to change owner from a non-owner account address
            await expect(
                depository.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            // Trying to change the owner to the zero address
            await expect(
                depository.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");

            // Changing the owner
            await depository.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                depository.connect(deployer).changeOwner(account.address)
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");
        });

        it("Should fail when deploying with zero addresses", async function () {
            await expect(
                depositoryFactory.deploy(AddressZero, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");

            await expect(
                depositoryFactory.deploy(olas.address, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");

            await expect(
                depositoryFactory.deploy(olas.address, deployer.address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");

            await expect(
                depositoryFactory.deploy(olas.address, deployer.address, deployer.address, AddressZero)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");
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

        it("Should fail if any of bond calculator input addresses is a zero address", async function () {
            const GenericBondCalculator = await ethers.getContractFactory("GenericBondCalculator");
            await expect(
                GenericBondCalculator.deploy(AddressZero, tokenomics.address)
            ).to.be.revertedWithCustomError(genericBondCalculator, "ZeroAddress");
            await expect(
                GenericBondCalculator.deploy(olas.address, AddressZero)
            ).to.be.revertedWithCustomError(genericBondCalculator, "ZeroAddress");
        });
    });

    context("Bond products", async function () {
        it("Should fail when the LP token is not authorized for the product", async () => {
            // Token address is not enabled
            await expect(
                depository.create(alice.address, defaultPriceLP, supplyProductOLAS, vesting)
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
            expect(await depository.isActiveProduct(productId)).to.equal(true);
            expect(await depository.isActiveProduct(productId + 1)).to.equal(true);
            expect(await depository.isActiveProduct(productId + 2)).to.equal(false);
        });

        it("Should fail when creating a product with a bigger amount than the allowed bond", async () => {
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, maxUint96, vesting)
            ).to.be.revertedWithCustomError(depository, "LowerThan");
        });

        it("Should fail when creating a product with a zero supply", async () => {
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, 0, vesting)
            ).to.be.revertedWithCustomError(depository, "ZeroValue");
        });

        it("Should fail when creating a product with a supply bigger than uint96.max", async () => {
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, maxUint96 + "0", vesting)
            ).to.be.revertedWithCustomError(depository, "Overflow");
        });

        it("Should fail when creating a product with priceLP bigger than uint160.max", async () => {
            await expect(
                depository.create(pairODAI.address, maxUint160 + "0", supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "Overflow");
        });

        it("Should fail when creating a product with a vesting time less than the minimum one", async () => {
            const lessThanMinVesting = Number(await depository.MIN_VESTING()) - 1;
            await expect(
                depository.create(pairODAI.address, defaultPriceLP, supplyProductOLAS, lessThanMinVesting)
            ).to.be.revertedWithCustomError(depository, "LowerThan");
        });

        it("Should fail when creating a product close to the uint32.max", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const minVesting = Number(await depository.MIN_VESTING());
            // Move time close to uint32.max
            await helpers.time.increaseTo(Number(maxUint32));

            await expect(
                depository.create(pairODAI.address, defaultPriceLP, supplyProductOLAS, minVesting)
            ).to.be.revertedWithCustomError(depository, "Overflow");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Should fail when creating a bond with a vesting time past the uint32.max", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const minVesting = Number(await depository.MIN_VESTING());
            // Move time close to uint32.max
            await helpers.time.increaseTo(Number(maxUint32) - minVesting - 100);

            // Create a product
            await depository.create(pairODAI.address, defaultPriceLP, supplyProductOLAS, minVesting);

            // Move the time a little bit more
            await helpers.time.increaseTo(Number(maxUint32) - 100);

            await expect(
                depository.connect(bob).deposit(productId, 1)
            ).to.be.revertedWithCustomError(depository, "Overflow");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Should fail when creating a product with a zero token address", async () => {
            await expect(
                depository.create(AddressZero, defaultPriceLP, supplyProductOLAS, vesting)
            ).to.be.revertedWithCustomError(depository, "UnauthorizedToken");
        });

        it("Should return IDs of all products", async () => {
            // Create a second bond
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            let [first, second] = await depository.getProducts(true);
            expect(Number(first)).to.equal(0);
            expect(Number(second)).to.equal(1);
        });

        it("Should include product Id in active products set for the LP token", async () => {
            [id] = await depository.getProducts(true);
            expect(Number(id)).to.equal(productId);
        });

        it("Get correct active product Ids when closing others", async () => {
            // Create a second bonding product
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Close the first bonding product
            await depository.close([0]);
            [first] = await depository.getProducts(true);
            expect(Number(first)).to.equal(1);
        });

        it("Should fail when the vesting time is too big", async () => {
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await expect(
                depository.create(pairODAI.address, priceLP, supplyProductOLAS, maxUint32 + "0")
            ).to.be.revertedWithCustomError(depository, "Overflow");
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

        it("Estimate Price LP influence when remove liquidity of 1%, 20%, 50% and 99.9%", async () => {
            // Create one more ERC20 token
            const ercToken = await erc20Token.deploy();
            ercToken.mint(deployer.address, initialMint);

            // Create an LP token
            await factory.createPair(olas.address, ercToken.address);
            const pAddress = await factory.allPairs(1);
            const pairDOLAS = await ethers.getContractAt("UniswapV2Pair", pAddress);

            // 2k OALS vs 100k non-OLAS
            const amountToken1 = "2" + "0".repeat(3) + decimals;
            const amountToken2 = "1" + "0".repeat(5) + decimals;
            let deadline = Date.now() + 1000;
            const toAddress = deployer.address;
            await olas.approve(router.address, LARGE_APPROVAL);
            await ercToken.approve(router.address, LARGE_APPROVAL);

            // Add LP token liquidity
            await router.connect(deployer).addLiquidity(
                olas.address,
                ercToken.address,
                amountToken1,
                amountToken2,
                amountToken1,
                amountToken2,
                toAddress,
                deadline
            );

            await pairDOLAS.approve(router.address, LARGE_APPROVAL);
            const path = [ercToken.address, olas.address];

            // Check the balance of both pair tokens before removing the liquidity
            const balanceOLASBefore = await olas.balanceOf(deployer.address);
            const balanceERCTokenBefore = await ercToken.balanceOf(deployer.address);

            let swappedBalancesCompare = new Array(4);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Get the minimum LP token amount as a fraction of a pair of 1%
            let minAmount = ethers.BigNumber.from(await pairDOLAS.balanceOf(deployer.address)).div(100);

            // Removing liquidity of a specified minAmount
            await router.connect(deployer).removeLiquidity(
                olas.address,
                ercToken.address,
                minAmount,
                0,
                0,
                toAddress,
                deadline
            );

            // Check the balance of both tokens after removing the liquidity
            let balanceOLASAfter = await olas.balanceOf(deployer.address);
            let balanceERCTokenAfter = await ercToken.balanceOf(deployer.address);
            // Get the difference between the OLAS balance after the liquidity is removed and the initial OLAS balance in ETH values
            let differenceOLAS = Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18;
            //console.log("OLAS difference", Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18);
            //console.log("ERC20Token difference", Number(ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore)) / 10**18);

            // Get the difference between the ERCToken balance after the liquidity is removed and the initial ERCToken balance in ETH values
            let ercTokenAmount = ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore);
            await router.connect(deployer).swapExactTokensForTokens(
                ercTokenAmount,
                0,
                path,
                toAddress,
                deadline
            );

            // Get the OLAS balance after the swap
            let balanceOLASAfterSwap = await olas.balanceOf(deployer.address);
            // Compare with the initial OLAS balance
            swappedBalancesCompare[0] = Number(ethers.BigNumber.from(balanceOLASAfterSwap).sub(balanceOLASAfter)) / 10**18;
            //console.log("OLAS difference after swap", swappedBalancesCompare[0]);
            // The ratio between the balance of OLAS after the swap and the initial one is almost 1%
            swappedBalancesCompare[0] = swappedBalancesCompare[0] / differenceOLAS;
            //console.log("Fraction of swapped OLAS compared to the original", swappedBalancesCompare[0]);

            // Restore to the state of the snapshot to try with different LP token amount values
            await snapshot.restore();

            // Get the minimum LP token amount as a fraction of a pair of 20%
            minAmount = ethers.BigNumber.from(await pairDOLAS.balanceOf(deployer.address)).div(5);

            // Removing liquidity of a specified minAmount
            await router.connect(deployer).removeLiquidity(
                olas.address,
                ercToken.address,
                minAmount,
                0,
                0,
                toAddress,
                deadline
            );

            // Check the balance after removing the liquidity
            balanceOLASAfter = await olas.balanceOf(deployer.address);
            balanceERCTokenAfter = await ercToken.balanceOf(deployer.address);
            differenceOLAS = Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18;
            //console.log("OLAS difference", Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18);
            //console.log("ERC20Token difference", Number(ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore)) / 10**18);

            ercTokenAmount = ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore);
            await router.connect(deployer).swapExactTokensForTokens(
                ercTokenAmount,
                0,
                path,
                toAddress,
                deadline
            );

            balanceOLASAfterSwap = await olas.balanceOf(deployer.address);
            swappedBalancesCompare[1] = Number(ethers.BigNumber.from(balanceOLASAfterSwap).sub(balanceOLASAfter)) / 10**18;
            //console.log("OLAS difference after swap", swappedBalancesCompare[0]);
            // The ratio is almost 20%
            swappedBalancesCompare[1] = swappedBalancesCompare[1] / differenceOLAS;
            //console.log("Fraction of swapped OLAS compared to the original", swappedBalancesCompare[0]);

            // Restore to the state of the snapshot
            await snapshot.restore();

            // Get the minimum LP token amount as a fraction of a pair of 50%
            minAmount = ethers.BigNumber.from(await pairDOLAS.balanceOf(deployer.address)).div(2);

            // Removing liquidity of a specified minAmount
            await router.connect(deployer).removeLiquidity(
                olas.address,
                ercToken.address,
                minAmount,
                0,
                0,
                toAddress,
                deadline
            );

            // Check the balance after removing the liquidity
            balanceOLASAfter = await olas.balanceOf(deployer.address);
            balanceERCTokenAfter = await ercToken.balanceOf(deployer.address);
            differenceOLAS = Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18;
            //console.log("OLAS difference", Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18);
            //console.log("ERC20Token difference", Number(ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore)) / 10**18);

            ercTokenAmount = ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore);
            await router.connect(deployer).swapExactTokensForTokens(
                ercTokenAmount,
                0,
                path,
                toAddress,
                deadline
            );

            balanceOLASAfterSwap = await olas.balanceOf(deployer.address);
            swappedBalancesCompare[2] = Number(ethers.BigNumber.from(balanceOLASAfterSwap).sub(balanceOLASAfter)) / 10**18;
            //console.log("OLAS difference after swap", swappedBalancesCompare[0]);
            // The ratio is almost 50%
            swappedBalancesCompare[2] = swappedBalancesCompare[2] / differenceOLAS;
            //console.log("Fraction of swapped OLAS compared to the original", swappedBalancesCompare[0]);

            // Restore to the state of the snapshot
            await snapshot.restore();
            // Get the minimum LP token amount as a fraction of a pair of 99.9%
            minAmount = (ethers.BigNumber.from(await pairDOLAS.balanceOf(deployer.address)).mul(999)).div(1000);

            // Removing liquidity of a specified minAmount
            await router.connect(deployer).removeLiquidity(
                olas.address,
                ercToken.address,
                minAmount,
                0,
                0,
                toAddress,
                deadline
            );

            // Check the balance after removing the liquidity
            balanceOLASAfter = await olas.balanceOf(deployer.address);
            balanceERCTokenAfter = await ercToken.balanceOf(deployer.address);
            differenceOLAS = Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18;
            //console.log("OLAS difference", Number(ethers.BigNumber.from(balanceOLASAfter).sub(balanceOLASBefore)) / 10**18);
            //console.log("ERC20Token difference", Number(ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore)) / 10**18);

            ercTokenAmount = ethers.BigNumber.from(balanceERCTokenAfter).sub(balanceERCTokenBefore);
            await router.connect(deployer).swapExactTokensForTokens(
                ercTokenAmount,
                0,
                path,
                toAddress,
                deadline
            );

            balanceOLASAfterSwap = await olas.balanceOf(deployer.address);
            swappedBalancesCompare[3] = Number(ethers.BigNumber.from(balanceOLASAfterSwap).sub(balanceOLASAfter)) / 10**18;
            //console.log("OLAS difference after swap", swappedBalancesCompare[3]);
            // The ratio is almost 99.9%
            swappedBalancesCompare[3] = swappedBalancesCompare[3] / differenceOLAS;
            //console.log("Fraction of swapped OLAS compared to the original", swappedBalancesCompare[3]);

            // The swapped balance of OLAS with bigger removal of liquidity is always smaller than the
            // swapped balance of OLAS with smaller removal of liquidity
            for (let i = 3; i > 0; i--) {
                expect(swappedBalancesCompare[i]).to.lessThan(swappedBalancesCompare[i - 1]);
            }
        });

        it("Crate several products", async () => {
            // Create a second product, the first one is already created
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Create a third product
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);

            // Check for the product being active
            expect(await depository.isActiveProduct(productId)).to.equal(true);
            expect(await depository.isActiveProduct(productId + 1)).to.equal(true);
            expect(await depository.isActiveProduct(productId + 2)).to.equal(true);

            // Get active bond products
            let activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(3);
            for (let i = 0; i < activeProducts.length; i++) {
                expect(activeProducts[i]).to.equal(productId + i);
            }

            // Close the first product
            await depository.close([productId + 1]);
            // Check for active products
            activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(2);
            expect(activeProducts[0]).to.equal(productId);
            expect(activeProducts[1]).to.equal(productId + 2);
        });
    });

    context("Bond deposits", async function () {
        it("Deposit to a bonding product for the OLAS payout", async () => {
            await olas.approve(router.address, LARGE_APPROVAL);
            await dai.approve(router.address, LARGE_APPROVAL);

            // Try to deposit zero amount of LP tokens
            await expect(
                depository.connect(bob).deposit(productId, 0)
            ).to.be.revertedWithCustomError(depository, "ZeroValue");

            // Get the full amount of LP tokens and deposit them
            const bamount = (await pairODAI.balanceOf(bob.address));
            await depository.connect(bob).deposit(productId, bamount);
            expect(Array(await depository.callStatic.getBonds(bob.address, false)).length).to.equal(1);
            const res = await depository.getBondStatus(0);
            // The default IDF without any incentivized coefficient or epsilon rate is 1
            // 1250 * 1.0 = 1250 * e18 =  1.25 * e21
            expect(Number(res.payout)).to.equal(1.25e+21);
        });

        it("Should not allow to deposit after the bonding product supply is depleted", async () => {
            // Send all remaining LPs to bob
            const balance = await pairODAI.balanceOf(deployer.address);
            await pairODAI.connect(deployer).transfer(bob.address, balance);

            // Get price LP
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);

            // Get the amount of LP to scoop all the product supply
            const product = await depository.mapBondProducts(0);
            const e18 = ethers.BigNumber.from("1" + decimals);
            const numLP = (ethers.BigNumber.from(product.supply).mul(e18)).div(priceLP);
            await depository.connect(bob).deposit(productId, numLP);

            // Trying to supply more to the depleted product
            await expect(
                depository.connect(bob).deposit(productId, 1)
            ).to.be.revertedWithCustomError(depository, "ProductClosed");
        });

        it("Should not allow a deposit with insufficient allowance", async () => {
            let amount = (await pairODAI.balanceOf(bob.address));
            await expect(
                depository.connect(deployer).deposit(productId, amount)
            ).to.be.revertedWithCustomError(treasury, "InsufficientAllowance");
        });

        it("Should not allow a deposit greater than max payout", async () => {
            const amount = (await pairODAI.balanceOf(deployer.address));

            // Trying to deposit the amount that would result in an overflow payout for the LP supply
            await pairODAI.connect(deployer).approve(treasury.address, LARGE_APPROVAL);

            await expect(
                depository.connect(deployer).deposit(productId, amount)
            ).to.be.revertedWithCustomError(depository, "ProductSupplyLow");
        });

        it("Should fail a deposit with the priceLP * tokenAmount overflow", async () => {
            await expect(
                // maxUint96 + maxUint96 in string will give a value of more than max of uint192
                depository.connect(deployer).deposit(productId, maxUint96 + maxUint96)
            ).to.be.revertedWithCustomError(treasury, "Overflow");
        });
    });

    context("Redeem", async function () {
        it("Should not redeem before the product is vested", async () => {
            let balance = await olas.balanceOf(bob.address);
            let bamount = (await pairODAI.balanceOf(bob.address));
            // console.log("bob LP:%s depoist:%s",bamount,amount);
            await depository.connect(bob).deposit(productId, bamount);
            await expect(
                depository.connect(bob).redeem([0])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Check that the OLAS balance was not changed
            expect(await olas.balanceOf(bob.address)).to.equal(balance);
        });

        it("Redeem OLAS after the product is vested", async () => {
            // Try to redeem with empty bond list
            await expect(
                depository.connect(bob).redeem([])
            ).to.be.revertedWithCustomError(depository, "ZeroValue");

            // Try to get pending bonds for the zero address
            await expect(
                depository.getBonds(AddressZero, false)
            ).to.be.revertedWithCustomError(depository, "ZeroAddress");

            // Deposit LP tokens
            let amount = (await pairODAI.balanceOf(bob.address));
            let [expectedPayout,,] = await depository.connect(bob).callStatic.deposit(productId, amount);
            // console.log("[expectedPayout, expiry, index]:",[expectedPayout, expiry, index]);
            await depository.connect(bob).deposit(productId, amount);

            // Increase the time to a half vesting
            await helpers.time.increase(vesting / 2);
            // Check for the matured pending bond which is not yet ready
            let pendingBonds = await depository.callStatic.getBonds(bob.address, true);
            expect(pendingBonds.bondIds).to.deep.equal([]);
            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            // Check for the matured pending bond
            pendingBonds = await depository.callStatic.getBonds(bob.address, true);
            expect(pendingBonds.bondIds[0]).to.equal(0);
            await depository.connect(bob).redeem([0]);
            const bobBalance = Number(await olas.balanceOf(bob.address));
            expect(bobBalance).to.greaterThanOrEqual(Number(expectedPayout));
            expect(bobBalance).to.lessThan(Number(expectedPayout * 1.0001));
            // Check for all pending bonds after the redeem (must be none left)
            pendingBonds = await depository.callStatic.getBonds(bob.address, false);
            expect(pendingBonds.bondIds).to.deep.equal([]);
            expect(pendingBonds.payout).to.equal(0);
        });

        it("Close a product", async () => {
            let product = await depository.mapBondProducts(productId);
            expect(Number(product.supply)).to.be.greaterThan(0);

            // Trying to close a product not by the contract owner
            await expect(
                depository.connect(alice).close([productId])
            ).to.be.revertedWithCustomError(depository, "OwnerOnly");

            await depository.close([productId]);

            // Try to close the bond product again
            const closedProductIds = await depository.callStatic.close([productId]);
            expect(closedProductIds).to.deep.equal([]);
            product = await depository.mapBondProducts(productId);
            expect(Number(product.supply)).to.equal(0);
        });

        it("Create a bond product, deposit, then close it", async () => {
            // Transfer more LP tokens to Bob
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);
            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            await depository.connect(bob).deposit(productId, bamount);
            await depository.close([productId]);
        });

        it("Create a bond product, deposit, then close via redeem", async () => {
            // Transfer more LP tokens to Bob
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);

            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            await depository.connect(bob).deposit(productId, bamount);

            // The product is now closed as its supply has been depleted
            expect(await depository.isActiveProduct(productId)).to.equal(false);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            // Redeem the bond
            await depository.connect(bob).redeem([0]);
            // Try to close the already closed bond product
            const closedProductIds = await depository.callStatic.close([productId]);
            expect(closedProductIds).to.deep.equal([]);
        });

        it("Create a bond product, deposit, then close it, detach depository, then redeem", async () => {
            // Transfer more LP tokens to Bob
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);

            // Deposit for the full amount of OLAS
            const bamount = "1" + "0".repeat(3) + decimals;
            let [expectedPayout,,] = await depository.connect(bob).callStatic.deposit(productId, bamount);
            await depository.connect(bob).deposit(productId, bamount);

            // The product is still open, let's close it
            expect(await depository.isActiveProduct(productId)).to.equal(true);
            await depository.close([productId]);
            expect(await depository.isActiveProduct(productId)).to.equal(false);

            // Now change the depository contract address
            const newDepository = await depositoryFactory.deploy(olas.address, tokenomics.address, treasury.address,
                genericBondCalculator.address);

            // Change to a new depository address
            await treasury.changeManagers(AddressZero, newDepository.address, AddressZero);
            await tokenomics.changeManagers(AddressZero, newDepository.address, AddressZero);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);

            // Redeem the bond and check the OLAS balance
            const balanceBefore = await olas.balanceOf(bob.address);
            await depository.connect(bob).redeem([productId]);
            const balanceAfter = await olas.balanceOf(bob.address);

            const balanceDiff = Number(balanceAfter) - Number(balanceBefore);
            expect(balanceDiff).to.equal(Number(expectedPayout));
        });

        it("Create a bond product, deposit, then close the product right away and try to redeem after", async () => {
            const amountOLASBefore = ethers.BigNumber.from(await olas.balanceOf(bob.address));

            // Transfer more LP tokens to Bob
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(4);
            await pairODAI.connect(deployer).transfer(bob.address, amountTo);

            // Deposit for the full amount of OLAS
            const bamount = "2" + "0".repeat(3) + decimals;
            let [expectedPayout,,] = await depository.connect(bob).callStatic.deposit(productId, bamount);
            await depository.connect(bob).deposit(productId, bamount);

            // Close the product right away
            await depository.close([productId]);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);
            // Redeem the bond
            await depository.connect(bob).redeem([0]);
            // Check the balance after redeem
            const amountOLASAfter = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            expect(amountOLASAfter.sub(amountOLASBefore)).to.equal(expectedPayout);
        });

        it("Crate several products and bonds", async () => {
            // Create a second product, the first one is already created
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            // Create a third product
            await depository.create(pairODAI.address, priceLP, supplyProductOLAS, 2 * vesting);

            // Check product and bond counters at this point of time
            const productCounter = await depository.productCounter();
            expect(productCounter).to.equal(3);
            const bondCounter = await depository.bondCounter();
            expect(bondCounter).to.equal(0);

            // Close tree products
            await depository.connect(deployer).close([0, 1]);

            // Get inactive product Ids
            const inactiveProducts = await depository.getProducts(false);
            expect(inactiveProducts.length).to.equal(2);
            for (let i = 0; i < 2; i++) {
                expect(inactiveProducts[i]).to.equal(i);
            }

            // Get active bond products
            let activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(1);

            // Try to create bond with expired products
            for (let i = 0; i < 2; i++) {
                await expect(
                    depository.connect(bob).deposit(i, 10)
                ).to.be.revertedWithCustomError(depository, "ProductClosed");
            }
            // Create bond
            let bamount = (await pairODAI.balanceOf(bob.address));
            const productId = 2;
            await depository.connect(bob).deposit(productId, bamount);

            // Redeem created bond
            await helpers.time.increase(2 * vesting);
            const bondStatus = await depository.getBondStatus(0);
            expect(bondStatus.payout).to.greaterThan(0);
            expect(bondStatus.matured).to.equal(true);
            await depository.connect(bob).redeem([0]);

            // Get active bond products
            activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(1);
        });

        it("Manipulate with different bonds", async () => {
            // Make two deposits for the same product
            const amount = ethers.BigNumber.from(await pairODAI.balanceOf(bob.address)).div(4);
            const deviation = ethers.BigNumber.from(await pairODAI.balanceOf(bob.address)).div(20);
            const amounts = [amount.add(deviation), amount, amount.add(deviation).add(deviation)];

            // Deposit a bond for bob (bondId == 0)
            await depository.connect(bob).deposit(productId, amounts[0]);
            // Transfer LP tokens from bob to alice
            await pairODAI.connect(bob).transfer(alice.address, amount);
            // Deposit from alice to the same product (bondId == 1)
            await depository.connect(alice).deposit(productId, amounts[1]);
            // Deposit to another bond for bob (bondId == 2)
            await depository.connect(bob).deposit(productId, amounts[2]);

            // Get bond statuses
            let bondStatus;
            for (let i = 0; i < 3; i++) {
                bondStatus = await depository.getBondStatus(0);
                expect(bondStatus.payout).to.greaterThan(0);
                expect(bondStatus.matured).to.equal(false);
            }

            // Check for the active products
            let activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(1);
            expect(activeProducts[0]).to.equal(productId);

            // Increase time such that the vesting is complete
            await helpers.time.increase(vesting + 60);

            // Get bond statuses
            for (let i = 0; i < 3; i++) {
                bondStatus = await depository.getBondStatus(0);
                expect(bondStatus.payout).to.greaterThan(0);
                expect(bondStatus.matured).to.equal(true);
            }

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

            // Get all redeemable (matured) bonds for bob
            let bondsToRedeem = await depository.callStatic.getBonds(bob.address, true);
            expect(bondsToRedeem.bondIds.length).to.equal(2);
            expect(bondsToRedeem.bondIds[0]).to.equal(0);
            expect(bondsToRedeem.bondIds[1]).to.equal(2);

            // Redeem all bonds for bob and verify the obtained OLAS result
            const amountOLASBefore = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            await depository.connect(bob).redeem([0, 2]);
            const amountOLASAfter = ethers.BigNumber.from(await olas.balanceOf(bob.address));
            expect(amountOLASAfter.sub(amountOLASBefore)).to.equal(bondsToRedeem.payout);

            // Get bond statuses
            bondStatus = await depository.getBondStatus(0);
            expect(bondStatus.payout).to.equal(0);
            expect(bondStatus.matured).to.equal(false);
            bondStatus = await depository.getBondStatus(2);
            expect(bondStatus.payout).to.equal(0);
            expect(bondStatus.matured).to.equal(false);

            // Check that the bond product is still active
            expect(await depository.isActiveProduct(productId)).to.equal(true);

            // Try to get redeemable (matured) bonds for bob once again
            bondsToRedeem = await depository.callStatic.getBonds(bob.address, true);
            expect(bondsToRedeem.bondIds).to.deep.equal([]);
            expect(bondsToRedeem.payout).to.equal(0);

            // Try to redeem already redeemed bonds
            await expect(
                depository.connect(bob).redeem([0])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");
            await expect(
                depository.connect(bob).redeem([2])
            ).to.be.revertedWithCustomError(depository, "BondNotRedeemable");

            // Get matured pending bonds for alice
            bondsToRedeem = await depository.callStatic.getBonds(alice.address, true);
            expect(bondsToRedeem.bondIds.length).to.equal(1);
            expect(bondsToRedeem.bondIds[0]).to.equal(1);

            // Redeem alice bonds
            await depository.connect(alice).redeem([1]);

            // Close the bond product
            const closedProductIds = await depository.callStatic.close([productId]);
            expect(closedProductIds[0]).to.equal(0);
            await depository.close([productId]);
        });

        it("Create several bond products, close some of them", async () => {
            const priceLP = await depository.getCurrentPriceLP(pairODAI.address);
            for (let i = 0; i < 4; i++) {
                await depository.create(pairODAI.address, priceLP, supplyProductOLAS, vesting);
            }

            // Close 0, 2, 4
            await depository.close([0, 2, 4]);

            // Get active products
            const activeProducts = await depository.getProducts(true);
            expect(activeProducts.length).to.equal(2);
            expect(activeProducts[0]).to.equal(1);
            expect(activeProducts[1]).to.equal(3);

            // Get inactive products
            const inactiveProducts = await depository.getProducts(false);
            expect(inactiveProducts.length).to.equal(3);
            expect(inactiveProducts[0]).to.equal(0);
            expect(inactiveProducts[1]).to.equal(2);
            expect(inactiveProducts[2]).to.equal(4);
        });
    });

    context("Attacks", async function () {
        it("Proof of protect against attack via smart-contract use deposit", async () => {
            const amountTo = ethers.BigNumber.from(await pairODAI.balanceOf(bob.address));
            // Transfer all LP tokens back to deployer
            // await pairODAI.connect(bob).transfer(deployer.address, amountTo);
            await pairODAI.connect(bob).transfer(attackDeposit.address, amountTo);

            // Trying to deposit the amount that would result in an overflow payout for the LP supply
            const payout = await attackDeposit.callStatic.flashAttackDepositImmuneOriginal(depository.address, treasury.address,
                pairODAI.address, olas.address, productId, amountTo, router.address);

            // Try to attack via flash loan
            await attackDeposit.flashAttackDepositImmuneOriginal(depository.address, treasury.address, pairODAI.address, olas.address,
                productId, amountTo, router.address);

            // Check that the flash attack did not do anything but obtained the same bond as everybody
            const res = await depository.getBondStatus(0);
            expect(res.payout).to.equal(payout);

            // We know that the payout for any account under these parameters must be 1.25 * e21
            expect(Number(res.payout)).to.equal(1.25e+21);
        });
    });
});
