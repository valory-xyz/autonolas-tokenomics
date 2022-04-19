/*global describe, before, beforeEach, it*/
const { ethers, network } = require("hardhat");
const { expect } = require("chai");

describe("Depository LP", async () => {
    const decimals = "0".repeat(18);
    // 1 million token
    const LARGE_APPROVAL = "1" + "0".repeat(6) + decimals;
    // Initial mint for OLA and DAI (40,000)
    const initialMint = "4" + "0".repeat(4) + decimals;
    // Increase timestamp by amount determined by `offset`
    const AddressZero = "0x" + "0".repeat(40);
    const E18 = 1 + "0".repeat(18);

    let deployer, alice, bob;
    let erc20Token;
    let olaFactory;
    let depositoryFactory;
    let tokenomicsFactory;
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let router;

    let dai;
    let ola;
    let pairODAI;
    let depository;
    let treasury;
    let treasuryFactory;
    let tokenomics;
    let epochLen = 100;

    // 5,000
    let supplyProductOLA =  "5" + "0".repeat(3) + decimals;

    let vesting = 60 * 60 * 24;
    let timeToConclusion = 60 * 60 * 24;
    let conclusion;

    var bid = 0;
    let first;
    let id;

    /**
     * Everything in this block is only run once before all tests.
     * This is the home for setup methods
     */
    before(async () => {
        [deployer, alice, bob] = await ethers.getSigners();
        olaFactory = await ethers.getContractFactory("OLA");
        erc20Token = await ethers.getContractFactory("ERC20Token");
        depositoryFactory = await ethers.getContractFactory("Depository");
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

    beforeEach(async () => {
        dai = await erc20Token.deploy();
        ola = await olaFactory.deploy();
        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = await tokenomicsFactory.deploy(ola.address, deployer.address, deployer.address, epochLen, componentRegistry.address,
            agentRegistry.address, serviceRegistry.address);
        // Correct depository address is missing here, it will be defined just one line below
        treasury = await treasuryFactory.deploy(ola.address, deployer.address, tokenomics.address, AddressZero);
        // Change to the correct treasury address
        await tokenomics.changeTreasury(treasury.address);
        // Change to the correct depository address
        depository = await depositoryFactory.deploy(ola.address, treasury.address, tokenomics.address);
        await treasury.changeDepository(depository.address);
        await tokenomics.changeDepository(depository.address);

        // Airdrop from the deployer :)
        await dai.mint(deployer.address, initialMint);
        await ola.mint(deployer.address, initialMint);
        await ola.mint(alice.address, initialMint);
        // Change treasury address
        await ola.changeTreasury(treasury.address);

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

        //        var json = require("../../../artifacts/@uniswap/v2-core/contracts/UniswapV2Pair.sol/UniswapV2Pair.json");
        //        const actual_bytecode1 = json["bytecode"];
        //        const COMPUTED_INIT_CODE_HASH1 = ethers.utils.keccak256(actual_bytecode1);
        //        console.log("init hash:", COMPUTED_INIT_CODE_HASH1, "in UniswapV2Library :: hash:0xe9d807835bf1c75fb519759197ec594400ca78aa1d4b77743b1de676f24f8103");
           
        //const pairODAItxReceipt = await factory.createPair(ola.address, dai.address);
        await factory.createPair(ola.address, dai.address);
        // const pairODAIdata = factory.interface.decodeFunctionData("createPair", pairODAItxReceipt.data);
        // console.log("ola[%s]:DAI[%s] pool", pairODAIdata[0], pairODAIdata[1]); 
        let pairAddress = await factory.allPairs(0);
        // console.log("ola - DAI address:", pairAddress);
        pairODAI = await ethers.getContractAt("UniswapV2Pair", pairAddress);
        // let reserves = await pairODAI.getReserves();
        // console.log("ola - DAI reserves:", reserves.toString());
        // console.log("balance dai for deployer:",(await dai.balanceOf(deployer.address)));
        
        // Add liquidity
        //const amountOLA = await ola.balanceOf(deployer.address);
        const amountOLA = "5"  + "0".repeat(3) + decimals;
        const minAmountOLA =  "5" + "0".repeat(2) + decimals;
        const amountDAI = "1" + "0".repeat(4) + decimals;
        const minAmountDAI = "1" + "0".repeat(3) + decimals;
        const deadline = Date.now() + 1000;
        const toAddress = deployer.address;
        await ola.approve(router.address, LARGE_APPROVAL);
        await dai.approve(router.address, LARGE_APPROVAL);

        await router.connect(deployer).addLiquidity(
            dai.address,
            ola.address,
            amountDAI,
            amountOLA,
            minAmountDAI,
            minAmountOLA,
            toAddress,
            deadline
        );

        //        console.log("deployer LP balance:", await pairODAI.balanceOf(deployer.address));
        //        console.log("LP total supplyProductOLA:", await pairODAI.totalSupply());
        // send half of the balance from deployer
        const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(deployer.address)).div(2);
        await pairODAI.connect(deployer).transfer(bob.address, amountTo);
        //        console.log("balance LP for bob:", (await pairODAI.balanceOf(bob.address)));
        //        console.log("deployer LP new balance:", await pairODAI.balanceOf(deployer.address));

        await ola.connect(alice).approve(depository.address, LARGE_APPROVAL);
        await dai.connect(bob).approve(depository.address, LARGE_APPROVAL);
        await pairODAI.connect(bob).approve(depository.address, LARGE_APPROVAL);
        await dai.connect(alice).approve(depository.address, supplyProductOLA);

        await treasury.enableToken(pairODAI.address);

        await depository.create(
            pairODAI.address,
            supplyProductOLA,
            vesting
        );
        
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
        await depository.create(
            pairODAI.address,
            supplyProductOLA,
            vesting
        );
        let [first, second] = await depository.getActiveProductsForToken(pairODAI.address);
        expect(Number(first)).to.equal(0);
        expect(Number(second)).to.equal(1);
    });

    it("should update IDs of products", async () => {
        // create a second bond
        await depository.create(
            pairODAI.address,
            supplyProductOLA,
            vesting
        );
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
        await ola.approve(router.address, LARGE_APPROVAL);
        await dai.approve(router.address, LARGE_APPROVAL);

        const bamount = (await pairODAI.balanceOf(bob.address));
        await depository
            .connect(bob)
            .deposit(pairODAI.address, bid, bamount, bob.address);
        expect(Array(await depository.getPendingBonds(bob.address)).length).to.equal(1);
        const res = await depository.getBondStatus(bob.address,0);
        // 2500 * 1.1 = 2750 * e18 =  2.75 * e21
        expect(Number(res.payout)).to.equal(2.75e+21);
    });

    it("should not allow a deposit with insufficient allowance", async () => {
        let amount = (await pairODAI.balanceOf(deployer.address));
        await expect(
            depository.connect(deployer).deposit(pairODAI.address, bid, amount, deployer.address)
        ).to.be.revertedWith("InsufficientAllowance");
    });

    it("should not allow a deposit greater than max payout", async () => {
        const amountTo = new ethers.BigNumber.from(await pairODAI.balanceOf(bob.address));
        // Transfer all LP tokens back to deployer
        await pairODAI.connect(bob).transfer(deployer.address, amountTo);
        const amount = (await pairODAI.balanceOf(deployer.address));
        //        console.log("LP token in:",amount);

        const totalSupply = (await pairODAI.totalSupply());
        // Calculate payout based on the amount of LP
        const token0address = (await pairODAI.token0());
        const token1address = (await pairODAI.token1());
        const token0 = await ethers.getContractAt("ERC20Token", token0address);
        const token1 = await ethers.getContractAt("ERC20Token", token1address);

        // Get the balances of tokens in LP
        let balance0 = (await token0.balanceOf(pairODAI.address));
        let balance1 = (await token1.balanceOf(pairODAI.address));
        //        console.log("token0",token0.address);
        //        console.log("token1",token1.address);
        //        console.log("balance0",balance0);
        //        console.log("balance1",balance1);
        //        console.log("ola token",ola.address);
        //        console.log("totalSupply LP",totalSupply);

        // Token fractions based on the LP tokens amount and total supply
        const amount0 = ethers.BigNumber.from(amount).mul(balance0).div(totalSupply);
        const amount1 = ethers.BigNumber.from(amount).mul(balance1).div(totalSupply);
        //        console.log("token0 amount ref LP",amount0);
        //        console.log("token1 amount ref LP",amount1);

        // This is equivalent to removing the liquidity
        let amountOLA = amount1;
        balance0 = balance0.sub(amount0);
        balance1 = balance1.sub(amount1);
        //        console.log("balance0",balance0);
        //        console.log("balance1",balance1);

        // This is the equivalent of a swap operation to calculate additional OLA
        const reserveIn = balance0;
        const reserveOut = balance1;
        let amountIn = amount0;
        //        console.log("amountIn",amountIn);
        // amountOLA = amountOLA + getAmountOut(amountPairForOLA, reserveIn, reserveOut);

        // We use this tutorial to correctly calculate the in-out amounts:
        // https://ethereum.org/en/developers/tutorials/uniswap-v2-annotated-code/#why-v2
        const amountInWithFee = amountIn.mul(997);
        const numerator = amountInWithFee.div(reserveOut);
        const denominator = (reserveIn.mul(1000)).add(amountInWithFee);
        const amountOut = numerator.div(denominator);
        amountOLA = amountOLA.add(amountOut);
        //        console.log("amountInWithFee",amountInWithFee);
        //        console.log("numerator",numerator);
        //        console.log("denominator",denominator);
        //        console.log("delta amountOut:",amountOut);
        //        console.log("sutotal amountOLA:",amountOLA);
        const payout = await tokenomics.calculatePayoutFromLP(pairODAI.address, amount, 0);
        const df = await tokenomics.getDF(0);

        // Payouts with direct calculation and via DF must be equal
        expect(amountOLA.mul(df).div(E18)).to.equal(payout);
        //        console.log("payout direclty", payout);
        //        console.log("payout via df", amountOLA.mul(df).div(E18));

        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);

        await expect(
            depository.connect(deployer).deposit(pairODAI.address, bid, amount, deployer.address)
        ).to.be.revertedWith("ProductSupplyLow");
    });

    it("should not redeem before vested", async () => {
        let balance = await ola.balanceOf(bob.address);
        let bamount = (await pairODAI.balanceOf(bob.address)); 
        // console.log("bob LP:%s depoist:%s",bamount,amount);
        await depository
            .connect(bob)
            .deposit(pairODAI.address, bid, bamount, bob.address);
        await depository.connect(bob).redeemAll(bob.address);
        expect(await ola.balanceOf(bob.address)).to.equal(balance);
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

        await network.provider.send("evm_increaseTime", [vesting+60]);
        await depository.redeemAll(bob.address);
        const bobBalance = Number(await ola.balanceOf(bob.address));
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
