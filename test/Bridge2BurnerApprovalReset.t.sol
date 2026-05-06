// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../lib/zuniswapv2/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Bridge2BurnerOptimism} from "../contracts/utils/Bridge2BurnerOptimism.sol";
import {Bridge2BurnerGnosis}   from "../contracts/utils/Bridge2BurnerGnosis.sol";
import {Bridge2BurnerArbitrum} from "../contracts/utils/Bridge2BurnerArbitrum.sol";

/// @dev Stand-in for the L2 token relayer (Optimism `withdrawTo`, Gnosis `relayTokens`,
///      Arbitrum `outboundTransfer`). All three are no-ops here — we are only verifying
///      that approval is cleared *after* the bridge call, not the bridge call itself.
contract MockL2Relayer {
    function withdrawTo(address, address, uint256, uint32, bytes calldata) external {}
    function relayTokens(address, address, uint256) external {}
    function outboundTransfer(address, address, uint256, uint256, uint256, bytes calldata)
        external
        payable
        returns (bytes memory)
    {
        return "";
    }
}

/// @dev L-NEW-2 (PR #282): direct unit coverage that the OLAS allowance granted to
///      `l2TokenRelayer` is reset to 0 after each variant's `relayToL1Burner()` call.
///      Mocked to cover all three variants in one place — including Gnosis, which has
///      no fork test today.
///
///      Run: forge test --mc Bridge2BurnerApprovalReset -vvv
contract Bridge2BurnerApprovalResetTest is Test {
    // Arbitrary L1 OLAS sentinel for the Arbitrum constructor — only its non-zero-ness matters here.
    address internal constant L1_OLAS = address(0x000000000000000000000000000000000000AaA1);

    // MIN_OLAS_BALANCE on the base Bridge2Burner is 100 ether — fund slightly above it.
    uint256 internal constant FUND_AMOUNT = 150 ether;

    MockERC20 internal olas;
    MockL2Relayer internal relayer;

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS", 18);
        relayer = new MockL2Relayer();
    }

    /// @dev Optimism (also covers Base, which reuses Bridge2BurnerOptimism on OP-stack).
    function test_relayResetsApproval_Optimism() public {
        Bridge2BurnerOptimism b2b = new Bridge2BurnerOptimism(address(olas), address(relayer));
        olas.mint(address(b2b), FUND_AMOUNT);

        // Sanity — pre-call allowance is zero.
        assertEq(olas.allowance(address(b2b), address(relayer)), 0);

        b2b.relayToL1Burner();

        // L-NEW-2: residual allowance must be zero after the bridge call.
        assertEq(
            olas.allowance(address(b2b), address(relayer)),
            0,
            "Optimism: residual allowance not cleared"
        );
    }

    /// @dev Gnosis — variant has no fork test today; this is its primary coverage.
    function test_relayResetsApproval_Gnosis() public {
        Bridge2BurnerGnosis b2b = new Bridge2BurnerGnosis(address(olas), address(relayer));
        olas.mint(address(b2b), FUND_AMOUNT);

        assertEq(olas.allowance(address(b2b), address(relayer)), 0);

        b2b.relayToL1Burner();

        assertEq(
            olas.allowance(address(b2b), address(relayer)),
            0,
            "Gnosis: residual allowance not cleared"
        );
    }

    /// @dev Arbitrum.
    function test_relayResetsApproval_Arbitrum() public {
        Bridge2BurnerArbitrum b2b = new Bridge2BurnerArbitrum(address(olas), address(relayer), L1_OLAS);
        olas.mint(address(b2b), FUND_AMOUNT);

        assertEq(olas.allowance(address(b2b), address(relayer)), 0);

        b2b.relayToL1Burner();

        assertEq(
            olas.allowance(address(b2b), address(relayer)),
            0,
            "Arbitrum: residual allowance not cleared"
        );
    }
}
