/*global describe, it, beforeEach, afterEach*/
const {ethers} = require("hardhat");
const {expect} = require("chai");
const fs = require("fs");
const {Audit, auditPair, pairSpec, proxyIdentity, auditForwarders, auditBridge, auditDispenser} = require("../scripts/audit_chains/audit_staking_routes");
const load = (file) => JSON.parse(fs.readFileSync(file));
const build = (name) => load(`out/${name}.sol/${name}.json`);
const zero = ethers.constants.AddressZero;

async function deploy(name, args = []) {
    const artifact = build(name);
    const contract = await new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, (await ethers.getSigners())[0]).deploy(...args);
    await contract.deployed();
    return contract;
}

async function fixture() {
    const [owner] = await ethers.getSigners();
    const root = {...load("scripts/deployment/globals_mainnet.json"), chainId: 31337, timelockAddress: owner.address};
    const token = await deploy("ERC20Token");
    root.olasAddress = token.address;
    const treasury = await deploy("Treasury", [token.address, owner.address, owner.address, owner.address]);
    root.treasuryAddress = treasury.address;
    const impl = await deploy("Tokenomics");
    const data = impl.interface.encodeFunctionData("initializeTokenomics", [token.address, treasury.address, owner.address, owner.address,
        owner.address, 30 * 86400, owner.address, owner.address, owner.address, zero]);
    const tp = await deploy("TokenomicsProxy", [impl.address, data]);
    root.tokenomicsProxyAddress = tp.address;
    const di = await deploy("Dispenser", [token.address, tp.address, root.retainerAddress]);
    root.dispenserAddress = di.address;
    const proxy = await deploy("DispenserProxy", [di.address, di.interface.encodeFunctionData("initialize", [treasury.address, zero, 1, 10])]);
    root.dispenserProxyAddress = proxy.address;
    const dispenser = di.attach(proxy.address);
    const vw = await deploy("MockVoteWeighting", [proxy.address]);
    root.voteWeightingAddress = vw.address;
    const staking = {...load("scripts/deployment/staking/globals_mainnet.json"), chainId: 31337, olasAddress: token.address};
    return {root, staking, dispenser, di, treasury, tokenomics: impl.attach(tp.address), vw};
}

