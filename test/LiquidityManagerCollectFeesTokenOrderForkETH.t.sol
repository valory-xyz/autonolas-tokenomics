// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {BaseSetup} from "./LiquidityManagerUniV2UniV3.t.sol";

/// @title LiquidityManagerCollectFeesTokenOrderForkETH
/// @dev collectFees() is permissionless and Uniswap resolves the same pool for either token ordering,
///      while the position manager always returns fees in the pool's canonical token0 < token1 order.
///      These fork tests pin the invariant that both orderings route identically: the OLAS-denominated
///      fee is burnt, the secondary-token fee goes to the treasury, and balances staged on the manager
///      are never touched.
contract LiquidityManagerCollectFeesTokenOrderForkETH is BaseSetup {
    // Routing outcome of a single collectFees() call
    struct Routed {
        uint256 olasBurnt;
        uint256 treasuryIn;
        uint256 managerOlasDelta;
        uint256 managerSecondaryDelta;
        uint256 returnedFirst;
        uint256 returnedSecond;
    }

    address internal constant CALLER = address(0xA11CE);

    /// @dev Creates the V3 position and accrues unequal fees on both sides of the pair.
    function _positionWithFees() internal {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25_000;
        tickShifts[1] = 15_000;

        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, 0, true);
        _roundTrip();
    }

    /// @dev Stages a pair balance on the manager, standing in for a pending owner operation. Fee routing
    ///      must never draw on it: only the just-collected amounts are managed.
    function _stage() internal {
        deal(OLAS, address(liquidityManager), initialAmounts[0]);
        deal(WETH, address(liquidityManager), initialAmounts[1]);
    }

    /// @dev Collects with the given ordering and measures where the value went.
    function _collectAndMeasure(address[] memory tokens) internal returns (Routed memory routed) {
        uint256 olasSupplyBefore = IToken(OLAS).totalSupply();
        uint256 treasuryBefore = IToken(WETH).balanceOf(TIMELOCK);
        uint256 managerOlasBefore = IToken(OLAS).balanceOf(address(liquidityManager));
        uint256 managerWethBefore = IToken(WETH).balanceOf(address(liquidityManager));

        vm.prank(CALLER);
        uint256[] memory amounts = liquidityManager.collectFees(tokens, FEE_TIER);

        routed.olasBurnt = olasSupplyBefore - IToken(OLAS).totalSupply();
        routed.treasuryIn = IToken(WETH).balanceOf(TIMELOCK) - treasuryBefore;
        routed.managerOlasDelta = _absDelta(IToken(OLAS).balanceOf(address(liquidityManager)), managerOlasBefore);
        routed.managerSecondaryDelta = _absDelta(IToken(WETH).balanceOf(address(liquidityManager)), managerWethBefore);
        routed.returnedFirst = amounts[0];
        routed.returnedSecond = amounts[1];
    }

    function _absDelta(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _ordered(address first, address second) internal pure returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = first;
        tokens[1] = second;
    }

    /// @dev Positive case: the canonical ordering burns the OLAS fee, sends the secondary fee to the
    ///      treasury, and leaves staged balances untouched.
    function test_collectFeesCanonicalOrderRoutesFees() public {
        _positionWithFees();
        _stage();

        Routed memory routed = _collectAndMeasure(_ordered(OLAS, WETH));

        assertGt(routed.returnedFirst, 0, "no OLAS fee accrued");
        assertGt(routed.returnedSecond, 0, "no secondary fee accrued");
        assertTrue(routed.returnedFirst != routed.returnedSecond, "fees must be unequal to expose ordering");

        assertEq(routed.olasBurnt, routed.returnedFirst, "OLAS fee must be burnt");
        assertEq(routed.treasuryIn, routed.returnedSecond, "secondary fee must reach the treasury");
        assertEq(routed.managerOlasDelta, 0, "staged OLAS must be untouched");
        assertEq(routed.managerSecondaryDelta, 0, "staged secondary must be untouched");
    }

    /// @dev Negative case: a reversed ordering must produce the identical routing. Before the alignment
    ///      fix this call burnt the secondary-token fee amount as OLAS and transferred the OLAS fee amount
    ///      as the secondary token, drawing the difference from the staged balances.
    function test_collectFeesReversedOrderRoutesIdentically() public {
        _positionWithFees();
        _stage();

        uint256 snapshotId = vm.snapshotState();
        Routed memory canonical = _collectAndMeasure(_ordered(OLAS, WETH));

        vm.revertToState(snapshotId);
        _stage();
        Routed memory reversed = _collectAndMeasure(_ordered(WETH, OLAS));

        // Same value, same destinations, whichever order the caller used
        assertEq(reversed.olasBurnt, canonical.olasBurnt, "reversed order must burn the same OLAS fee");
        assertEq(reversed.treasuryIn, canonical.treasuryIn, "reversed order must send the same secondary fee");

        // Staged balances are never a funding source for fee routing
        assertEq(reversed.managerOlasDelta, 0, "reversed order must not touch staged OLAS");
        assertEq(reversed.managerSecondaryDelta, 0, "reversed order must not touch staged secondary");

        // The returned array follows the caller's ordering, so it is the mirror of the canonical one
        assertEq(reversed.returnedFirst, canonical.returnedSecond, "returned amounts must follow caller order");
        assertEq(reversed.returnedSecond, canonical.returnedFirst, "returned amounts must follow caller order");

        // Explicitly pin the pre-fix transposition as absent
        assertTrue(canonical.returnedFirst != canonical.returnedSecond, "fees must be unequal for this check");
        assertTrue(reversed.olasBurnt != canonical.returnedSecond, "must not burn the secondary fee amount as OLAS");
    }
}
