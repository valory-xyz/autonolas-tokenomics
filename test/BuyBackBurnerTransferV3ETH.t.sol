// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BuyBackBurner, UnauthorizedToken, UnauthorizedPool} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

interface IFactoryV3 {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IPoolV3 {
    function fee() external view returns (uint24);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
}

/// @dev Minimal LiquidityManager view stub — we only need `factoryV3()` for setV3Pools' canonicality
///      check. The on-chain LiquidityManager is not yet deployed (per audits/internal15/README.md
///      §"On-chain verification"), so we deploy a tiny stand-in that points at the real Uniswap V3
///      factory on mainnet.
contract LMStub {
    address public immutable factoryV3Addr;
    constructor(address _factory) { factoryV3Addr = _factory; }
    function factoryV3() external view returns (address) { return factoryV3Addr; }
    function checkPoolAndGetCenterPrice(address) external pure returns (uint160) { return 0; }
}

/// @dev Fork tests for the L-06 fix against real Uniswap V3 mainnet contracts.
///      Validates that:
///        - setV3Pools accepts a real (USDC, OLAS) pool by the canonical-factory test (when one exists),
///          or accepts a real (WETH, USDC) pool when used as the "secondToken vs OLAS" placeholder.
///        - setV3Pools rejects non-canonical pool addresses (e.g. the WETH/OLAS pool registered for
///          USDC's secondToken slot).
///        - transfer(USDC) on a fresh BBB blocks the sweep when mapV3Pools[USDC] is configured,
///          regardless of the (now-removed) fee-tier degree of freedom.
///
///      Run: forge test -f $FORK_ETH_NODE_URL --mc BuyBackBurnerTransferV3ETH -vvv
contract BuyBackBurnerTransferV3ETHTest is Test {
    // Mainnet (Ethereum) addresses
    address internal constant OLAS         = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH         = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant FACTORY_V3   = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant ROUTER_V3    = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant BRIDGE       = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0; // OLAS_BURNER on mainnet
    address internal constant TREASURY     = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;

    // OLAS / WETH 1.0 % pool — canonical Uniswap V3 pool on mainnet (the only fee tier
    // where an OLAS/WETH V3 pool actually exists on L1 as of fork time).
    address internal constant OLAS_WETH_POOL_1  = 0x18f7B33172F5150949EeF05EbB3b5D4Fe245f391;
    uint24  internal constant OLAS_WETH_FEE_1   = 10000;
    // USDC / WETH 0.3 % pool — used as a "non-canonical" pool when paired with USDC's secondToken slot
    address internal constant USDC_WETH_POOL_03  = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;

    LMStub internal lm;
    BuyBackBurnerUniswap internal bbb;

    function setUp() public {
        // Deploy the LM stub pointing at the real V3 factory
        lm = new LMStub(FACTORY_V3);

        // Deploy fresh BBB proxy
        BuyBackBurnerUniswap impl = new BuyBackBurnerUniswap(address(lm), BRIDGE, TREASURY, ROUTER_V3);
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = address(0);
        accounts[2] = address(0);
        accounts[3] = address(0);
        bytes memory initPayload = abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        bbb = BuyBackBurnerUniswap(payable(address(proxy)));
    }

    function _whitelistPool(address secondToken, address pool) internal {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = secondToken;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        bbb.setV3Pools(secondTokens, pools);
    }

    // -----------------------------------------------------------------------
    // L-06 / I-01: real-factory canonicality check
    // -----------------------------------------------------------------------

    /// @dev Real OLAS/WETH 1.0 % pool — canonical-factory match passes; mapV3Pools is populated.
    function testSetV3Pools_acceptsCanonicalOlasWethPool() public {
        // Sanity — confirm the pool is what we think it is on this fork
        assertEq(uint256(IPoolV3(OLAS_WETH_POOL_1).fee()), uint256(OLAS_WETH_FEE_1));
        // Factory must produce this exact pool address for (WETH, OLAS, 1.0 %)
        assertEq(IFactoryV3(FACTORY_V3).getPool(WETH, OLAS, OLAS_WETH_FEE_1), OLAS_WETH_POOL_1);

        _whitelistPool(WETH, OLAS_WETH_POOL_1);
        assertEq(bbb.mapV3Pools(WETH), OLAS_WETH_POOL_1);
    }

    /// @dev Non-canonical case: try to register the USDC/WETH pool against the USDC secondToken slot.
    ///      Pool's fee() = 3000, but factory.getPool(USDC, OLAS, 3000) ≠ USDC_WETH_POOL_03 — revert.
    ///      Closes the I-01 admin-trust surface (admin can no longer point a wrong pool at a token).
    function testSetV3Pools_revertsOnNonCanonicalPool_realFactory() public {
        // The USDC/WETH 0.3 % pool exists, has fee() = 3000, but is paired with WETH not OLAS
        assertEq(uint256(IPoolV3(USDC_WETH_POOL_03).fee()), uint256(uint24(3000)));

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = USDC;
        address[] memory pools = new address[](1);
        pools[0] = USDC_WETH_POOL_03;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, USDC_WETH_POOL_03));
        bbb.setV3Pools(secondTokens, pools);

