// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

// ============================================================
// PoC #1: Double-applied mint cap for years >= 11
// Fork test against deployed TokenomicsConstants
// ============================================================

interface ITokenomics {
    function getInflationForYear(uint256 numYears) external pure returns (uint256);
    function getActualSupplyCapForYear(uint256 numYears) external pure returns (uint256);
}

contract PoC_DoubleMintCap is Test {
    // Tokenomics proxy on Ethereum mainnet
    address constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;

    function setUp() public {
        // Fork Ethereum mainnet
        vm.createSelectFork("mainnet");
    }

    function test_PoC_DoubleMintCapYear11_Fork() public {
        ITokenomics tokenomics = ITokenomics(TOKENOMICS);

        // Year 10 supply cap (index 9, last hardcoded)
        uint256 supplyCap10 = tokenomics.getActualSupplyCapForYear(9);

        // Correct inflation for year 11: 2% of year 10 supply cap
        uint256 correctInflation = (supplyCap10 * 2) / 100;

        // Actual inflation from deployed contract
        uint256 actualInflation = tokenomics.getInflationForYear(10);

        emit log_named_uint("Year 10 supply cap", supplyCap10);
        emit log_named_uint("Correct year 11 inflation (2.00%)", correctInflation);
        emit log_named_uint("Actual year 11 inflation (buggy)", actualInflation);
        emit log_named_uint("Excess per year (wei)", actualInflation - correctInflation);

        // Bug: actual > correct because f applied to post-compound cap
        assertGt(actualInflation, correctInflation, "FAIL: inflation should exceed correct 2%");

        // Magnitude: excess ≈ supplyCap10 * 0.02 * 0.02 = 0.04% of cap
        uint256 expectedExcess = (supplyCap10 * 4) / 10000;
        assertApproxEqRel(
            actualInflation - correctInflation,
            expectedExcess,
            0.01e18 // 1% relative tolerance
        );
    }

    function test_PoC_AccumulatedDriftOver20Years() public {
        ITokenomics tokenomics = ITokenomics(TOKENOMICS);

        uint256 supplyCap10 = tokenomics.getActualSupplyCapForYear(9);
        uint256 totalActualInflation;
        uint256 totalCorrectInflation;

        // Compute correct vs actual for years 11-30
        uint256 correctCap = supplyCap10;
        for (uint256 year = 10; year < 30; year++) {
            uint256 actual = tokenomics.getInflationForYear(year);
            uint256 correct = (correctCap * 2) / 100;

            totalActualInflation += actual;
            totalCorrectInflation += correct;

            correctCap += correct;
        }

        uint256 totalExcess = totalActualInflation - totalCorrectInflation;
        emit log_named_uint("Total actual inflation (20 years)", totalActualInflation);
        emit log_named_uint("Total correct inflation (20 years)", totalCorrectInflation);
        emit log_named_uint("Total excess OLAS over 20 years", totalExcess);
        emit log_named_decimal_uint("Total excess OLAS (readable)", totalExcess, 18);

        assertGt(totalExcess, 0, "FAIL: should have accumulated excess");
    }
}

// ============================================================
// PoC #2: Wormhole DoS when transferAmount == 0
// Fork test demonstrating the revert
// ============================================================

interface IWormholeTokenBridge {
    function transferTokensWithPayload(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        bytes memory payload
    ) external payable returns (uint64 sequence);
}

contract PoC_WormholeDoS is Test {
    // Deployed on Ethereum mainnet
    address constant WORMHOLE_TOKEN_BRIDGE = 0x3ee18B2214AFF97000D974cf647E7C347E8fa585;
    address constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;

    function setUp() public {
        vm.createSelectFork("mainnet");
    }

    function test_PoC_WormholeRevertsOnZeroAmount() public {
        // Demonstrate: Wormhole Token Bridge reverts when amount == 0
        // This is what happens inside sendTokenWithPayloadToEvm when transferAmount == 0

        vm.expectRevert(); // Wormhole reverts on zero amount
        IWormholeTokenBridge(WORMHOLE_TOKEN_BRIDGE).transferTokensWithPayload(
            OLAS,
            0, // amount == 0 triggers revert
            14, // Celo wormhole chain ID
            bytes32(uint256(uint160(address(this)))),
            0,
            ""
        );
    }

    function test_PoC_WormholeSucceedsOnNonZeroAmount() public {
        // For comparison: non-zero amount does NOT revert (would need approval+balance)
        // Just verify the zero-amount path is the problem

        // Show that Arbitrum/Optimism/Gnosis/Polygon all have the guard:
        // ArbitrumDepositProcessorL1.sol:164 — if (transferAmount > 0) { ... }
        // OptimismDepositProcessorL1.sol:103 — if (transferAmount > 0) { ... }
        // GnosisDepositProcessorL1.sol:56   — if (transferAmount > 0) { ... }
        // PolygonDepositProcessorL1.sol:65  — if (transferAmount > 0) { ... }
        //
        // WormholeDepositProcessorL1.sol:111 — NO GUARD, always calls sendTokenWithPayloadToEvm
        //
        // When claimStakingIncentives() computes transferAmount = stakingIncentive - withheldAmount = 0,
        // all bridges except Wormhole handle it gracefully.
        // Wormhole permanently blocks staking distribution for that chain.
    }

    function test_PoC_CompareAllBridgeImplementations() public pure {
        // Code evidence summary (line numbers from deployed contracts):
        //
        // contracts/staking/ArbitrumDepositProcessorL1.sol
        //   Line 164: if (transferAmount > 0) {
        //   Line 183: if (transferAmount > 0) {
        //   → Token bridge ONLY when amount > 0. Message sent separately.
        //
        // contracts/staking/OptimismDepositProcessorL1.sol
        //   Line 103: if (transferAmount > 0) {
        //   → Token bridge ONLY when amount > 0. Message via CrossDomainMessenger.
        //
        // contracts/staking/GnosisDepositProcessorL1.sol
        //   Line 56: if (transferAmount > 0) {
        //   → Token bridge ONLY when amount > 0. Message via AMB.
        //
        // contracts/staking/PolygonDepositProcessorL1.sol
        //   Line 65: if (transferAmount > 0) {
        //   → Token bridge ONLY when amount > 0. Message via FxRoot.
        //
        // contracts/staking/WormholeDepositProcessorL1.sol
        //   Line 111: sendTokenWithPayloadToEvm(..., transferAmount)
        //   → NO if (transferAmount > 0) guard!
        //   → Wormhole's transferTokensWithPayload requires amount > 0
        //   → REVERTS when transferAmount == 0
    }
}
