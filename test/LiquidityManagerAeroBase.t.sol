// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerBaseTest} from "./LiquidityManagerBase.t.sol";
import {LiquidityManagerBalancerSlipstream} from "../contracts/pol/LiquidityManagerBalancerSlipstream.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

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