describe("Static route audits", function () {
    let log, lines;
    beforeEach(() => {log = console.log; lines = []; console.log = (line) => lines.push(line);});
    afterEach(() => {console.log = log;});

    for (const network of ["eth", "arbitrum", "gnosis", "optimism", "base", "celo", "mode", "polygon", "robinhood"]) {
        it(`${network}: validates code/bindings before linking and link state afterwards`, async () => {
            const {root, staking} = await fixture();
            let l2;
            if (network !== "eth") {
                l2 = load(`scripts/deployment/staking/${network}/globals_${network}_mainnet.json`);
                l2.l1ChainId = staking.chainId;
            }
            let spec = pairSpec(network, root, staking, l2);
            const processor = await deploy(spec.name, spec.args);
            staking[network === "eth" ? "ethereumDepositProcessorAddress" : `${network}DepositProcessorL1Address`] = processor.address;
            let target;
            if (l2) {
                l2[`${network}DepositProcessorL1Address`] = processor.address;
                spec = pairSpec(network, root, staking, l2);
                target = await deploy(spec.targetName, spec.targetArgs);
                l2[`${network}TargetDispenserL2Address`] = target.address;
                staking[`${network}TargetDispenserL2Address`] = target.address;
            }
            const audit = new Audit();
            await auditPair(audit, [ethers.provider, ethers.provider], network, root, staking, l2, "before-link");
            audit.finish();
            if (!l2) return;
            const premature = new Audit();
            await auditPair(premature, [ethers.provider, ethers.provider], network, root, staking, l2, "after-link");
            expect(() => premature.finish()).to.throw("AUDIT FAILED");
            await processor.setL2TargetDispenser(target.address);
            if (network === "polygon") await target.setFxRootTunnel(processor.address);
            const after = new Audit();
            await auditPair(after, [ethers.provider, ethers.provider], network, root, staking, l2, "after-link");
            after.finish();
            // Corrupt a constructor input: identical runtime length is insufficient.
            const wrong = new Audit();
            await auditPair(wrong, [ethers.provider, ethers.provider], network, root,
                {...staking, olasAddress: (await ethers.getSigners())[1].address}, l2, "after-link");
            expect(wrong.failures.some((label) => label.includes("runtime hash"))).to.equal(true);
        });
    }

    it("rejects initialized standalone implementation as proxy, and continues all checks", async () => {
        const {root, di} = await fixture();
        await di.initialize(root.treasuryAddress, zero, 1, 1);
        const audit = new Audit();
        await proxyIdentity(audit, ethers.provider, {...root, dispenserProxyAddress: di.address});
        expect(audit.failures).to.include("Dispenser proxy implementation slot");
        expect(audit.failures).to.include("DispenserProxy runtime hash");
        expect(() => audit.finish()).to.throw("2 checks");
    });

    it("reports governance differences then validates the configured Dispenser", async () => {
        const {root, staking, dispenser, treasury, tokenomics} = await fixture();
        const before = new Audit();
        await auditDispenser(before, ethers.provider, root, staking);
        expect(before.failures.some((s) => s.endsWith("voteWeighting()"))).to.equal(true);
        expect(before.failures.some((s) => s.endsWith("paused()"))).to.equal(true);
        expect(before.failures.filter((s) => s.includes("processor route"))).to.have.length(9);
        await dispenser.changeManagers(zero, root.voteWeightingAddress);
        await treasury.changeManagers(tokenomics.address, zero, dispenser.address);
        await tokenomics.changeManagers(zero, zero, dispenser.address);
        const networks = ["eth", "arbitrum", "gnosis", "optimism", "base", "celo", "mode", "polygon", "robinhood"];
        await dispenser.setDepositProcessorChainIds(networks.map((n) => staking[n === "eth" ? "ethereumDepositProcessorAddress" : `${n}DepositProcessorL1Address`]),
            networks.map((n) => n === "eth" ? root.chainId : staking[`${n}L2TargetChainId`]));
        await dispenser.setPauseState(0);
        const after = new Audit();
        await auditDispenser(after, ethers.provider, root, staking);
        after.finish();
    });

    it("checks both forwarders, CREATE2 identity and bridge recipient", async () => {
        const [owner, other] = await ethers.getSigners();
        const eth = {chainId: 1, olasAddress: owner.address, burnerAddress: other.address};
        const polygon = {chainId: 137, olasAddress: other.address};
        const a = build("PolygonBurnForwarder");
        const data = new ethers.ContractFactory(a.abi, a.bytecode.object).getDeployTransaction(polygon.olasAddress, eth.olasAddress, eth.burnerAddress, 137, 1).data;
        const predicted = ethers.utils.getCreate2Address("0x4e59b44847b379578588920cA78FbF26c0B4956C", ethers.utils.id("PolygonBurnForwarder"), ethers.utils.keccak256(data));
        await ethers.provider.send("hardhat_setCode", [predicted, await ethers.provider.call({data})]);
        eth.polygonBurnForwarderAddress = polygon.polygonBurnForwarderAddress = predicted;
        const good = new Audit();
        await auditForwarders(good, [ethers.provider, ethers.provider], eth, polygon);
        good.finish();
        const wrong = new Audit();
        await auditForwarders(wrong, [ethers.provider, ethers.provider], eth, {...polygon, polygonBurnForwarderAddress: owner.address});
        expect(() => wrong.finish()).to.throw("AUDIT FAILED");
        const bridge = await deploy("Bridge2BurnerPolygon", [polygon.olasAddress, predicted]);
        polygon.bridge2BurnerAddress = bridge.address;
        const b = new Audit();
        await auditBridge(b, ethers.provider, polygon);
        b.finish();
        const bad = new Audit();
        await auditBridge(bad, ethers.provider, {...polygon, polygonBurnForwarderAddress: owner.address});
        expect(bad.failures).to.have.length(2);
    });

    it("collects unavailable and mismatching reads without disclosing RPC errors", async () => {
        const audit = new Audit();
        await audit.check("mismatch", 1, async () => 2);
        await audit.check("unreadable", 1, async () => {throw new Error("secret endpoint");});
        await audit.check("later check", 1, async () => 1);
        expect(lines.join("\n")).not.to.include("secret endpoint");
        expect(lines[2]).to.include("PASS");
        expect(() => audit.finish()).to.throw("2 checks");
    });
});

