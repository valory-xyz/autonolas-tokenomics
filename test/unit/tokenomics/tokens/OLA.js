/*global describe, context, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ERC20 OLA with treasury", () => {
    let deployer;
    let treasury;
    let bob;
    let alice;
    let ola;
    let olaFactory;
    const initSupply = "5" + "0".repeat(26);
    const oneYear = 365 * 86400;
    const threeYears = 3 * oneYear;
    const nineYears = 9 * oneYear;
    const tenYears = 10 * oneYear;

    beforeEach(async () => {
        [deployer, treasury, bob, alice] = await ethers.getSigners();
        olaFactory = await ethers.getContractFactory("OLA");
        [deployer, treasury, bob, alice] = await ethers.getSigners();
        // Treasury address is deployer by default
        ola = await olaFactory.deploy(initSupply, deployer.address);
        // Changing the treasury address
        await ola.connect(deployer).changeTreasury(treasury.address);
        //console.log("Deployer:",deployer.address);
        //console.log("Vault:",treasury.address);
        //const newVault = await ola.treasury();
        //console.log("Vault in OLA:",newVault);
    });

    context("initialization", () => {
        it("correctly constructs an ERC20", async () => {
            expect(await ola.name()).to.equal("OLA Token");
            expect(await ola.symbol()).to.equal("OLA");
            expect(await ola.decimals()).to.equal(18);
        });
    });

    context("mint", () => {
        it("must be done by treasury", async () => {
            await expect(ola.connect(bob).mint(bob.address, 100)).to.be.revertedWith(
                "ManagerOnly"
            );
        });

        it("increases total supply", async () => {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(treasury).mint(bob.address, 100);
            expect(supplyBefore.add(100)).to.equal(await ola.totalSupply());
        });
    });

    context("burn", () => {
        beforeEach(async () => {
            await ola.connect(treasury).mint(bob.address, 100);
        });

        it("reduces the total supply", async () => {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(bob).burn(10);
            expect(supplyBefore.sub(10)).to.equal(await ola.totalSupply());
        });

        it("cannot exceed total supply", async () => {
            const supply = await ola.totalSupply();
            await expect(ola.connect(bob).burn(supply.add(1))).to.be.revertedWith(
                "ERC20: burn amount exceeds balance"
            );
        });

        it("cannot exceed bob's balance", async () => {
            await ola.connect(treasury).mint(alice.address, 15);
            await expect(ola.connect(alice).burn(16)).to.be.revertedWith(
                "ERC20: burn amount exceeds balance"
            );
        });
    });

    context("Mint schedule", () => {
        it("Should fail when mint more than a supplyCap within the first ten years", async () => {
            const supplyCap = await ola.supplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            await expect(ola.connect(treasury).mint(deployer.address, amount)).to.be.revertedWith("WrongAmount");

            // Move 9 years in time
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + nineYears + 1000]);

            // Mint up to the supply cap
            amount = "5" + "0".repeat(26);
            await ola.connect(treasury).mint(deployer.address, amount);

            // Check the total supply that must be equal to the supply cap
            const totalSupply = await ola.totalSupply();
            expect(totalSupply).to.equal(supplyCap);
        });

        it("Mint and burn after ten years", async () => {
            const supplyCap = await ola.supplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            await expect(ola.connect(treasury).mint(deployer.address, amount)).to.be.revertedWith("WrongAmount");

            // Move 10 years in time
            let blockNumber = await ethers.provider.getBlockNumber();
            let block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + tenYears + 1000]);

            let totalSupply = new ethers.BigNumber.from(await ola.totalSupply());
            const supplyCapFraction = await ola.maxMintCapFraction();
            let expectedSupplyCap = totalSupply.add(totalSupply.mul(supplyCapFraction).div(100));

            // Mint up to the supply cap that is up to the renewed supply cap after ten years
            // New total supply is 500 * 1.02 = 510 million. We can safely mint 9 million
            amount = "9" + "0".repeat(24);
            let totalSupplyAfterTenYears = totalSupply;
            await ola.connect(treasury).mint(deployer.address, amount);
            expect(await ola.totalSupplyAfterTenYears()).to.equal(totalSupplyAfterTenYears);
            const updatedTotalSupply = await ola.totalSupply();
            expect(Number(updatedTotalSupply)).to.be.lessThan(Number(expectedSupplyCap));
            //console.log("updated total supply", updatedTotalSupply);

            // Mint more than a new total supply must fail
            amount = "2" + "0".repeat(24);
            await expect(ola.connect(treasury).mint(deployer.address, amount)).to.be.revertedWith("WrongAmount");

            // Move 3 more years in time, in addition to what we have already surpassed 10 years
            // So it will be the beginning of a year 4 after first 10 years
            blockNumber = await ethers.provider.getBlockNumber();
            block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + threeYears + 1000]);
            // Calculate max supply cap after 4 years in total
            expectedSupplyCap = new ethers.BigNumber.from(totalSupplyAfterTenYears);
            for (let i = 0; i < 4; ++i) {
                expectedSupplyCap = expectedSupplyCap.add(expectedSupplyCap.mul(supplyCapFraction).div(100));
            }

            // The max supply now is 541,216,080 * E18
            // Mint 30 million more
            amount = "3" + "0".repeat(25);
            await ola.connect(treasury).mint(deployer.address, amount);

            // Mint 5 more million must fail
            amount = "5" + "0".repeat(24);
            await expect(ola.connect(treasury).mint(deployer.address, amount)).to.be.revertedWith("WrongAmount");

            // Burn 10 million
            amount = "1" + "0".repeat(25);
            await ola.connect(deployer).burn(amount);
            // Updated supply must not decrease since it didn't drop to the ten year total supply
            expect(await ola.totalSupplyAfterTenYears()).to.equal(totalSupplyAfterTenYears);

            // Burn the amount below the 10 years total supply
            totalSupply = new ethers.BigNumber.from(await ola.totalSupply());
            amount = "5" + "0".repeat(26);
            await ola.connect(deployer).burn(amount);
            // Updated supply must decrease to the burned amount
            totalSupplyAfterTenYears = totalSupply.sub(amount);
            expect(await ola.totalSupplyAfterTenYears()).to.equal(totalSupplyAfterTenYears);
        });
    });
});
