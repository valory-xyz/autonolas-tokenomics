/*global describe, it, process*/
const {ethers} = require("hardhat");
const {expect} = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const fs = require("fs");
const path = require("path");
const registryOut = process.env.REGISTRIES_OUT;
const governanceOut = process.env.GOVERNANCE_OUT;
const zero = ethers.constants.AddressZero;
const epoch = 30 * 86400;
const budget = 15000000;
const targetCount = 10;
const b32 = (a) => ethers.utils.hexZeroPad(a, 32);

async function deploy(name, args = [], directory = "out") {
    const artifact = JSON.parse(fs.readFileSync(path.join(directory, `${name === "BatchGasBridge" ? "BridgeRelayer" : name}.sol`, `${name}.json`)));
    const bytecode = artifact.bytecode.object || artifact.bytecode;
    const c = await new ethers.ContractFactory(artifact.abi, bytecode, (await ethers.getSigners())[0]).deploy(...args);
    await c.deployed();
    return c;
}

async function fixture(local = false, highIncentive = false) {
    await ethers.provider.send("hardhat_reset", []);
    await helpers.time.setNextBlockTimestamp(2000000000);
    const [owner] = await ethers.getSigners();
    const olas = await deploy("OLAS", [], governanceOut);
    const ve = await deploy("veOLAS", [olas.address, "Voting escrow OLAS", "veOLAS"], governanceOut);
    const registry = owner.address; // Only identity getters are used; no services are registered in this funding test.
    const utility = owner.address;
    const verifier = await deploy("StakingVerifier", [olas.address, registry, utility, ethers.utils.parseEther("1"), 365 * 86400, 44, ethers.utils.parseEther("1")], registryOut);
    const factory = await deploy("StakingFactory", [verifier.address], registryOut);
    const staking = await deploy("StakingToken", [], registryOut);
    await verifier.setImplementationsStatuses([staking.address], [true], true);
    const treasury = await deploy("Treasury", [olas.address, owner.address, owner.address, owner.address]);
    const ti = await deploy("Tokenomics");
    const data = ti.interface.encodeFunctionData("initializeTokenomics", [olas.address, treasury.address, owner.address, owner.address,
        ve.address, epoch, registry, registry, registry, zero]);
    const tp = await deploy("TokenomicsProxy", [ti.address, data]);
    const tokenomics = ti.attach(tp.address);
    const impl = await deploy("Dispenser", [olas.address, tp.address, b32("0x000000000000000000000000000000000000dEaD")]);
    const proxy = await deploy("DispenserProxy", [impl.address, impl.interface.encodeFunctionData("initialize", [treasury.address, zero, 1, targetCount])]);
    const dispenser = impl.attach(proxy.address);
    const vw = await deploy("VoteWeighting", [ve.address, proxy.address], governanceOut);
    await dispenser.changeManagers(zero, vw.address);
    await treasury.changeManagers(tp.address, zero, proxy.address);
    await tokenomics.changeManagers(zero, zero, proxy.address);
    await tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 100);
    await tokenomics.changeStakingParams(ethers.utils.parseEther(highIncentive ? "1000" : "1"), 10);
    await dispenser.setPauseState(0);
    const bridge = await deploy("BatchGasBridge");
    const chain = local ? 31337 : 100;
    const processor = local ? await deploy("EthereumDepositProcessor", [olas.address, proxy.address, factory.address, owner.address]) :
        await deploy("GnosisDepositProcessorL1", [olas.address, proxy.address, bridge.address, bridge.address, chain]);
    const receiver = await deploy("GnosisTargetDispenserL2", [olas.address, factory.address, bridge.address, processor.address, 31337]);
    if (!local) await processor.setL2TargetDispenser(receiver.address);
    await dispenser.setDepositProcessorChainIds([processor.address], [chain]);
    const targets = [];
    for (let i = 0; i < targetCount; i++) {
        // Funding does not call the activity checker or depend on occupied service slots.
        const params = [b32(owner.address), 44, 10000000000, ethers.utils.parseEther("1"), 2, 2, 86400, 365 * 86400,
            1, [], 0, ethers.constants.HashZero, b32(owner.address), registry, olas.address];
        const init = staking.interface.encodeFunctionData("initialize", [params, utility, olas.address]);
        const receipt = await (await factory.createStakingInstance(staking.address, init)).wait();
        const target = receipt.events.find((event) => event.event === "InstanceCreated").args.instance;
        targets.push(staking.attach(target));
    }
    targets.sort((a, b) => a.address.toLowerCase().localeCompare(b.address.toLowerCase()));
    await olas.mint(owner.address, ethers.utils.parseEther("1000000"));
    await olas.approve(ve.address, ethers.utils.parseEther("1000000"));
    await ve.createLock(ethers.utils.parseEther("1000000"), 4 * 365 * 86400);
    await olas.changeMinter(treasury.address);
    await helpers.time.increase(epoch);
    await tokenomics.checkpoint();
    for (const target of targets) {
        await vw.addNomineeEVM(target.address, chain);
        await vw.voteForNomineeWeights(b32(target.address), chain, 1000);
    }
    await helpers.time.increase(epoch);
    await tokenomics.checkpoint();
    const claim = (gasLimit = budget) => dispenser.claimStakingIncentivesBatch(1, [chain], [targets.map((t) => b32(t.address))], ["0x"], [0], {gasLimit});
    return {olas, tokenomics, dispenser, vw, bridge, processor, receiver, factory, targets, chain, claim};
}

