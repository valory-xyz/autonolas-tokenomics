// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UniswapOracleBaseSetup} from "./UniswapPriceOracle.t.sol";
import {UniswapPriceOracle, Overflow, ZeroValue} from "../contracts/oracles/UniswapPriceOracle.sol";

contract UniswapPriceOracleWindowTest is UniswapOracleBaseSetup {
    function warmUp() internal returns (uint256 start) {
        start = block.timestamp;
        assertTrue(oracle.updatePrice());
        vm.warp(start + minUpdateInterval);
        assertTrue(oracle.updatePrice());
    }

    function test_initialWarmUpRequiresTwoObservations() public {
        vm.expectRevert(ZeroValue.selector);
        oracle.getTWAP();
        assertTrue(oracle.updatePrice());
        vm.expectRevert(ZeroValue.selector);
        oracle.getTWAP();
        vm.warp(block.timestamp + minUpdateInterval);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), 1 ether);
    }

    function test_windowAgeBoundaryWithFreshLatestObservation() public {
        uint256 start = warmUp();
        vm.warp(start + maxStaleness);
        assertEq(oracle.getTWAP(), 1 ether);
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
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
    }

    function test_recoveryExcludesOldPriceHistory() public {
        warmUp();
        vm.warp(block.timestamp + maxStaleness + 1);
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(olas);
        router.swapExactTokensForTokens(500 ether, 0, path, address(this));
        uint256 freshPrice = (oracle.getPrice() * 1 ether) >> 112;
        assertLt(freshPrice, 1 ether);
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
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
            assertEq(oracle.getTWAP(), 1 ether);
            assertTrue(oracle.updatePrice());
            assertEq(oracle.getTWAP(), 1 ether);
        }
    }

    function test_constructorRejectsUpdateIntervalBeyondMaximumWindow() public {
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        new UniswapPriceOracle(pair, address(olas), minTwapWindow, maxStaleness + 1, maxStaleness);
    }

    function test_updateIntervalAtMaximumWindowCanRecover() public {
        oracle = new UniswapPriceOracle(pair, address(olas), minTwapWindow, maxStaleness, maxStaleness);
        assertTrue(oracle.updatePrice());
        vm.warp(block.timestamp + maxStaleness);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), 1 ether);
        vm.warp(block.timestamp + maxStaleness + 1);
        assertTrue(oracle.updatePrice());
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, maxStaleness + 1, maxStaleness));
        oracle.getTWAP();
        vm.warp(block.timestamp + maxStaleness);
        assertTrue(oracle.updatePrice());
        assertEq(oracle.getTWAP(), 1 ether);
    }
}
