/*global process, require, module*/
// Read-only checks against the current Forge build and deployment globals.
const { ethers } = require("ethers");
const fs = require("fs");
const ZERO = ethers.constants.AddressZero;
const SLOT = ethers.utils.id("PROXY_DISPENSER");
const NETWORKS = ["eth", "arbitrum", "gnosis", "optimism", "base", "celo", "mode", "polygon", "robinhood"];
const load = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const artifact = (name) => load(`out/${name}.sol/${name}.json`);
const bytes = (value) => typeof value === "string" ? value : value.object;
const address = (value) => {
    const result = ethers.utils.getAddress(value);
    if (result === ZERO) throw new Error("Expected a nonzero address");
    return result;
};
const printable = (value) => value.toString().toLowerCase();

class Audit {
    constructor() { this.failures = []; }
    async check(label, expected, read) {
        try {
            const observed = await read();
            const matches = printable(expected) === printable(observed);
            console.log(`${matches ? "PASS" : "FAIL"} ${label}: expected=${expected}, observed=${observed}`);
            if (!matches) this.failures.push(label);
        } catch {
            // RPC errors can contain credentials in their URL/body; do not print them.
            console.log(`FAIL ${label}: check unavailable`);
            this.failures.push(label);
        }
    }
    finish() {
        if (this.failures.length) throw new Error(`AUDIT FAILED: ${this.failures.length} checks: ${this.failures.join(", ")}`);
        console.log("AUDIT PASSED");
    }
    async contract(provider, name, location, args) {
        location = address(location);
        const build = artifact(name);
        const contract = new ethers.Contract(location, build.abi, provider);
        await this.check(`${name} ${location} runtime hash`, "matching reviewed build", async () => {
            const data = new ethers.ContractFactory(build.abi, bytes(build.bytecode)).getDeployTransaction(...args).data;
            // Constructor eth_call returns runtime including the supplied immutables, without broadcasting.
            const expected = await provider.call({ data });
            const observed = await provider.getCode(location);
            if (expected === "0x" || observed === "0x") return "empty runtime";
            const a = ethers.utils.keccak256(expected);
            const b = ethers.utils.keccak256(observed);
            return a === b ? "matching reviewed build" : `hash ${b} (expected ${a})`;
        });
        return contract;
    }
    async getters(contract, expected) {
        for (const [key, value] of Object.entries(expected)) {
            await this.check(`${contract.address} ${key}()`, value, () => contract[key]());
        }
    }
}

async function providerFor(globals, override) {
    let url = process.env[override] || globals.networkURL;
    if (!process.env[override] && url.includes("alchemy.com")) {
        const suffix = {1: "MAINNET", 11155111: "SEPOLIA", 137: "MATIC", 80002: "AMOY"}[globals.chainId];
        const key = process.env[`ALCHEMY_API_KEY_${suffix}`];
        if (!key) throw new Error(`Set ${override} or the configured Alchemy key`);
        url += key;
    }
    const provider = new ethers.providers.JsonRpcProvider(url);
    let chain;
    try { chain = (await provider.getNetwork()).chainId; } catch { throw new Error("Cannot read RPC chain ID"); }
    if (String(chain) !== String(globals.chainId)) throw new Error(`Wrong RPC chain: expected=${globals.chainId}, observed=${chain}`);
    return provider;
}

async function proxyIdentity(audit, provider, root) {
    const proxy = address(root.dispenserProxyAddress);
    const implementation = address(root.dispenserAddress);
    await audit.check("Dispenser proxy implementation slot", ethers.utils.hexZeroPad(implementation, 32),
        () => provider.getStorageAt(proxy, SLOT));
    // The proxy has no runtime immutables; initialization is storage, not code.
    await audit.check("DispenserProxy runtime hash", ethers.utils.keccak256(bytes(artifact("DispenserProxy").deployedBytecode)),
        async () => ethers.utils.keccak256(await provider.getCode(proxy)));
    const impl = await audit.contract(provider, "Dispenser", implementation,
        [address(root.olasAddress), address(root.tokenomicsProxyAddress), root.retainerAddress]);
    return new ethers.Contract(proxy, impl.interface, provider);
}

