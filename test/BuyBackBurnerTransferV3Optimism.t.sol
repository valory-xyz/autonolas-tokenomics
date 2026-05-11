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
    function factory() external view returns (address);
}

interface ISwapRouterCL {
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
}

/// @dev Minimal LiquidityManager view stub — same pattern as `LMStubBase` in
///      `BuyBackBurnerTransferV3Base.t.sol`. The on-chain Optimism LiquidityManager
///      isn't deployed yet (its proxy address is empty in `globals_optimism_mainnet.json`),
///      so we deploy a tiny stand-in pointing at the real Velodrome Slipstream CLFactory.
contract LMStubOptimism {
    address public immutable factoryV3Addr;
    constructor(address _factory) { factoryV3Addr = _factory; }
    function factoryV3() external view returns (address) { return factoryV3Addr; }
    function checkPoolAndGetCenterPrice(address) external pure returns (uint160) { return 0; }
}

/// @dev Fork tests for the Optimism BBB wiring against the real Velodrome Slipstream router.
///      Mirror of `BuyBackBurnerTransferV3Base.t.sol` but using:
///        - Velodrome (Optimism) instead of Aerodrome (Base)
///        - SwapRouter `0xbA3aEe516399388C779463183d00bB579f5041Ca`
///        - CLFactory `0xe13Dd1fbA721Aa81a1826D9523AC9BC7d260c879`
///        - No real OLAS Velodrome CL pool exists on Optimism today, so the "canonical pool
///          accepted" positive path is not exercised against a live OLAS pool — only the
///          rejection paths and the sweep path. If/when an OLAS Velodrome CL pool ships,
///          add the canonical-acceptance test mirroring the Base one.
///
///      Run: forge test -f $FORK_OPTIMISM_NODE_URL --mc BuyBackBurnerTransferV3Optimism -vvv
contract BuyBackBurnerTransferV3OptimismTest is Test {
    // Optimism mainnet addresses
    address internal constant OLAS         = 0xFC2E6e6BCbd49ccf3A5f029c79984372DcBFE527;
    address internal constant WETH         = 0x4200000000000000000000000000000000000006;
    address internal constant USDC         = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // native USDC on OP (6 decimals)
    address internal constant VELO_FACTORY = 0xe13Dd1fbA721Aa81a1826D9523AC9BC7d260c879; // Velodrome Slipstream CLFactory
    address internal constant VELO_ROUTER  = 0xbA3aEe516399388C779463183d00bB579f5041Ca; // Velodrome Slipstream SwapRouter
    address internal constant BRIDGE2BURNER = 0x000000000000000000000000000000000000Ba1B; // sentinel — only ID matters
    address internal constant TREASURY     = 0x000000000000000000000000000000000000bEEF; // sentinel — fresh treasury

    // Real WETH/USDC Velodrome Slipstream pool — token0 = USDC, token1 = WETH, tickSpacing = 50.
    // Used as a "non-canonical" sample: it exists, but is not OLAS-paired, so registering it
    // against an OLAS-context secondToken slot must revert under the I-01 canonicality check.
    address internal constant WETH_USDC_POOL_TS50 = 0xc092E9CBdb4148837FC54bc5233c12C2fc83B4DB;

    LMStubOptimism internal lm;
    BuyBackBurnerBalancer internal bbb;

    function setUp() public {
        // Sanity — Velodrome Slipstream router/factory wiring on this fork
        assertEq(ISwapRouterCL(VELO_ROUTER).factory(), VELO_FACTORY, "router.factory mismatch");
        assertEq(ISwapRouterCL(VELO_ROUTER).WETH9(), WETH, "router.WETH9 mismatch");

        // Sanity — pool's factory ancestry (Slipstream pools expose factory())
        assertEq(IPoolCL(WETH_USDC_POOL_TS50).factory(), VELO_FACTORY, "pool.factory mismatch");
        assertEq(IPoolCL(WETH_USDC_POOL_TS50).tickSpacing(), int24(50));

        // Deploy the LM stub pointing at the real Velodrome CLFactory
        lm = new LMStubOptimism(VELO_FACTORY);

        // Deploy fresh BBB proxy. BuyBackBurnerBalancer's _initialize takes (address[], bytes32) —
        // accounts[0..3] = (olas, nativeToken, oracle, balancerVault), poolId payload.
        BuyBackBurnerBalancer impl = new BuyBackBurnerBalancer(address(lm), BRIDGE2BURNER, TREASURY, VELO_ROUTER);
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

    // -----------------------------------------------------------------------
    // Smoke: BBB immutables wire through to Velodrome on Optimism
    // -----------------------------------------------------------------------

    function testImmutables_wireToVelodrome() public {
        assertEq(bbb.liquidityManager(), address(lm));
        assertEq(bbb.swapRouter(), VELO_ROUTER);
        assertEq(bbb.bridge2Burner(), BRIDGE2BURNER);
        assertEq(bbb.treasury(), TREASURY);
        assertEq(bbb.olas(), OLAS);
    }

    // -----------------------------------------------------------------------
    // I-01: setV3Pools rejects non-canonical / non-existent OLAS pool registrations
    //       (no real OLAS Velodrome CL pool exists on Optimism today, so the
    //       canonical-acceptance branch can't be exercised — only rejection.)
    // -----------------------------------------------------------------------

    /// @dev Confirms there is currently no OLAS/USDC Velodrome CL pool on Optimism
    ///      (covers the common Slipstream tickSpacings).
    function testFactory_noOlasUsdcPoolExists() public {
        int24[5] memory tickSpacings = [int24(1), int24(50), int24(100), int24(200), int24(2000)];
        for (uint256 i = 0; i < tickSpacings.length; ++i) {
            assertEq(
                IFactoryCL(VELO_FACTORY).getPool(OLAS, USDC, tickSpacings[i]),
                address(0),
                "OLAS/USDC pool unexpectedly exists at this tickSpacing"
            );
        }
    }

    /// @dev Non-canonical: the real WETH/USDC ts=50 pool exists but is not OLAS-paired.
    ///      setV3Pools reads `pool.tickSpacing() = 50`, then queries
    ///      `factory.getPool(USDC, OLAS, 50) = address(0)` ≠ pool → revert.
    function testSetV3Pools_revertsOnNonCanonicalPool_realFactory() public {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = USDC;
        address[] memory pools = new address[](1);
        pools[0] = WETH_USDC_POOL_TS50;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, WETH_USDC_POOL_TS50));
        bbb.setV3Pools(secondTokens, pools);

        assertEq(bbb.mapV3Pools(USDC), address(0));
    }

    /// @dev Non-existent OLAS pool: factory.getPool(WETH, OLAS, ts=50) = address(0).
    ///      Operator-supplied pool address is non-zero (the real WETH/USDC ts=50 pool),
    ///      so the canonicality check fails.
    function testSetV3Pools_revertsWhenFactoryReturnsZero_realFactory() public {
        assertEq(IFactoryCL(VELO_FACTORY).getPool(WETH, OLAS, int24(50)), address(0));

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = WETH_USDC_POOL_TS50;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, WETH_USDC_POOL_TS50));
        bbb.setV3Pools(secondTokens, pools);
    }

    // -----------------------------------------------------------------------
    // L-06: transfer() sweep path — unrelated tokens remain sweepable on Optimism
    // -----------------------------------------------------------------------

    /// @dev With no V3 entries set (mapV3Pools is empty), transfer() must sweep
    ///      arbitrary held tokens to the configured treasury.
    function testTransfer_succeedsForUnrelatedToken_realFactory() public {
        deal(WETH, address(bbb), 0.5 ether);
        uint256 treasuryBefore = IERC20Like(WETH).balanceOf(TREASURY);

        bbb.transfer(WETH);
        assertEq(IERC20Like(WETH).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(WETH).balanceOf(TREASURY) - treasuryBefore, 0.5 ether);
    }

    /// @dev USDC sweep — exercises the same code path with a 6-decimal token.
    function testTransfer_succeedsForUsdc_realFactory() public {
        deal(USDC, address(bbb), 1_000e6);
        uint256 treasuryBefore = IERC20Like(USDC).balanceOf(TREASURY);

        bbb.transfer(USDC);
        assertEq(IERC20Like(USDC).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(USDC).balanceOf(TREASURY) - treasuryBefore, 1_000e6);
    }
}