        // No state side effects from the failed call
        assertEq(bbb.mapV3Pools(USDC), address(0));
    }

    // -----------------------------------------------------------------------
    // L-06: transfer() blocks V3-eligible secondToken on a real fork
    // -----------------------------------------------------------------------

    /// @dev With the OLAS/WETH 0.3 % pool wired as the WETH V3 pool, transfer(WETH) must revert.
    ///      Closes the original L-06 griefing path (front-run buyBack to divert WETH to treasury).
    function testTransfer_revertsOnV3SecondToken_realFactory() public {
        _whitelistPool(WETH, OLAS_WETH_POOL_1);

        // Fund BBB with some WETH (deal bypasses real WETH allowance/transfer flow)
        deal(WETH, address(bbb), 1 ether);
        assertEq(IERC20Like(WETH).balanceOf(address(bbb)), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, WETH));
        bbb.transfer(WETH);

        // BBB still holds the WETH; treasury did not receive it
        assertEq(IERC20Like(WETH).balanceOf(address(bbb)), 1 ether);
    }

    /// @dev Delisting (pool = address(0)) re-enables the sweep.
    function testTransfer_succeedsAfterDelist_realFactory() public {
        _whitelistPool(WETH, OLAS_WETH_POOL_1);

        deal(WETH, address(bbb), 1 ether);
        // Treasury is a real production address that already holds WETH on mainnet — assert via delta
        uint256 treasuryBefore = IERC20Like(WETH).balanceOf(TREASURY);

        // Delist
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = address(0);
        bbb.setV3Pools(secondTokens, pools);

        bbb.transfer(WETH);
        assertEq(IERC20Like(WETH).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(WETH).balanceOf(TREASURY) - treasuryBefore, 1 ether);
    }

    // -----------------------------------------------------------------------
    // Combined V2 + V3 gate — transfer must block when either side is configured
    // -----------------------------------------------------------------------

    /// @dev If the operator has wired both a V2 oracle AND a V3 pool for the same secondToken,
    ///      transfer() must still block (any path's authorization is enough). This covers the
    ///      "OR" semantics of the combined check.
    function testTransfer_blocksWhenBothV2AndV3Configured() public {
        _whitelistPool(WETH, OLAS_WETH_POOL_1);

        // Wire a V2 oracle for WETH too — sentinel address is fine, transfer() only checks non-zero
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        address[] memory oracles = new address[](1);
        oracles[0] = address(0xBABE);
        bbb.setV2Oracles(tokens, oracles);

        deal(WETH, address(bbb), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, WETH));
        bbb.transfer(WETH);
    }

    /// @dev Transfer must still block on the V2 leg alone (V3 unconfigured) — regression check.
    function testTransfer_blocksV2OracleOnly_realFactory() public {
        // No V3 pool; V2 oracle only
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        address[] memory oracles = new address[](1);
        oracles[0] = address(0xBABE);
        bbb.setV2Oracles(tokens, oracles);

        deal(USDC, address(bbb), 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, USDC));
        bbb.transfer(USDC);
    }

    /// @dev Transfer must still allow sweeping a token that's neither V2-mapped nor V3-paired.
    ///      Sanity that the gate hasn't accidentally become deny-by-default for arbitrary tokens.
    function testTransfer_allowsTrulyStrayToken_realFactory() public {
        _whitelistPool(WETH, OLAS_WETH_POOL_1);

        // USDC is not in either path on this BBB
        deal(USDC, address(bbb), 1_000e6);
        uint256 treasuryBefore = IERC20Like(USDC).balanceOf(TREASURY);

        bbb.transfer(USDC);
        assertEq(IERC20Like(USDC).balanceOf(address(bbb)), 0);
        assertEq(IERC20Like(USDC).balanceOf(TREASURY) - treasuryBefore, 1_000e6);
    }

    // -----------------------------------------------------------------------
    // Setter accepts/rejects edge cases against real factory
    // -----------------------------------------------------------------------

    /// @dev Cannot configure a V3 pool for OLAS itself (operator misconfiguration guard).
    function testSetV3Pools_revertsWhenSecondTokenIsOlas_realFactory() public {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = OLAS;
        address[] memory pools = new address[](1);
        pools[0] = OLAS_WETH_POOL_1;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, OLAS));
        bbb.setV3Pools(secondTokens, pools);
    }

    /// @dev Trying to whitelist OLAS/WETH at fee=3000 must fail — that pool doesn't exist on mainnet,
    ///      so the factory returns address(0) but the operator tried to register a non-zero address.
    function testSetV3Pools_revertsForNonexistentFeeTier_realFactory() public {
        // Verify the pool truly doesn't exist on Uniswap V3 mainnet today
        assertEq(IFactoryV3(FACTORY_V3).getPool(WETH, OLAS, uint24(3000)), address(0));

        // Attempt to register the OLAS/WETH 1.0% pool while claiming fee=3000 — pool's fee() = 10000,
        // setter reads fee() = 10000, factory.getPool(WETH, OLAS, 10000) = OLAS_WETH_POOL_1 (matches),
        // so this actually passes! The operator's "claimed fee" is implicit in the pool.fee() reader,
        // not in any caller-supplied param. Asserting acceptance is the right behavior.
        _whitelistPool(WETH, OLAS_WETH_POOL_1);
        assertEq(bbb.mapV3Pools(WETH), OLAS_WETH_POOL_1);

        // Now attempt to whitelist the USDC/WETH pool against WETH's slot. This pool's fee() = 3000,
        // factory.getPool(WETH, OLAS, 3000) returns address(0), so the canonicality check rejects.
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = USDC_WETH_POOL_03;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, USDC_WETH_POOL_03));
        bbb.setV3Pools(secondTokens, pools);
    }
}