async function auditDispenser(audit, provider, root, staking) {
    const dispenser = await proxyIdentity(audit, provider, root);
    await audit.getters(dispenser, {
        olas: address(root.olasAddress), tokenomics: address(root.tokenomicsProxyAddress), retainer: root.retainerAddress,
        retainerHash: ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["bytes32", "uint256"], [root.retainerAddress, root.chainId])),
        treasury: address(root.treasuryAddress), owner: address(root.timelockAddress),
        voteWeighting: address(root.voteWeightingAddress), maxNumClaimingEpochs: root.maxNumClaimingEpochs,
        maxNumStakingTargets: root.maxNumStakingTargets, paused: 0
    });
    const vw = new ethers.Contract(root.voteWeightingAddress, ["function dispenser() view returns (address)"], provider);
    await audit.getters(vw, {dispenser: root.dispenserProxyAddress});
    for (const key of ["tokenomicsProxyAddress", "treasuryAddress"]) {
        const manager = new ethers.Contract(root[key], ["function dispenser() view returns (address)"], provider);
        await audit.getters(manager, {dispenser: root.dispenserProxyAddress});
    }
    for (const network of NETWORKS) {
        const chain = network === "eth" ? root.chainId : staking[`${network}L2TargetChainId`];
        const expected = address(staking[network === "eth" ? "ethereumDepositProcessorAddress" : `${network}DepositProcessorL1Address`]);
        await audit.check(`Dispenser processor route ${chain}`, expected, () => dispenser.mapChainIdDepositProcessors(chain));
    }
}

function pairSpec(network, root, l1, l2) {
    if (!NETWORKS.includes(network)) throw new Error("Unsupported processor network");
    const args = [address(l1.olasAddress), address(root.dispenserProxyAddress)];
    let kind;
    const get = (suffix) => l1[`${network}${suffix}`];
    if (network === "eth") {
        return {name: "EthereumDepositProcessor", location: l1.ethereumDepositProcessorAddress,
            args: [...args, address(l1.serviceStakingFactoryAddress), address(l1.timelockAddress)]};
    }
    if (["arbitrum", "robinhood"].includes(network)) {
        kind = "Arbitrum";
        args.push(get("L1ERC20GatewayRouterAddress"), get("InboxAddress"), get("L2TargetChainId"),
            get("L1ERC20GatewayAddress"), get("OutboxAddress"), get("BridgeAddress"));
    } else if (network === "gnosis") {
        kind = "Gnosis";
        args.push(get("OmniBridgeAddress"), get("AMBForeignAddress"), get("L2TargetChainId"));
    } else if (network === "polygon") {
        kind = "Polygon";
        args.push(get("RootChainManagerProxyAddress"), get("FXRootAddress"), get("L2TargetChainId"),
            get("CheckpointManagerAddress"), get("ERC20PredicateAddress"));
    } else {
        kind = "Optimism";
        args.push(get("L1StandardBridgeProxyAddress"), get("L1CrossDomainMessengerProxyAddress"),
            get("L2TargetChainId"), get("OLASAddress"));
    }
    const relayerKey = {Arbitrum: "ArbSysAddress", Gnosis: "AMBHomeAddress", Polygon: "FXChildAddress", Optimism: "L2CrossDomainMessengerAddress"}[kind];
    return {name: `${kind}DepositProcessorL1`, location: get("DepositProcessorL1Address"), args,
        targetName: `${kind}TargetDispenserL2`, target: l2[`${network}TargetDispenserL2Address`],
        targetArgs: [l2.olasAddress, l2.serviceStakingFactoryAddress, l2[`${network}${relayerKey}`], get("DepositProcessorL1Address"), l1.chainId]};
}

async function auditPair(audit, providers, network, root, l1, l2, phase) {
    if (!["before-link", "after-link"].includes(phase)) throw new Error("Use before-link or after-link");
    const dispenser = await proxyIdentity(audit, providers[0], root);
    await audit.check("Dispenser initialized owner", true, async () => (await dispenser.owner()) !== ZERO);
    await audit.check("L1 OLAS configuration", root.olasAddress, async () => l1.olasAddress);
    const spec = pairSpec(network, root, l1, l2);
    const processor = await audit.contract(providers[0], spec.name, spec.location, spec.args);
    if (network === "eth") return;
    await audit.check("L2 chain configuration", l1[`${network}L2TargetChainId`], async () => l2.chainId);
    await audit.check("L1 chain configuration", l1.chainId, async () => l2.l1ChainId);
    await audit.check("L2 globals processor", spec.location, async () => l2[`${network}DepositProcessorL1Address`]);
    await audit.check("L1 globals target", spec.target, async () => l1[`${network}TargetDispenserL2Address`]);
    if (["optimism", "base", "celo", "mode"].includes(network)) {
        await audit.check("L2 OLAS configuration", l2.olasAddress, async () => l1[`${network}OLASAddress`]);
    }
    const target = await audit.contract(providers[1], spec.targetName, spec.target, spec.targetArgs);
    await audit.getters(target, {paused: 1, migratedTo: ZERO});
    await audit.check("L2 target initialized owner", true, async () => (await target.owner()) !== ZERO);
    const linked = phase === "after-link";
    await audit.getters(processor, {l2TargetDispenser: linked ? address(spec.target) : ZERO});
    await audit.check("L1 processor owner cleared", linked, async () => (await processor.owner()) === ZERO);
    if (network === "polygon") {
        await audit.getters(processor, {fxChildTunnel: linked ? address(spec.target) : ZERO,
            checkpointManager: l1.polygonCheckpointManagerAddress, fxRoot: l1.polygonFXRootAddress});
        await audit.getters(target, {fxChild: l2.polygonFXChildAddress, fxRootTunnel: linked ? address(spec.location) : ZERO});
    }
}