describe("Processor shell audit checkpoints", function () {
    for (const [network, failedPhase] of [["gnosis", "before-link"], ["gnosis", "after-link"], ["polygon", ""], ["robinhood", ""], ["eth", ""]]) {
        it(`${network}: ${failedPhase || "complete flow"}`, () => {
            const os = require("os");
            const path = require("path");
            const {spawnSync} = require("child_process");
            const dir = fs.mkdtempSync(path.join(os.tmpdir(), "route-audit-"));
            const base = path.join(dir, "scripts/deployment/staking");
            fs.mkdirSync(path.join(base, network), {recursive: true});
            fs.mkdirSync(path.join(dir, "bin"));
            const write = (file, body) => fs.writeFileSync(file, "#!/bin/bash\n" + body + "\n", {mode: 0o755});
            const wrapper = "scripts/deployment/staking/multi_deploy_01_processor_dispenser_link.sh";
            fs.copyFileSync(wrapper, path.join(dir, wrapper));
            write(path.join(base, `deploy_01_${network}_deposit_processor.sh`), "echo L1 >> \"$CALLS\"");
            write(path.join(base, network, `deploy_01_${network}_target_dispenser.sh`), "echo L2 >> \"$CALLS\"");
            write(path.join(base, "script_01_set_target_dispenser_l2.sh"), "echo link >> \"$CALLS\"");
            write(path.join(base, "script_03_set_deposit_processor_l1_polygon.sh"), "echo polygon-link >> \"$CALLS\"");
            write(path.join(dir, "bin/node"), "echo \"audit ${@: -1}\" >> \"$CALLS\"\n[[ -n \"$FAIL_PHASE\" && \"${@: -1}\" == \"$FAIL_PHASE\" ]] && exit 9\nexit 0");
            try {
                const result = spawnSync("bash", [wrapper, `${network}_mainnet`], {cwd: dir,
                    env: {...process.env, PATH: `${dir}/bin:${process.env.PATH}`, CALLS: path.join(dir, "calls"), FAIL_PHASE: failedPhase}, encoding: "utf8"});
                expect(result.status, result.stderr).to.equal(failedPhase ? 9 : 0);
                const calls = fs.readFileSync(path.join(dir, "calls"), "utf8").trim().split("\n");
                if (network === "eth") expect(calls).to.deep.equal(["L1", "audit after-link"]);
                else if (failedPhase === "before-link") expect(calls).to.deep.equal(["L1", "L2", "audit before-link"]);
                else expect(calls).to.deep.equal(["L1", "L2", "audit before-link", "link", ...(network === "polygon" ? ["polygon-link"] : []), "audit after-link"]);
            } finally { fs.rmSync(dir, {recursive: true, force: true}); }
        });
    }
});

describe("Polygon bridge shell audit checkpoints", function () {
    for (const failedMode of ["forwarders", "bridge"]) {
        it(`stops on the ${failedMode} audit failure`, () => {
            const path = require("path");
            const {spawnSync} = require("child_process");
            const dir = fs.mkdtempSync(path.join(require("os").tmpdir(), "bridge-audit-"));
            const base = path.join(dir, "scripts/deployment/utils");
            fs.mkdirSync(base, {recursive: true});
            fs.mkdirSync(path.join(dir, "bin"));
            const write = (file, body) => fs.writeFileSync(file, "#!/bin/bash\n" + body + "\n", {mode: 0o755});
            const wrapper = "scripts/deployment/utils/deploy_00c_bridge2burner_polygon.sh";
            fs.copyFileSync(wrapper, path.join(dir, wrapper));
            const token = "0x1111111111111111111111111111111111111111";
            const forwarder = "0x2222222222222222222222222222222222222222";
            fs.writeFileSync(path.join(base, "globals_polygon_mainnet.json"), JSON.stringify({chainId: 137,
                networkURL: "http://unused", useLedger: true, olasAddress: token, polygonBurnForwarderAddress: forwarder, contractVerification: false}));
            write(path.join(base, "polygon_burn_forwarder_common.sh"), `pbfLoadArgs() { polygonChainId=137; polygonOlas=${token}; }\npbfPredict() { predicted=${forwarder}; }\npbfCheckDeployed() { return 0; }`);
            write(path.join(dir, "bin/node"), "echo \"audit ${@: -1}\" >> \"$CALLS\"\n[[ \"${@: -1}\" == \"$FAIL_MODE\" ]] && exit 9\nexit 0");
            write(path.join(dir, "bin/cast"), `echo ${token}`);
            write(path.join(dir, "bin/forge"), `echo broadcast >> "$CALLS"\necho "Deployed to: ${token}"`);
            try {
                const result = spawnSync("bash", [wrapper, "polygon_mainnet"], {cwd: dir,
                    env: {...process.env, TERM: "dumb", PATH: `${dir}/bin:${process.env.PATH}`, CALLS: path.join(dir, "calls"), FAIL_MODE: failedMode}, encoding: "utf8"});
                expect(result.status, result.stderr).to.equal(1);
                const calls = fs.readFileSync(path.join(dir, "calls"), "utf8").trim().split("\n");
                expect(calls).to.deep.equal(failedMode === "forwarders" ? ["audit forwarders"] : ["audit forwarders", "broadcast", "audit bridge"]);
            } finally { fs.rmSync(dir, {recursive: true, force: true}); }
        });
    }
});
