"""Offline checks for proposal staging; no RPC requests or transactions are sent."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/proposals/proposal_23_transfer_lp_token_celo.sh"
EXPECTED = "100000000000000000000"


class CeloProposalStagesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for relative in (
            "scripts/deployment/globals_mainnet.json",
            "scripts/deployment/staking/globals_mainnet.json",
            "scripts/deployment/staking/celo/globals_celo_mainnet.json",
            "scripts/deployment/utils/globals_celo_mainnet.json",
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            data = json.loads((ROOT / relative).read_text())
            if relative.endswith("utils/globals_celo_mainnet.json"):
                data["lpSwapCeloAddress"] = "0x1111111111111111111111111111111111111111"
            target.write_text(json.dumps(data))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        cast = self.bin / "cast"
        cast.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CAST_LOG"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1] == "call":
    if os.environ.get("RPC_FAIL") == "1":
        sys.exit(1)
    print(os.environ.get("LP_BALANCE", "100000000000000000000"))
else:
    print("0x1234")
''')
        cast.chmod(0o755)
        self.log = self.root / "cast.log"

    def run_stage(self, stage, balance=EXPECTED, expected=EXPECTED, fail=False):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", TERM="xterm",
                   CAST_LOG=str(self.log), LP_BALANCE=balance, RPC_FAIL=str(int(fail)),
                   OLAS_AMOUNT="1000", EXPECTED_CELO_LP_AMOUNT=expected)
        result = subprocess.run(["bash", str(SCRIPT), *stage], cwd=self.root, env=env,
                                text=True, capture_output=True)
        calls = self.log.read_text() if self.log.exists() else ""
        return result, calls

    def test_explicit_stage_required(self):
        result, calls = self.run_stage([])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_lp_stage_excludes_funding_and_migration(self):
        result, calls = self.run_stage(["lp"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("transferTokens(", calls)
        self.assertNotIn("depositERC20To(", calls)
        self.assertNotIn("sendMessage(", calls)
        self.assertIn("values  = [0, 0, 0, 0]", result.stdout)

    def test_missing_expected_amount_blocks_funding(self):
        result, calls = self.run_stage(["fund"], expected="")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("depositERC20To(", calls)

    def test_incomplete_or_invalid_balance_blocks_funding(self):
        for balance in ("0", "1", "99999999999999999999", "invalid"):
            with self.subTest(balance=balance):
                result, calls = self.run_stage(["fund"], balance=balance)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("depositERC20To(", calls)

    def test_rpc_failure_blocks_funding(self):
        result, calls = self.run_stage(["fund"], fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("depositERC20To(", calls)

    def test_full_arrival_generates_only_funding_and_migration(self):
        result, calls = self.run_stage(["fund"], balance=EXPECTED + " [1e20]")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://forno.celo.org", calls)
        self.assertIn("0x2976Fa805141b467BCBc6334a69AffF4D914d96A", calls)
        self.assertIn("depositERC20To(", calls)
        self.assertIn("sendMessage(", calls)
        self.assertNotIn("transferTokens(", calls)
        self.assertIn("values  = [0, 0, 0]", result.stdout)

    def test_extra_lp_does_not_block_funding(self):
        result, _ = self.run_stage(["fund"], balance=str(int(EXPECTED) + 1))
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
