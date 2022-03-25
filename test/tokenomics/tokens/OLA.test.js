/*global describe, before, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ERC20 OLA with vault", () => {
    let deployer;
    let vault;
    let bob;
    let alice;
    let ola;
    let olaFactory;

    before(async () => {
        [deployer, vault, bob, alice] = await ethers.getSigners();
        olaFactory = await ethers.getContractFactory("OLA");
    });

    beforeEach(async () => {
        [deployer, vault, bob, alice] = await ethers.getSigners();
        ola = await olaFactory.deploy();
        await ola.connect(deployer).changeTreasury(vault.address);
        //console.log("Deployer:",deployer.address);
        //console.log("Vault:",vault.address);
        //const newVault = await ola.vault();
        //console.log("Vault in OLA:",newVault);
    });

    it("correctly constructs an ERC20", async () => {
        expect(await ola.name()).to.equal("OLA Token");
        expect(await ola.symbol()).to.equal("OLA");
        expect(await ola.decimals()).to.equal(18);
    });

    describe("mint", () => {
        it("must be done by vault", async () => {
            await expect(ola.connect(bob).mint(bob.address, 100)).to.be.revertedWith(
                "Unauthorized"
            );
        });

        it("increases total supply", async () => {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(vault).mint(bob.address, 100);
            expect(supplyBefore.add(100)).to.equal(await ola.totalSupply());
        });
    });

    describe("burn", () => {
        beforeEach(async () => {
            await ola.connect(vault).mint(bob.address, 100);
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
            await ola.connect(vault).mint(alice.address, 15);
            await expect(ola.connect(alice).burn(16)).to.be.revertedWith(
                "ERC20: burn amount exceeds balance"
            );
        });
    });
});
