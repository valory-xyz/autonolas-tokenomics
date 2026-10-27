// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerBaseTest, ISlipstream, INPMMintSlipstream} from "./LiquidityManagerBase.t.sol";
import {LiquidityManagerBalancerSlipstream} from "../contracts/pol/LiquidityManagerBalancerSlipstream.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

import {NotEnoughHistory} from "../contracts/pol/LiquidityManagerCore.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";

interface IAeroStartupFactory {
    function getPoolSwapHook(address pool) external view returns (address);
    function swapFeeManager() external view returns (address);
}

interface IAeroStartupHook {
    function setFeeCap(address pool, uint24 cap) external;
    function setScalingFactor(address pool, uint64 factor) external;
    function blockFee(address pool, uint256 number) external view returns (uint256);
    function secondsAgo() external view returns (uint32);
}

interface IAeroPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @dev Reuses every Base lifecycle assertion with only the DEX deployment addresses changed.
///      Official manifests: Dromos-Labs/metadex-slipstream-public at
///      f99f2095918cab69eafeffa2c3d0a8762de737b7, deployment-addresses/cl-base.json.
///      Run against Base block 53153049; all deployments and upgrades occur only on the local fork.
contract LiquidityManagerAeroBaseTest is LiquidityManagerBaseTest {
    address internal EXISTING_LM_PROXY = 0x2ACD313B892C9922E470e4950e907d5EAa70fC2a;

    function _configureSlipstream() internal virtual override {
        assertEq(block.chainid, 8453);
        ROUTER_V3 = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;
        FACTORY_V3 = 0x9CB220581b91b0C83223012FE69688b92aD07a76;
        POSITION_MANAGER_V3 = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
    }

    function testUpgradeExistingProxy_preservesStateAndMintsAeroPosition() public {
        LiquidityManagerBalancerSlipstream existing = LiquidityManagerBalancerSlipstream(EXISTING_LM_PROXY);
        address previousOwner = existing.owner();
        uint16 previousSlippage = existing.maxSlippage();
        address previousTreasury = existing.treasury();
        uint256 previousOlasBalance = IToken(OLAS).balanceOf(EXISTING_LM_PROXY);
        uint256 previousWethBalance = IToken(WETH).balanceOf(EXISTING_LM_PROXY);

        LiquidityManagerBalancerSlipstream replacement = new LiquidityManagerBalancerSlipstream(
            existing.olas(), previousTreasury, POSITION_MANAGER_V3,
            existing.neighborhoodScanner(), existing.observationCardinality(),
            existing.balancerVault(), existing.bridge2Burner()
        );
        vm.prank(previousOwner);
        existing.changeImplementation(address(replacement));

        assertEq(address(existing), EXISTING_LM_PROXY);
        assertEq(existing.owner(), previousOwner);
        assertEq(existing.maxSlippage(), previousSlippage);
        assertEq(existing.treasury(), previousTreasury);
        assertEq(existing.positionManagerV3(), POSITION_MANAGER_V3);
        assertEq(existing.factoryV3(), FACTORY_V3);
        assertEq(IToken(OLAS).balanceOf(EXISTING_LM_PROXY), previousOlasBalance);
        assertEq(IToken(WETH).balanceOf(EXISTING_LM_PROXY), previousWethBalance);

        // Fixed test funding; this is not a measurement of live market depth or treasury funds.
        deal(OLAS, EXISTING_LM_PROXY, 10_000 ether);
        deal(WETH, EXISTING_LM_PROXY, 1 ether);
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        vm.prank(previousOwner);
        (uint256 positionId, uint256 liquidity,) =
            existing.convertToV3(TOKENS, bytes32(0), TICK_SPACING, tickShifts, 0, true);
        assertGt(liquidity, 0);
        assertEq(IAeroPositionOwner(POSITION_MANAGER_V3).ownerOf(positionId), EXISTING_LM_PROXY);
    }
}

/// @dev Same lifecycle and existing-proxy upgrade assertions on Optimism block 158748334.
contract LiquidityManagerAeroOptimismTest is LiquidityManagerAeroBaseTest {
    function _configureSlipstream() internal override {
        _configureOptimism(true);
        EXISTING_LM_PROXY = 0x1f84F8F70dE0651C2d51Bf8850FE9D0289Ba3B3A;
    }
}

/// @dev Control suite for the currently configured legacy Optimism deployment.
contract LiquidityManagerLegacyOptimismTest is LiquidityManagerBaseTest {
    function _configureSlipstream() internal override { _configureOptimism(false); }
}

