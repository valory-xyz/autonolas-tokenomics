#!/usr/bin/env python3
"""Check that the conservation regression rejects three accounting faults.

All mutations run in a temporary copy; tracked contracts in the checkout are never
modified. Requires installed repository dependencies and Foundry on PATH.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SINGLE = "ITokenomics(tokenomics).refundFromStaking(withheldUsed);"
BATCH = "totalAmounts[2] += withheldUsed;"
TESTS = ("test_recycleThenSpend_single()", "test_recycleThenSpend_batch()")
ASSERTION = "minted + outstanding allowance != fresh budgets"


def run(forge, root):
    result = subprocess.run(
        [forge, "test", "--root", str(root), "--offline", "--match-contract",
         "DispenserInflationConservationTest", "--match-test", "test_recycleThenSpend_", "-vv"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False,
    )
    return result.returncode, result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge", default="forge", help="Foundry forge executable")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    forge = shutil.which(args.forge)
    if forge is None:
        parser.error("forge executable not found")

    with tempfile.TemporaryDirectory(prefix="dispenser-inflation-mutations-") as directory:
        root = Path(directory)
        shutil.copytree(source / "contracts", root / "contracts")
        (root / "test").mkdir()
        shutil.copy2(source / "test/DispenserInflationConservation.t.sol", root / "test")
        shutil.copy2(source / "foundry.toml", root)
        for dependency in ("lib", "node_modules"):
            os.symlink((source / dependency).resolve(), root / dependency, target_is_directory=True)

        code, output = run(forge, root)
        if code or not all(f"[PASS] {test}" in output for test in TESTS):
            raise SystemExit("Unmodified baseline did not pass:\n" + output)
        print("PASS: unmodified baseline (single and batch)", flush=True)

        contract = root / "contracts/Dispenser.sol"
        original = contract.read_text()
        if original.count(SINGLE) != 1 or original.count(BATCH) != 1:
            raise SystemExit("Mutation anchors changed; review the mutations before running")
        mutations = {
            "duplicate refund": (
                SINGLE.replace("(withheldUsed)", "(2 * withheldUsed)"),
                "totalAmounts[2] += 2 * withheldUsed;",
            ),
            "omit refund": ("// withheld refund deliberately omitted", "// withheld refund deliberately omitted"),
            "mint without netting reused credit": (
                SINGLE + "\n                transferAmount += withheldUsed;",
                BATCH + "\n                    transferAmounts[i] += withheldUsed;",
            ),
        }
        for label, (single, batch) in mutations.items():
            contract.write_text(original.replace(SINGLE, single).replace(BATCH, batch))
            code, output = run(forge, root)
            failures = [line for line in output.splitlines() if line.startswith("[FAIL:")]
            caught = all(any(test in line and ASSERTION in line for line in failures) for test in TESTS)
            if code == 0 or not caught:
                raise SystemExit(f"Mutation was not rejected by the conservation assertion: {label}\n{output}")
            print(f"PASS: rejected {label} in single and batch claims", flush=True)


if __name__ == "__main__":
    main()
