/*global process*/

// Static reconciliation of the POL deployment surface against the contracts (issue #327).
// Catches drift that never appears in a code diff: deploy-script constructor args vs the contract constructor,
// deploy scripts vs the README variant list, and orphan globals keys. Exits non-zero on any mismatch, so it can
// run in CI. Read-only; no RPC, no on-chain calls.

const fs = require("fs");
const path = require("path");

const POL_DIR = "scripts/deployment/pol";
const ABIS_DIR = "abis/0.8.30";
const README = path.join(POL_DIR, "README.md");

const failures = [];
const fail = (m) => failures.push(m);
const read = (p) => fs.readFileSync(p, "utf8");

// ---- helpers ----
const deploy02Scripts = fs.readdirSync(POL_DIR)
    .filter((f) => /^deploy_02_liquidity_manager_.*\.sh$/.test(f));
const slugOf = (f) => f.replace(/^deploy_02_liquidity_manager_(.*)\.sh$/, "$1");
const globalsFiles = fs.readdirSync(POL_DIR).filter((f) => /^globals_.*\.json$/.test(f));

// ============================================================================
// Check 1 — deploy_02 constructor args vs the contract constructor arity
// ============================================================================
for (const scriptFile of deploy02Scripts) {
    const body = read(path.join(POL_DIR, scriptFile));

    const nameM = body.match(/contractName\s*=\s*"([^"]+)"/);
    if (!nameM) { fail(`${scriptFile}: no contractName= found`); continue; }
    const contractName = nameM[1];

    const argsM = body.match(/constructorArgs\s*=\s*"([^"]*)"/);
    if (!argsM) { fail(`${scriptFile}: no constructorArgs= found`); continue; }
    const argsCount = argsM[1].trim().split(/\s+/).filter((t) => t.startsWith("$")).length;

    const sigM = body.match(/cast abi-encode\s+"constructor\(([^)]*)\)"/);
    if (!sigM) { fail(`${scriptFile}: no cast abi-encode "constructor(...)" found`); continue; }
    const sigCount = sigM[1].trim() === "" ? 0 : sigM[1].split(",").length;

    const abiPath = path.join(ABIS_DIR, `${contractName}.json`);
    if (!fs.existsSync(abiPath)) { fail(`${scriptFile}: ABI ${abiPath} missing for ${contractName}`); continue; }
    const ctor = JSON.parse(read(abiPath)).abi.find((e) => e.type === "constructor");
    const abiCount = ctor ? ctor.inputs.length : 0;

    if (!(argsCount === sigCount && sigCount === abiCount)) {
        fail(`${scriptFile}: constructor arity mismatch for ${contractName} — `
            + `constructorArgs=${argsCount}, abi-encode signature=${sigCount}, contract ABI=${abiCount}`);
    }
}

// ============================================================================
// Check 2 — deploy_02 slugs <-> README variant list (both directions)
// ============================================================================
{
    const readme = read(README);
    const slugs = deploy02Scripts.map(slugOf);
    for (const slug of slugs) {
        // Match the slug as a backticked token in the README variant prose.
        if (!new RegExp("`" + slug.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "`").test(readme)) {
            fail(`README: deploy variant \`${slug}\` (deploy_02_liquidity_manager_${slug}.sh) is not listed`);
        }
    }
    // Reverse: any `slug` the README lists that has no deploy script.
    const backticked = [...readme.matchAll(/`([a-z0-9_]+)`/g)].map((m) => m[1]);
    for (const tok of new Set(backticked)) {
        if (/^(univ2univ3|balancer_slipstream|balancer_univ3|univ2univ3_bridge)$/.test(tok) && !slugs.includes(tok)) {
            fail(`README: variant \`${tok}\` is listed but has no deploy_02_liquidity_manager_${tok}.sh`);
        }
    }
}

// ============================================================================
// Check 3 — every globals key is read by a pol script or is a known output/config key
// ============================================================================
//
// DIRECTION IS DELIBERATE — do not invert it. This flags keys that are PRESENT but UNREAD (orphans); it does
// NOT require that every script-read key be present in every globals file. That asymmetry is load-bearing:
// routerV2Address is absent from Balancer-source chains and balancerVaultAddress from UniV2-source ones, and
// script_05's variant guard branches on exactly that absence. A check demanding every read key be present
// everywhere would push someone to fill them all in and silently disarm that guard.
{
    // Keys read anywhere in the pol scripts (jq -r '.X' / jq -rc '.X' / // empty variants).
    const scriptText = fs.readdirSync(POL_DIR)
        .filter((f) => f.endsWith(".sh"))
        .map((f) => read(path.join(POL_DIR, f)))
        .join("\n");
    const readKeys = new Set(
        [...scriptText.matchAll(/jq -r?c?\s+'\.([a-zA-Z0-9_]+)/g)].map((m) => m[1])
    );

    // Keys that are legitimately present without being read as input:
    //  - deploy-time OUTPUTS (written by a script, or produced by deployment),
    //  - variant-specific keys deliberately present only on some chains (the asymmetry script_05's guard needs).
    const KNOWN = new Set([
        // outputs / filled during deployment
        "neighborhoodScannerAddress", "liquidityManagerAddress", "liquidityManagerProxyAddress",
        "buyBackBurnerProxyAddress", "v3Pools", "v3SecondTokens", "v3MaxSlippages",
        // variant-specific (expected-absent on the other variant's chains)
        "routerV2Address", "balancerVaultAddress", "bridge2BurnerAddress",
        "timelockAddress", "bridgeMediatorAddress",
    ]);

    for (const gf of globalsFiles) {
        const keys = Object.keys(JSON.parse(read(path.join(POL_DIR, gf))));
        for (const k of keys) {
            if (!readKeys.has(k) && !KNOWN.has(k)) {
                fail(`${gf}: key "${k}" is not read by any pol script and is not a known output/variant key (orphan)`);
            }
        }
    }
}

// ---- report ----
if (failures.length) {
    console.error("POL reconciliation FAILED:");
    for (const f of failures) console.error("  - " + f);
    process.exit(1);
}
console.log(`POL reconciliation OK — ${deploy02Scripts.length} deploy variants, ${globalsFiles.length} globals checked.`);
process.exit(0);