/// @dev The complete existing Aero lifecycle runs after dynamics-enabled seed preparation.
contract LiquidityManagerAeroStartupBaseTest is LiquidityManagerAeroBaseTest {
    function _warmUpV3Pool(address pool) internal override {
        IAeroStartupFactory factory = IAeroStartupFactory(FACTORY_V3);
        IAeroStartupHook hook = IAeroStartupHook(factory.getPoolSwapHook(pool));
        vm.startPrank(factory.swapFeeManager());
        hook.setFeeCap(pool, 50_000);
        hook.setScalingFactor(pool, 1_000_000_000);
        vm.stopPrank();
        vm.txGasPrice(block.basefee);
        assertEq(hook.secondsAgo(), 600);
        uint256 created = vm.getBlockTimestamp(); // Freeze before warps; avoid optimizer caching block.timestamp.
        _expectFreshHistoryRevert(pool);
        ISlipstream(pool).increaseObservationCardinalityNext(observationCardinality);
        int24 center = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        deal(WETH, address(this), 20 ether);
        deal(OLAS, address(this), 500_000 ether);
        IToken(WETH).approve(POSITION_MANAGER_V3, 20 ether);
        IToken(OLAS).approve(POSITION_MANAGER_V3, 500_000 ether);
        (uint256 id, uint128 liquidity,,) = INPMMintSlipstream(POSITION_MANAGER_V3).mint(
            INPMMintSlipstream.MintParams(WETH, OLAS, TICK_SPACING,
                ((center - 30000) / TICK_SPACING) * TICK_SPACING,
                ((center + 30000) / TICK_SPACING) * TICK_SPACING,
                20 ether, 500_000 ether, 0, 0, address(this), block.timestamp, 0));
        assertGt(liquidity, 0);
        _expectFreshHistoryRevert(pool);

        _advanceStartup(created + 1);
        uint256 firstOut = _swap(WETH, OLAS, 0.01 ether);
        assertEq(hook.blockFee(pool, block.number), 10_000, "no dynamic history: base fee");
        // A fresh block still has insufficient 600-second hook history.
        _advanceStartup(created + 599);
        _swap(WETH, OLAS, 0.01 ether);
        assertEq(hook.blockFee(pool, block.number), 10_000);
        _expectFreshHistoryRevert(pool);
        _advanceStartup(created + 600);
        _swap(OLAS, WETH, firstOut);
        assertGt(hook.blockFee(pool, block.number), 10_000, "dynamic component must activate");
        assertLe(hook.blockFee(pool, block.number), 50_000);
        _expectFreshHistoryRevert(pool); // Hook history is shorter than the LM's 1800 seconds.
        _advanceStartup(created + 900);
        oracleV2.updatePrice();
        _advanceStartup(created + 1799);
        _expectFreshHistoryRevert(pool);
        _roundTrip(); // Ends at exactly 1800 seconds, within the V2 freshness bound.
        oracleV2.updatePrice();
        liquidityManager.checkPoolAndGetCenterPrice(pool);
        oracleV2.getTWAP();
        INPMMintSlipstream(POSITION_MANAGER_V3).decreaseLiquidity(
            INPMMintSlipstream.DecreaseLiquidityParams(id, liquidity, 0, 0, block.timestamp));
        (uint256 amount0, uint256 amount1) = INPMMintSlipstream(POSITION_MANAGER_V3).collect(
            INPMMintSlipstream.CollectParams(id, address(this), type(uint128).max, type(uint128).max));
        assertGt(amount0, 0);
        assertGt(amount1, 0);
        liquidityManager.checkPoolAndGetCenterPrice(pool);
    }

    function _advanceStartup(uint256 timestamp) private {
        vm.warp(timestamp);
        vm.roll(block.number + 1);
    }

    function _expectFreshHistoryRevert(address pool) private {
        vm.expectRevert(abi.encodeWithSelector(NotEnoughHistory.selector, pool));
        liquidityManager.checkPoolAndGetCenterPrice(pool);
    }
}

contract LiquidityManagerAeroStartupOptimismTest is LiquidityManagerAeroStartupBaseTest {
    function _configureSlipstream() internal override {
        _configureOptimism(true);
        EXISTING_LM_PROXY = 0x1f84F8F70dE0651C2d51Bf8850FE9D0289Ba3B3A;
    }
}
