// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {BuyBackBurner, ZeroAddress, V3PathDisabled, OwnerOnly} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// Minimal mock LM whose checkPoolAndGetCenterPrice returns a non-zero sqrt price; used to prove
// that the LM-only guard in checkPoolPrices passes when LM is non-zero, even with swapRouter == 0.
contract MockLM {
    uint160 public sqrtPriceX96 = 1 << 96;
    function factoryV3() external view returns (address) { return address(this); }
    function getPool(address, address, uint24) external view returns (address) { return address(0xBEEF); }
    function checkPoolAndGetCenterPrice(address) external view returns (uint160) { return sqrtPriceX96; }
    function factory() external view returns (address) { return address(this); }
}

/// @dev Unit tests for the V3-optional BuyBackBurner deployment mode introduced after PR #272.
///      Run: forge test --mc BuyBackBurnerV3Disabled -vvv
contract BuyBackBurnerV3DisabledTest is Test {
    address internal constant BRIDGE2BURNER = address(0xB10B);
    address internal constant TREASURY      = address(0x7157);
    address internal constant LM            = address(0x71C0);
    address internal constant ROUTER        = address(0xF00D);

    MockERC20 internal olas;

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS");
    }

    // -----------------------------------------------------------------------
    // Constructor: zero LM / swapRouter accepted, bridge2Burner / treasury required
    // -----------------------------------------------------------------------

    function test_constructor_acceptsZeroLiquidityManager() public {
        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(address(0), BRIDGE2BURNER, TREASURY, ROUTER);
        assertEq(impl.liquidityManager(), address(0));
        assertEq(impl.swapRouter(), ROUTER);
        assertEq(impl.bridge2Burner(), BRIDGE2BURNER);
        assertEq(impl.treasury(), TREASURY);
    }

    function test_constructor_acceptsZeroSwapRouter() public {
        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(LM, BRIDGE2BURNER, TREASURY, address(0));
        assertEq(impl.liquidityManager(), LM);
        assertEq(impl.swapRouter(), address(0));
    }

    function test_constructor_acceptsBothZero() public {
        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(address(0), BRIDGE2BURNER, TREASURY, address(0));
        assertEq(impl.liquidityManager(), address(0));
        assertEq(impl.swapRouter(), address(0));
    }

    function test_constructor_revertsOnZeroBridge2Burner() public {
        vm.expectRevert(ZeroAddress.selector);
        new BuyBackBurnerUniswap(LM, address(0), TREASURY, ROUTER);
    }

    function test_constructor_revertsOnZeroTreasury() public {
        vm.expectRevert(ZeroAddress.selector);
        new BuyBackBurnerUniswap(LM, BRIDGE2BURNER, address(0), ROUTER);
    }

    function test_constructor_revertsOnZeroBridge2Burner_balancerVariant() public {
        vm.expectRevert(ZeroAddress.selector);
        new BuyBackBurnerBalancer(LM, address(0), TREASURY, ROUTER);
    }

    function test_constructor_revertsOnZeroTreasury_balancerVariant() public {
        vm.expectRevert(ZeroAddress.selector);
        new BuyBackBurnerBalancer(LM, BRIDGE2BURNER, address(0), ROUTER);
    }

    // -----------------------------------------------------------------------
    // V3-touching surfaces revert V3PathDisabled when V3 is off
    // -----------------------------------------------------------------------

    function _deployProxy(address lm, address router) internal returns (BuyBackBurnerUniswap) {
        BuyBackBurnerUniswap impl = new BuyBackBurnerUniswap(lm, BRIDGE2BURNER, TREASURY, router);
        address[] memory accounts = new address[](4);
        accounts[0] = address(olas);
        accounts[1] = address(0);
        accounts[2] = address(0);
        accounts[3] = address(0);
        bytes memory initPayload = abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        return BuyBackBurnerUniswap(payable(address(proxy)));
    }

    function test_buyBackV3_revertsV3PathDisabled_whenLMZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), ROUTER);
        vm.expectRevert(V3PathDisabled.selector);
        bbb.buyBack(address(0xCAFE), 1 ether, int24(3000), 0);
    }

    function test_buyBackV3_revertsV3PathDisabled_whenSwapRouterZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(LM, address(0));
        vm.expectRevert(V3PathDisabled.selector);
        bbb.buyBack(address(0xCAFE), 1 ether, int24(3000), 0);
    }

    function test_buyBackV3_revertsV3PathDisabled_whenBothZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        vm.expectRevert(V3PathDisabled.selector);
        bbb.buyBack(address(0xCAFE), 1 ether, int24(3000), 0);
    }

    function test_setV3PoolStatuses_revertsV3PathDisabled_whenLMZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), ROUTER);
        address[] memory pools = new address[](1);
        pools[0] = address(0xBEEF);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(V3PathDisabled.selector);
        bbb.setV3PoolStatuses(pools, statuses);
    }

    function test_setV3PoolStatuses_revertsV3PathDisabled_whenSwapRouterZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(LM, address(0));
        address[] memory pools = new address[](1);
        pools[0] = address(0xBEEF);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(V3PathDisabled.selector);
        bbb.setV3PoolStatuses(pools, statuses);
    }

    /// @dev Owner check fires before the V3 guard, so non-owner callers see OwnerOnly even on a V3-off deployment.
    function test_setV3PoolStatuses_ownerCheckTakesPrecedence() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        address[] memory pools = new address[](1);
        bool[] memory statuses = new bool[](1);
        vm.prank(address(0xCAFE));
        vm.expectRevert(abi.encodeWithSelector(OwnerOnly.selector, address(0xCAFE), address(this)));
        bbb.setV3PoolStatuses(pools, statuses);
    }

    // -----------------------------------------------------------------------
    // checkPoolPrices uses _requireLiquidityManager (LM only, not swapRouter)
    // -----------------------------------------------------------------------

    function test_checkPoolPrices_revertsV3PathDisabled_whenLMZero() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), ROUTER);
        MockLM mockLM = new MockLM();
        vm.expectRevert(V3PathDisabled.selector);
        bbb.checkPoolPrices(address(0x1), address(0x2), address(mockLM), 3000);
    }

    /// @dev With LM populated and swapRouter == 0, checkPoolPrices passes the V3 guard and
    ///      delegates to LM as designed (swapRouter is not on its read path).
    function test_checkPoolPrices_succeedsWithSwapRouterZero() public {
        MockLM mockLM = new MockLM();
        BuyBackBurnerUniswap bbb = _deployProxy(address(mockLM), address(0));
        // No revert means the LM-only guard accepted swapRouter == 0
        bbb.checkPoolPrices(address(0x1), address(0x2), address(mockLM), 3000);
    }

    // -----------------------------------------------------------------------
    // V2-and-other admin surfaces unaffected by V3-off mode
    // -----------------------------------------------------------------------

    function test_setV2Oracles_succeedsWhenV3Disabled() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xCAFE);
        address[] memory oracles = new address[](1);
        oracles[0] = address(0xBABE);
        bbb.setV2Oracles(tokens, oracles);
        assertEq(bbb.mapV2Oracles(address(0xCAFE)), address(0xBABE));
    }

    function test_setMaxSlippages_succeedsWhenV3Disabled() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xCAFE);
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 500;
        bbb.setMaxSlippages(tokens, slippages);
        assertEq(bbb.mapTokenMaxSlippages(address(0xCAFE)), 500);
    }

    function test_changeOwner_succeedsWhenV3Disabled() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        bbb.changeOwner(address(0xCAFE));
        assertEq(bbb.owner(), address(0xCAFE));
    }

    function test_changeImplementation_succeedsWhenV3Disabled() public {
        BuyBackBurnerUniswap bbb = _deployProxy(address(0), address(0));
        // Deploy a fresh impl with V3 enabled and swap to it via the upgrade path
        BuyBackBurnerUniswap newImpl = new BuyBackBurnerUniswap(LM, BRIDGE2BURNER, TREASURY, ROUTER);
        bbb.changeImplementation(address(newImpl));
        // Post-upgrade: now the proxy delegatecalls into an impl with non-zero immutables → V3 enabled
        assertEq(BuyBackBurnerUniswap(payable(address(bbb))).liquidityManager(), LM);
        assertEq(BuyBackBurnerUniswap(payable(address(bbb))).swapRouter(), ROUTER);
    }
}
