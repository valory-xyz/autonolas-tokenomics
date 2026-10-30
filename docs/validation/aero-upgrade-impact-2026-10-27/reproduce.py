#!/usr/bin/env python3
"""Reproduce the Aero integration review and inspect its lossless evidence bundle.

snapshot: read-only RPC checks (requires cast); interfaces: source tuple checks;
verify: offline artifact/source hash checks; show: print an original evidence item.
Run --help or a subcommand's --help for arguments.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
UPSTREAM = "f99f2095918cab69eafeffa2c3d0a8762de737b7"
BASE_URL = f"https://raw.githubusercontent.com/Dromos-Labs/metadex-slipstream-public/{UPSTREAM}/"


def rpc(url, method, params):
    request = urllib.request.Request(url, data=json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": method, "params": params
    }).encode(), headers={"Content-Type": "application/json", "User-Agent": "tokenomics-read-only-review"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        return result.get("result", {"error": result.get("error")})
    except Exception as error:
        return {"error": str(error)}


def selector(signature):
    return subprocess.check_output(["cast", "sig", signature], text=True).strip()


SIGNATURES = ["factory()", "factoryV3()", "positionManagerV3()", "swapRouter()",
              "liquidityManager()", "owner()", "balanceOf(address)", "mapV3Pools(address)"]
SELECTORS = {}  # Populated only by the snapshot command, which requires cast.


def word(address):
    return address.lower().removeprefix("0x").zfill(64)


def inspect(chain, url, requested_block):
    pol = json.loads((ROOT / f"scripts/deployment/pol/globals_{chain}_mainnet.json").read_text())
    utils = json.loads((ROOT / f"scripts/deployment/utils/globals_{chain}_mainnet.json").read_text())
    config = next(c for c in json.loads((ROOT / "docs/configuration.json").read_text()) if c["name"] == chain)
    upstream_url = BASE_URL + f"deployment-addresses/cl-{chain}.json"
    with urllib.request.urlopen(upstream_url, timeout=20) as response:
        upstream = json.load(response)
    block = hex(requested_block) if requested_block else rpc(url, "eth_blockNumber", [])
    output = {"rpc": url, "block": block, "chain_id": rpc(url, "eth_chainId", []),
              "upstream_manifest": upstream_url, "contracts": {}, "calls": {}}
    if not isinstance(block, str):
        return output
    header = rpc(url, "eth_getBlockByNumber", [block, False])
    output["block_header"] = {k: header.get(k) for k in ["number", "hash", "timestamp"]} if isinstance(header, dict) else header
    addresses = {"configured_npm": pol["positionManagerV3Address"],
                 "configured_router": utils["swapRouterV3Address"],
                 "lm_proxy": pol["liquidityManagerProxyAddress"],
                 "lm_implementation": pol["liquidityManagerAddress"],
                 "aero_npm": upstream["nftPositionManager"],
                 "aero_router": upstream["swapRouter"], "aero_factory": upstream["clFactory"]}
    addresses.update({c["name"]: c["address"] for c in config["contracts"] if c["name"].startswith("BuyBackBurner")})
    for label, address in addresses.items():
        code = rpc(url, "eth_getCode", [address, block])
        output["contracts"][label] = {"address": address, "code_bytes": (len(code) - 2) // 2 if isinstance(code, str) else code}

    def call(label, address, signature, arg=""):
        output["calls"][label] = rpc(url, "eth_call", [{"to": address, "data": SELECTORS[signature] + arg}, block])

    for label in ["configured_npm", "configured_router", "aero_npm", "aero_router"]:
        call(label + ".factory", addresses[label], "factory()")
    for sig in ["factoryV3()", "positionManagerV3()", "owner()"]:
        call("lm." + sig, addresses["lm_proxy"], sig)
    bbb = addresses["BuyBackBurnerProxy"]
    for sig in ["swapRouter()", "liquidityManager()", "owner()"]:
        call("bbb." + sig, bbb, sig)
    tokens = {"WETH": "0x4200000000000000000000000000000000000006",
              "USDC": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" if chain == "base" else "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"}
    for label, token in tokens.items():
        call("bbb.mapV3Pools." + label, bbb, "mapV3Pools(address)", word(token))
    call("configured_npm.balanceOf.lm", addresses["configured_npm"], "balanceOf(address)", word(addresses["lm_proxy"]))
    call("aero_npm.balanceOf.lm", addresses["aero_npm"], "balanceOf(address)", word(addresses["lm_proxy"]))
    return output



def fields(root, path, struct):
    source = (root / path).read_text()
    match = re.search(r"struct\s+" + struct + r"\s*\{([^}]+)\}", source)
    return [line.strip().split()[0] for line in match.group(1).split(";") if line.strip()]


def compare_interfaces(upstream):
    upstream = Path(upstream).resolve()
    NPM = "contracts/periphery/interfaces/INonfungiblePositionManager.sol"
    checks = [
        ("MintParams", "contracts/pol/LiquidityManagerTargetSlipstream.sol", NPM),
        ("ExactInputSingleParams", "contracts/utils/BuyBackBurnerBalancer.sol", "contracts/periphery/interfaces/ISwapRouter.sol"),
        ("IncreaseLiquidityParams", "contracts/interfaces/IPositionManagerV3.sol", NPM),
        ("DecreaseLiquidityParams", "contracts/interfaces/IPositionManagerV3.sol", NPM),
        ("CollectParams", "contracts/interfaces/IUniswapV3.sol", NPM),
    ]
    results = []
    for name, ours, theirs in checks:
        local_fields, upstream_fields = fields(ROOT, ours, name), fields(upstream, theirs, name)
        results.append({"tuple": name, "local_file": ours, "upstream_file": theirs,
                        "local_types": local_fields, "upstream_types": upstream_fields,
                        "same_abi_tuple": local_fields == upstream_fields})
    paths = {p for _, _, p in checks} | {
        "contracts/core/interfaces/pool/ICLPoolState.sol",
        "contracts/core/interfaces/pool/ICLPoolDerivedState.sol",
        "contracts/core/interfaces/ICLFactory.sol",
    }
    return {
        "tokenomics_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "aero_source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, text=True).strip(),
        "upstream_sha256": {p: hashlib.sha256((upstream / p).read_bytes()).hexdigest() for p in sorted(paths)},
        "tuple_comparisons": results,
        "scope": "Exact tuple field-type and order comparison only; function behavior, output layouts and oracle semantics require separate review."
    }


def load_bundle():
    return json.loads(Path(__file__).with_name("evidence.json").read_text())


def verify_bundle(bundle):
    files = bundle["files"]
    snapshots = bundle.get("source_snapshots", {})
    for name, item in list(files.items()) + list(snapshots.items()):
        actual = hashlib.sha256(item["text"].encode("utf-8")).hexdigest()
        if actual != item.get("sha256", name):
            raise SystemExit(f"Evidence hash mismatch: {name}")
    checked_sources = set()
    totals = {"workspace": 0, "historical": 0}
    for run in bundle["runs"]:
        record_name, output_name = run["record"], run["output"]
        source_state = run["source_state"]
        record = json.loads(files[record_name]["text"])
        for path, expected in record["sha256"].items():
            if source_state == "historical" and expected in snapshots:
                if snapshots[expected]["path"] != path:
                    raise SystemExit(f"Archived source path mismatch: {path}")
            elif hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected:
                raise SystemExit(f"Source hash mismatch: {path} ({record_name})")
            checked_sources.add((path, expected))
        if files[output_name]["sha256"] != record["output_sha256"]:
            raise SystemExit(f"Recorded output hash mismatch: {output_name}")
        passed = sum(result["passed"] for result in record["results"].values())
        if files[output_name]["text"].count("[PASS]") != passed:
            raise SystemExit(f"Recorded test-count mismatch: {output_name}")
        totals[source_state] += passed
    print(f"Verified {len(files)} bundled evidence items and {len(checked_sources)} source hashes; "
          f"logs record {totals['workspace']} current-source and {totals['historical']} historical passing tests. "
          "Tests were not rerun by this command.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    snapshot = commands.add_parser("snapshot", help="Read deployed state from RPC")
    snapshot.add_argument("--blocks", nargs=2, type=int, metavar=("BASE_BLOCK", "OPTIMISM_BLOCK"))
    snapshot.add_argument("--base-rpc", default="https://base.drpc.org")
    snapshot.add_argument("--optimism-rpc", default="https://mainnet.optimism.io")
    interfaces = commands.add_parser("interfaces", help="Compare source tuple layouts")
    interfaces.add_argument("upstream", type=Path, help="Local official Aero Slipstream checkout")
    commands.add_parser("verify", help="Verify bundled evidence and local source hashes offline")
    show = commands.add_parser("show", help="Print an original bundled evidence file verbatim")
    show.add_argument("name", nargs="?", help="Original filename; omit to list names")
    show.add_argument("--source", action="store_true", help="Read archived test source by SHA-256 instead")
    args = parser.parse_args()
    if args.command == "snapshot":
        SELECTORS.update({sig: selector(sig) for sig in SIGNATURES})
        chains = [("base", args.base_rpc), ("optimism", args.optimism_rpc)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            jobs = [pool.submit(inspect, chain, url, args.blocks[i] if args.blocks else None)
                    for i, (chain, url) in enumerate(chains)]
            results = {chain: job.result() for (chain, _), job in zip(chains, jobs)}
        print(json.dumps({"collected_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                          "tokenomics_commit": subprocess.check_output(
                              ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                          "aero_source_commit": UPSTREAM, "chains": results}, indent=2))
    elif args.command == "interfaces":
        result = compare_interfaces(args.upstream)
        print(json.dumps(result, indent=2))
        if not all(check["same_abi_tuple"] for check in result["tuple_comparisons"]):
            raise SystemExit(1)
    elif args.command == "verify":
        verify_bundle(load_bundle())
    elif args.command == "show":
        files = load_bundle()["source_snapshots" if args.source else "files"]
        if args.name is None:
            print("\n".join(files))
        elif args.name not in files:
            parser.error(f"Unknown evidence item: {args.name}")
        else:
            sys.stdout.write(files[args.name]["text"])


if __name__ == "__main__":
    main()