// Explicit opt-in: these are cross-repository tests using reviewed Forge artifacts, not mocks of funding logic.
(registryOut && governanceOut ? describe : describe.skip)("Dispenser batch gas (10 targets)", function () {
    this.timeout(120000);
    for (const local of [true, false]) {
        it(`${local ? "Ethereum" : "Gnosis"}: first and subsequent funding`, async () => {
            const f = await fixture(local);
            for (const round of ["first", "subsequent"]) {
                const balances = await Promise.all(f.targets.map((target) => target.balance()));
                const receipt = await (await f.claim()).wait();
                console.log(`${local ? "Ethereum" : "Gnosis"} ${round} L1 gas=${receipt.gasUsed}`);
                if (!local) {
                    expect(await f.bridge.allowance()).to.equal(await f.processor.MESSAGE_GAS_LIMIT());
                    const delivery = await (await f.bridge.deliver({gasLimit: 3000000})).wait();
                    console.log(`Gnosis ${round} delivery transaction gas=${delivery.gasUsed}; receiver allowance=2000000`);
                }
                for (const [i, target] of f.targets.entries()) expect(await target.balance()).to.gt(balances[i]);
                await helpers.time.increase(epoch);
                await f.tokenomics.checkpoint();
            }
        });
    }
    for (const mode of ["paused queue", "invalid instances", "emissions cap"]) {
        it(`Gnosis: ${mode} within the message allowance`, async () => {
            const f = await fixture(false, mode === "emissions cap");
            await f.claim();
            if (mode === "paused queue") await f.receiver.pause();
            if (mode === "invalid instances") for (const target of f.targets) await f.factory.setInstanceStatus(target.address, false);
            const receipt = await (await f.bridge.deliver({gasLimit: 3000000})).wait();
            console.log(`Gnosis ${mode} delivery transaction gas=${receipt.gasUsed}`);
            if (mode === "emissions cap") expect(await f.receiver.withheldAmount()).to.gt(0);
            if (mode === "invalid instances") {
                const payload = f.receiver.interface.decodeFunctionData("receiveMessage", await f.bridge.message())[0];
                const [, amounts] = ethers.utils.defaultAbiCoder.decode(["address[]", "uint256[]", "bytes32"], payload);
                expect(amounts.length).to.equal(targetCount);
                for (const target of f.targets) expect(await target.balance()).to.equal(0);
                const total = amounts.reduce((sum, amount) => sum.add(amount), ethers.constants.Zero);
                expect(await f.receiver.withheldAmount()).to.equal(total);
            }
            if (mode === "paused queue") {
                const payload = f.receiver.interface.decodeFunctionData("receiveMessage", await f.bridge.message())[0];
                const [targets, amounts, hash] = ethers.utils.defaultAbiCoder.decode(["address[]", "uint256[]", "bytes32"], payload);
                expect(targets.length).to.equal(targetCount);
                for (const [i, target] of f.targets.entries()) {
                    expect(await target.balance()).to.equal(0);
                    const queueHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
                        ["address", "uint256", "bytes32", "uint256", "address"], [targets[i], amounts[i], hash, 31337, f.receiver.address]));
                    expect(await f.receiver.queuedHashes(queueHash)).to.equal(true);
                }
            }
            if (mode === "emissions cap") for (const target of f.targets) expect(await target.balance()).to.equal(await target.emissionsAmount());
        });
    }
});
