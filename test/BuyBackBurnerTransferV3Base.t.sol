// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BuyBackBurner, UnauthorizedToken, UnauthorizedPool} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

interface IFactoryCL {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

interface IPoolCL {
    function tickSpacing() external view returns (int24);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
}

/// @dev Minimal LiquidityManager view stub — we only need `factoryV3()` for setV3Pools' canonicality
///      check on Base. The on-chain Base LiquidityManager isn't deployed yet (per audits/internal15
///      §"On-chain verification: NOT DEPLOYED on any chain"), so we deploy a tiny stand-in pointing
///      at the real Aerodrome CLFactory.
contract LMStubBase {
    address public immutable factoryV3Addr;
    constructor(address _factory) { factoryV3Addr = _factory; }
    function factoryV3() external view returns (address) { return factoryV3Addr; }
    function checkPoolAndGetCenterPrice(address) external pure returns (uint160) { return 0; }
}

/// @dev Fork tests for the L-06 fix on Base — exercises the `BuyBackBurnerBalancer` child's
///      Slipstream / `pool.tickSpacing()` reader branch, which was previously only mock-tested.
///      Mirror of `BuyBackBurnerTransferV3ETH.t.sol` but using:
///        - `BuyBackBurnerBalancer` (Slipstream V3 child) instead of `BuyBackBurnerUniswap`
///        - Aerodrome's `CLFactory` instead of Uniswap V3 factory
///        - `pool.tickSpacing()` (int24) instead of `pool.fee()` (uint24)
///        - Real OLAS/USDC pool that exists on Base mainnet at tickSpacing=100
///
///      Run: forge test -f $FORK_BASE_NODE_URL --mc BuyBackBurnerTransferV3Base -vvv
contract BuyBackBurnerTransferV3BaseTest is Test {
    // Base mainnet addresses
    address internal constant OLAS         = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH         = 0x4200000000000000000000000000000000000006;
    address internal constant USDC         = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant AERO_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A; // Aerodrome CLFactory
    address internal constant AERO_ROUTER  = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5; // Aerodrome SwapRouter
    address internal constant BRIDGE2BURNER = 0x000000000000000000000000000000000000Ba1B; // sentinel — only ID matters
    address internal constant TREASURY     = 0x000000000000000000000000000000000000bEEF; // sentinel — fresh treasury

    // Real OLAS/USDC Aerodrome Slipstream pool — token0 = OLAS, token1 = USDC, tickSpacing = 100
    address internal constant OLAS_USDC_POOL_TS100 = 0xa8bF464636F619fecBADdA3bd5d28f8C74970C39;
    int24   internal constant OLAS_USDC_TICK_SPACING = 100;

    // Real WETH/USDC Aerodrome Slipstream pool — used as a non-canonical sample (not paired with OLAS)
    address internal constant WETH_USDC_POOL_TS100  = 0xb2cc224c1c9feE385f8ad6a55b4d94E92359DC59;

    LMStubBase internal lm;
    BuyBackBurnerBalancer internal bbb;

    function setUp() public {
        // Deploy the LM stub pointing at the real Aerodrome CLFactory
        lm = new LMStubBase(AERO_FACTORY);

        // Deploy fresh BBB proxy. BuyBackBurnerBalancer's _initialize takes (address[], bytes32) —
        // accounts[0..3] = (olas, nativeToken, oracle, balancerVault), poolId payload.
        BuyBackBurnerBalancer impl = new BuyBackBurnerBalancer(address(lm), BRIDGE2BURNER, TREASURY, AERO_ROUTER);
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = address(0);
        accounts[2] = address(0);
        accounts[3] = address(0);
        bytes32 dummyPoolId = bytes32(0);
        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts, dummyPoolId));
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        bbb = BuyBackBurnerBalancer(payable(address(proxy)));
    }

    function _whitelistPool(address secondToken, address pool) internal {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = secondToken;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        bbb.setV3Pools(secondTokens, pools);
    }

    // -----------------------------------------------------------------------
    // L-06 / I-01: setV3Pools accepts a canonical Aerodrome Slipstream pool
    // -----------------------------------------------------------------------

    /// @dev Real OLAS/USDC tickSpacing=100 pool on Aerodrome — canonical-factory match passes.
    ///      Exercises the Slipstream / `pool.tickSpacing()` reader branch in
    ///      `BuyBackBurnerBalancer._readPoolFeeOrTickSpacing`.
    function testSetV3Pools_acceptsCanonicalOlasUsdcPool() public {
        // Sanity — confirm the pool is what we think it is on this fork
        assertEq(IPoolCL(OLAS_USDC_POOL_TS100).tickSpacing(), OLAS_USDC_TICK_SPACING);
        assertEq(IPoolCL(OLAS_USDC_POOL_TS100).token0(), OLAS);
        assertEq(IPoolCL(OLAS_USDC_POOL_TS100).token1(), USDC);
        // Factory must produce this exact pool address for (USDC, OLAS, ts=100)
        assertEq(
            IFactoryCL(AERO_FACTORY).getPool(USDC, OLAS, OLAS_USDC_TICK_SPACING),
            OLAS_USDC_POOL_TS100
        );

        _whitelistPool(USDC, OLAS_USDC_POOL_TS100);
        assertEq(bbb.mapV3Pools(USDC), OLAS_USDC_POOL_TS100);
    }

    /// @dev Non-canonical case: try to register the WETH/USDC pool against the USDC secondToken slot.
    ///      The pool has tickSpacing=100, but factory.getPool(USDC, OLAS, 100) ≠ WETH/USDC pool — revert.
    ///      Closes the I-01 admin-trust surface for the Slipstream branch.
    function testSetV3Pools_revertsOnNonCanonicalPool_realFactory() public {
        assertEq(IPoolCL(WETH_USDC_POOL_TS100).tickSpacing(), int24(100));

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = USDC;
        address[] memory pools = new address[](1);
        pools[0] = WETH_USDC_POOL_TS100;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, WETH_USDC_POOL_TS100));
        bbb.setV3Pools(secondTokens, pools);

        // No state side effects from the failed call
        assertEq(bbb.mapV3Pools(USDC), address(0));
    }

    /// @dev Non-existent pool: factory returns address(0) for (WETH, OLAS, ts=100). Operator-supplied
    ///      pool address is non-zero, so canonicality fails.
    function testSetV3Pools_revertsWhenFactoryReturnsZero_realFactory() public {
        // Verify the pool truly doesn't exist on Aerodrome (no OLAS/WETH pool at ts=100 today)
        assertEq(IFactoryCL(AERO_FACTORY).getPool(WETH, OLAS, int24(100)), address(0));

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = OLAS_USDC_POOL_TS100; // pool exists but not canonical for (WETH, OLAS, 100)

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, OLAS_USDC_POOL_TS100));
        bbb.setV3Pools(secondTokens, pools);
    }

    // -----------------------------------------------------------------------
    // L-06: transfer() blocks V3-eligible secondToken on a real fork
    // -----------------------------------------------------------------------

    /// @dev With the OLAS/USDC ts=100 pool wired as USDC's V3 pool, transfer(USDC) must revert.
    ///      Closes the L-06 griefing path on the Slipstream side.
    function testTransfer_revertsOnV3SecondToken_realFactory() public {
        _whitelistPool(USDC, OLAS_USDC_POOL_TS100);

        // Fund BBB with some USDC (USDC has 6 decimals on Base)
        deal(USDC, address(bbb), 1_000e6);
        assertEq(IERC20Like(USDC).balanceOf(address(bbb)), 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, USDC));
        bbb.transfer(USDC);

        assertEq(IERC20Like(USDC).balanceOf(address(bbb)), 1_000e6);
    }

    /// @dev Delisting (pool = address(0)) re-enables the sweep on Base.
    function testTransfer_succeedsAfterDelist_realFactory() public {
        _whitelistPool(USDC, OLAS_USDC_POOL_TS100);

        deal(USDC, address(bbb), 1_000e6);
        uint256 treasuryBefore = IERC20Like(USDC).balanceOf(TREASURY);

        // Delist
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = USDC;
        address[] memory pools = new address[](1);
        pools[0] = address(0);
        bbb.setV3Pools(secondTokens, pools);

        bbb.transfer(USDC);
        assertEq(IERC20Like(USDC).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(USDC).balanceOf(TREASURY) - treasuryBefore, 1_000e6);
    }

    /// @dev Unrelated tokens (no V2 oracle, no V3 pool) remain sweepable on Base.
    function testTransfer_succeedsForUnrelatedToken_realFactory() public {
        _whitelistPool(USDC, OLAS_USDC_POOL_TS100);

        // WETH is not in either swap path — must remain sweepable
        deal(WETH, address(bbb), 0.5 ether);
        uint256 treasuryBefore = IERC20Like(WETH).balanceOf(TREASURY);

        bbb.transfer(WETH);
        assertEq(IERC20Like(WETH).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(WETH).balanceOf(TREASURY) - treasuryBefore, 0.5 ether);
    }
}
