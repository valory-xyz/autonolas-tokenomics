// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerCore, RatioDeviation} from "../contracts/pol/LiquidityManagerCore.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

/// @dev Minimal mock for positionManagerV3 — only factory() is called in the Core constructor.
contract MockPositionManager {
    address public factoryAddr;

    constructor(address _factory) {
        factoryAddr = _factory;
    }

    function factory() external view returns (address) {
        return factoryAddr;
    }
}

/// @dev Concrete LiquidityManagerCore that exposes the internal source-side ratio cross-check and lets a test
///      set `maxSlippage` directly. All other abstract virtuals are stubbed — only `_checkRemovedRatioAgainstV3`
///      is under test.
contract RatioCheckHarness is LiquidityManagerCore {
    constructor(address _positionManager)
        LiquidityManagerCore(address(1), address(2), _positionManager, address(3), 1)
    {}

    function setMaxSlippage(uint16 m) external {
        maxSlippage = m;
    }

    function checkRatio(uint256 removed0, uint256 removed1, uint160 sqrtPriceX96) external view {
        _checkRemovedRatioAgainstV3(removed0, removed1, sqrtPriceX96);
    }

    // --- stubbed virtuals (not exercised here) ---
    function _burn(uint256) internal override {}

    function _checkTokensAndRemoveLiquidityV2(address[] memory, bytes32)
        internal
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
    }

    function _feeAmountTickSpacing(int24 f) internal pure override returns (int24) {
        return f;
    }

    function _getV3Pool(address[] memory, int24) internal pure override returns (address) {
        return address(0);
    }

    function _mintV3(address[] memory, uint256[] memory, uint256[] memory, int24[] memory, int24, uint160)
        internal
        override
        returns (uint256, uint128, uint256[] memory)
    {
        uint256[] memory a = new uint256[](2);
        return (0, 0, a);
    }
}

/// @title Unit tests for LiquidityManagerCore._checkRemovedRatioAgainstV3 (issue #324 cross-check)
/// @dev Deterministic, no-fork coverage of the arithmetic edges the fork suites only hit at realistic values:
///      the inclusive tolerance boundary in both directions, `maxSlippage = 0`, and overflow-safety of the
///      staged mulDiv at a WETH/USDC-scale sqrtP. Run: forge test --mc LiquidityManagerRatioCheckUnit -vvv
contract LiquidityManagerRatioCheckUnitTest is Test {
    RatioCheckHarness internal h;

    // sqrtPriceX96 for price = 1 (token1 per token0 == 1) => referenceRatio == 1e18. Makes the bps math exact.
    uint160 internal constant Q96 = 0x1000000000000000000000000; // 2**96

    function setUp() public {
        MockPositionManager pm = new MockPositionManager(address(0xF));
        h = new RatioCheckHarness(address(pm));
    }

    // Reference price 1.0; removed ratio 1.0 => diff 0 => passes at any tolerance.
    function test_exactMatch_passes() public {
        h.setMaxSlippage(500);
        h.checkRatio(1e18, 1e18, Q96);
    }

    // At exactly maxSlippage the guard is inclusive (revert only when diff STRICTLY exceeds the bound).
    // 5% tolerance, reference 1e18 => bound 5e16. Ratio 1.05 and 0.95 both sit exactly on the bound.
    function test_atToleranceEdge_bothDirections_pass() public {
        h.setMaxSlippage(500);
        h.checkRatio(100, 105, Q96); // ratio 1.05 -> diff == 5% bound
        h.checkRatio(100, 95, Q96); // ratio 0.95 -> diff == 5% bound (symmetric)
    }

    // One wei past the bound (above the reference) reverts.
    function test_justOverTolerance_above_reverts() public {
        h.setMaxSlippage(500);
        vm.expectPartialRevert(RatioDeviation.selector);
        h.checkRatio(1e18, 105e16 + 1, Q96); // ratio 1.05e18 + 1 -> diff 5e16 + 1 > bound
    }

    // One wei past the bound (below the reference) reverts too — the guard is symmetric.
    function test_justOverTolerance_below_reverts() public {
        h.setMaxSlippage(500);
        vm.expectPartialRevert(RatioDeviation.selector);
        h.checkRatio(1e18, 95e16 - 1, Q96); // ratio 0.95e18 - 1 -> diff 5e16 + 1 > bound
    }

    // maxSlippage == 0 => bound 0 => only an exact match passes; any nonzero divergence reverts.
    function test_zeroTolerance_onlyExactPasses() public {
        h.setMaxSlippage(0);
        h.checkRatio(1e18, 1e18, Q96); // exact -> passes
        vm.expectPartialRevert(RatioDeviation.selector);
        h.checkRatio(1e18, 1e18 + 1, Q96); // off by one wei -> reverts
    }

    // WETH/USDC-scale sqrtP (~1.8e33): sqrtP^2 ~ 3.2e66 fits in uint256, so the staged mulDiv must NOT overflow.
    // Parity case (removed ratio == reference by construction) passes; a grossly-off ratio reverts with
    // RatioDeviation (not an arithmetic panic), proving the whole computation ran.
    function test_highPrice_noOverflow() public {
        h.setMaxSlippage(500);
        uint160 sqrtP = 1829051650017666386914232435074991; // real WETH/USDC 0.05% slot0

        // removed0 = Q96, removed1 = sqrtP^2/Q96  =>  removedRatio == referenceRatio exactly.
        uint256 removed1 = mulDiv(uint256(sqrtP), uint256(sqrtP), Q96);
        h.checkRatio(Q96, removed1, sqrtP); // parity -> passes, exercising the big-number path

        vm.expectPartialRevert(RatioDeviation.selector);
        h.checkRatio(1e18, 1, sqrtP); // ratio ~0 vs a huge reference -> reverts, no overflow
    }
}