async function auditForwarders(audit, providers, eth, polygon) {
    const args = [address(polygon.olasAddress), address(eth.olasAddress), address(eth.burnerAddress), polygon.chainId, eth.chainId];
    const build = artifact("PolygonBurnForwarder");
    const data = new ethers.ContractFactory(build.abi, bytes(build.bytecode)).getDeployTransaction(...args).data;
    const factory = "0x4e59b44847b379578588920cA78FbF26c0B4956C";
    const predicted = ethers.utils.getCreate2Address(factory, ethers.utils.id("PolygonBurnForwarder"), ethers.utils.keccak256(data));
    for (const [index, globals] of [eth, polygon].entries()) {
        await audit.check(`Forwarder address chain ${globals.chainId}`, predicted, async () => address(globals.polygonBurnForwarderAddress));
        const forwarder = await audit.contract(providers[index], "PolygonBurnForwarder", globals.polygonBurnForwarderAddress, args);
        await audit.getters(forwarder, {VERSION: "0.1.0", polygonOlas: args[0], l1Olas: args[1], olasBurner: args[2], polygonChainId: args[3], l1ChainId: args[4]});
    }
}

async function auditBridge(audit, provider, globals) {
    const bridge = await audit.contract(provider, "Bridge2BurnerPolygon", globals.bridge2BurnerAddress,
        [address(globals.olasAddress), address(globals.polygonBurnForwarderAddress)]);
    await audit.getters(bridge, {olas: globals.olasAddress, l2TokenRelayer: globals.polygonBurnForwarderAddress,
        VERSION: "0.1.0", MIN_OLAS_BALANCE: ethers.utils.parseEther("100")});
}

async function main(args) {
    const [mode, networkArg, phase] = args;
    const audit = new Audit();
    if (mode === "forwarders" || mode === "bridge") {
        const eth = load("scripts/deployment/utils/globals_eth_mainnet.json");
        const polygon = load("scripts/deployment/utils/globals_polygon_mainnet.json");
        if (mode === "forwarders") {
            await auditForwarders(audit, [await providerFor(eth, "AUDIT_L1_RPC_URL"), await providerFor(polygon, "AUDIT_L2_RPC_URL")], eth, polygon);
        } else {
            await auditBridge(audit, await providerFor(polygon, "AUDIT_L2_RPC_URL"), polygon);
        }
    } else if (mode === "dispenser" || mode === "pair") {
        if (!networkArg || !/^[a-z0-9_]+$/.test(networkArg)) throw new Error("Supply network (e.g. mainnet or gnosis_mainnet)");
        const split = networkArg.lastIndexOf("_");
        const network = networkArg.slice(0, split);
        const suffix = mode === "pair" ? networkArg.slice(split + 1) : networkArg;
        if (mode === "pair" && !NETWORKS.includes(network)) throw new Error("Unsupported processor network");
        const root = load(`scripts/deployment/globals_${suffix}.json`);
        const l1 = load(`scripts/deployment/staking/globals_${suffix}.json`);
        const provider = await providerFor(root, "AUDIT_L1_RPC_URL");
        if (String(l1.chainId) !== String(root.chainId)) throw new Error("Root/staking chain IDs differ");
        if (mode === "dispenser") await auditDispenser(audit, provider, root, l1);
        else {
            const l2 = network === "eth" ? null : load(`scripts/deployment/staking/${network}/globals_${networkArg}.json`);
            await auditPair(audit, [provider, l2 && await providerFor(l2, "AUDIT_L2_RPC_URL")], network, root, l1, l2, phase);
        }
    } else throw new Error("Use dispenser <network>, pair <network> <before-link|after-link>, forwarders, or bridge");
    audit.finish();
}

if (require.main === module) main(process.argv.slice(2)).catch((error) => {
    // Avoid leaking RPC credentials in provider error payloads.
    console.error(error.code ? `Audit unavailable (${error.code})` : error.message);
    process.exitCode = 1;
});
module.exports = {Audit, proxyIdentity, auditDispenser, pairSpec, auditPair, auditForwarders, auditBridge, main};
