// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BalancerOracleBaseSetup} from "./BalancerPriceOracle.t.sol";
import {BalancerPriceOracle, Overflow} from "../contracts/oracles/BalancerPriceOracle.sol";

contract BalancerPriceOracleWindowTest is BalancerOracleBaseSetup {
    function warmUp() internal returns (uint256 start) {
        start = block.timestamp;
        assertTrue(oracle.updatePrice());
        vm.warp(start + minUpdateInterval);
        assertTrue(oracle.updatePrice());
    }

    function test_windowAgeBoundaryWithFreshLatestObservation() public {
        uint256 start = warmUp();
        // The window starts at `prev` (= start); a quote stays valid up to maxStaleness past it.
        vm.warp(start + maxStaleness);
        assertEq(oracle.getTWAP(), 1e18);
        vm.warp(start + maxStaleness + 1);
        // The latest observation is still fresh, but the averaging window is too old.
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
    }

    function test_oneUpdateAfterInactivityDoesNotRestoreQuotes() public {
        warmUp();
        uint256 lastUpdate = block.timestamp;
        vm.warp(lastUpdate + maxStaleness + 1);
        vm.expectRevert();
        oracle.getTWAP();
        // A single update after the gap only shifts the stale observation into the window start.
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
    }

    function test_recoveryExcludesOldPriceHistory() public {
        warmUp();
        vm.warp(block.timestamp + maxStaleness + 1);
        // Move the spot price (OLAS is tokens[1], direction 0, so price = olas / weth).
        _setBalances(5000 ether, 10_000 ether);
        uint256 freshPrice = oracle.getPrice();
        assertEq(freshPrice, 2e18);
        // One update after inactivity still cannot quote: the window start is the pre-gap observation.
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
        // A second update must respect the min interval, then the window sits entirely in the new regime.
        vm.warp(block.timestamp + minUpdateInterval - 1);
        assertFalse(oracle.updatePrice());
        vm.warp(block.timestamp + 1);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), freshPrice);
    }

    function test_regularUpdatesKeepQuotesAvailable() public {
        warmUp();
        for (uint256 i; i < 4; ++i) {
            vm.warp(block.timestamp + minUpdateInterval);
            assertEq(oracle.getTWAP(), 1e18);
            assertTrue(oracle.updatePrice());
            assertEq(oracle.getTWAP(), 1e18);
        }
    }

    function test_constructorRejectsUpdateIntervalBeyondMaximumWindow() public {
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        new BalancerPriceOracle(address(vault), poolId, olas, minTwapWindow, maxStaleness + 1, maxStaleness);
    }

    function test_updateIntervalAtMaximumWindowCanRecover() public {
        oracle = new BalancerPriceOracle(address(vault), poolId, olas, minTwapWindow, maxStaleness, maxStaleness);
        assertTrue(oracle.updatePrice());
        vm.warp(block.timestamp + maxStaleness);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), 1e18);
        vm.warp(block.timestamp + maxStaleness + 1);
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
        vm.warp(block.timestamp + maxStaleness);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), 1e18);
    }
}
