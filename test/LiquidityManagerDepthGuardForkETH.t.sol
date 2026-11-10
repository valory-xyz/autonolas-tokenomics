// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerUniV2UniV3} from "../contracts/pol/LiquidityManagerUniV2UniV3.sol";

/// @dev Harness exposing the internal depth check and a direct factor setter against live pools.
contract LMForkHarness is LiquidityManagerUniV2UniV3 {
    constructor()
        LiquidityManagerUniV2UniV3(
            0x0001A500A6B18995B03f44bb040A5fFc28E45CB0, // OLAS (real, unused by the depth views)
            address(0xBEEF), // treasury (unused)
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88, // real NonfungiblePositionManager (factory() read in ctor)
            address(0xCAFE), // neighborhoodScanner (unused)
            1, // observationCardinality (unused)
            address(0xD00D) // routerV2 (unused)
        )
    {}

    function setFactor(uint256 f) external {
        minDepthFactor = f;
    }

    function checkDepth(address pool, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96) external view {
        _checkPoolDepth(pool, amount0, amount1, sqrtPriceX96);
    }
}

/// @notice Validates the depth metric and the entry-op check against LIVE mainnet V3 oracle data (the synthetic
///         unit tests use controlled observe() values; this exercises the real secondsPerLiquidity accumulation,
///         tick scale and price). Requires ETH_RPC_URL. Pinned for determinism.
contract LiquidityManagerDepthGuardForkETH is Test {
    // USDC/WETH 0.05% — very deep, continuous observation history.
    address constant DEEP_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    // USDC/WETH 1% — materially thinner than the 0.05% pool.
    address constant THIN_POOL = 0x7BeA39867e4169DBe237d55C8242a8f2fcDcc387;
    uint256 constant PIN_BLOCK = 21_000_000;

    LMForkHarness lm;

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            return; // skipped when no RPC configured
        }
        vm.createSelectFork(rpc, PIN_BLOCK);
        lm = new LMForkHarness();
    }

    modifier onFork() {
        if (address(lm) == address(0)) {
            emit log("ETH_RPC_URL not set - skipping fork test");
            return;
        }
        _;
    }

    // Reference price the production entry ops pass to the depth check: the TWAP-derived price from the
    // existing manipulation gate (checkPoolAndGetCenterPrice), not slot0.
    function _ref(address pool) internal view returns (uint160) {
        return lm.checkPoolAndGetCenterPrice(pool);
    }

    // slot0 price, for a plain metric-magnitude comparison on a pool that may lack a fresh TWAP.
    function _slot0(address pool) internal view returns (uint160 sqrtPriceX96) {
        (bool ok, bytes memory data) = pool.staticcall(abi.encodeWithSignature("slot0()"));
        require(ok, "slot0 failed");
        sqrtPriceX96 = abi.decode(data, (uint160));
    }

    function test_fork_metric_readsRealLiquidity() public onFork {
        uint128 hm = lm.windowHarmonicMeanLiquidity(DEEP_POOL);
        assertGt(uint256(hm), 0, "deep pool must report sustained in-range liquidity");

        uint160 sqrtP = _ref(DEEP_POOL);
        uint256 depth = lm.estimatedBandInventoryToken1(DEEP_POOL, sqrtP);
        assertGt(depth, 0, "deep pool must report positive executable depth");
        emit log_named_uint("deep pool harmonic-mean liquidity", uint256(hm));
        emit log_named_uint("deep pool band depth (token1/WETH wei)", depth);
    }

    function test_fork_metric_discriminatesDepth() public onFork {
        // Metric-magnitude comparison (not the production gate): use slot0 so a less-active pool without a
        // fresh TWAP is still comparable.
        uint256 deep = lm.estimatedBandInventoryToken1(DEEP_POOL, _slot0(DEEP_POOL));
        uint256 thin = lm.estimatedBandInventoryToken1(THIN_POOL, _slot0(THIN_POOL));
        emit log_named_uint("deep pool band depth", deep);
        emit log_named_uint("thin pool band depth", thin);
        // Both valued in WETH terms at their own price; the 0.05% pool is far deeper than the 1% pool.
        assertGt(deep, thin, "metric should rank the deep pool above the thin pool");
    }

    function test_fork_check_passesAndReverts_byFactor() public onFork {
        uint160 sqrtP = _ref(DEEP_POOL);
        uint256 depth = lm.estimatedBandInventoryToken1(DEEP_POOL, sqrtP);

        // factor 1x, notional (token1 terms) just below available depth -> passes.
        lm.setFactor(1e18);
        lm.checkDepth(DEEP_POOL, 0, depth / 2, sqrtP);

        // notional above available depth -> reverts InsufficientPoolDepth on live data.
        vm.expectRevert();
        lm.checkDepth(DEEP_POOL, 0, depth + 1, sqrtP);

        // factor 0 -> inactive even for an enormous notional.
        lm.setFactor(0);
        lm.checkDepth(DEEP_POOL, type(uint128).max, type(uint128).max, sqrtP);
    }
}
