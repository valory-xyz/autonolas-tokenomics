// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {
    BuyBackBurner,
    UnauthorizedToken,
    UnauthorizedPool,
    ZeroAddress,
    OwnerOnly,
    WrongArrayLength
} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Minimal V3 pool stub exposing the immutable fee() reader the new fix uses.
contract MockV3PoolWithFee {
    uint24 public immutable fee;
    constructor(uint24 _fee) { fee = _fee; }
}

/// @dev Mock factory whose getPool() can be programmed per (tokenA, tokenB, fee) triple. Used to
///      simulate canonical vs non-canonical pool addresses for the setV3Pools canonicality check.
contract MockFactory {
    mapping(bytes32 => address) internal _pools;
    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _pools[_key(tokenA, tokenB, fee)] = pool;
    }
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return _pools[_key(tokenA, tokenB, fee)];
    }
    function _key(address a, address b, uint24 fee) internal pure returns (bytes32) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(t0, t1, fee));
    }
}

contract MockLM {
    address public immutable factoryV3Addr;
    constructor(address _factory) { factoryV3Addr = _factory; }
    function factoryV3() external view returns (address) { return factoryV3Addr; }
    function checkPoolAndGetCenterPrice(address) external pure returns (uint160) { return 0; }
}

/// @dev Unit tests for the L-06 fix:
///      - mapV3Pools is now keyed by secondToken (mirrors mapV2Oracles).
///      - transfer(address) blocks tokens whose secondToken is configured for either V2 or V3.
///      - setV3Pools verifies factory-pool canonicality, closing I-01 in code.
///
///      Run: forge test --mc BuyBackBurnerTransferV3 -vvv
contract BuyBackBurnerTransferV3Test is Test {
    address internal constant BRIDGE2BURNER = address(0xB10B);
    address internal constant TREASURY      = address(0x7157);
    address internal constant SWAP_ROUTER   = address(0xF00D);
    uint24  internal constant FEE_3000      = 3000;
    uint24  internal constant FEE_500       = 500;

    MockERC20 internal olas;
    MockERC20 internal usdc;
    MockERC20 internal weth;
    MockFactory internal factory;
    MockLM internal lm;
    BuyBackBurnerUniswap internal bbb;

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS");
        usdc = new MockERC20("USDC", "USDC");
        weth = new MockERC20("WETH", "WETH");
        factory = new MockFactory();
        lm = new MockLM(address(factory));
        bbb = _deployProxy();
    }

    function _deployProxy() internal returns (BuyBackBurnerUniswap) {
        BuyBackBurnerUniswap impl = new BuyBackBurnerUniswap(address(lm), BRIDGE2BURNER, TREASURY, SWAP_ROUTER);
        address[] memory accounts = new address[](4);
        accounts[0] = address(olas);
        accounts[1] = address(0);
        accounts[2] = address(0);
        accounts[3] = address(0);
        bytes memory initPayload = abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        return BuyBackBurnerUniswap(payable(address(proxy)));
    }

    /// @dev Whitelist a (secondToken, pool) entry — wires the factory mock so canonicality check passes.
    function _wireV3(address secondToken, uint24 fee) internal returns (address pool) {
        pool = address(new MockV3PoolWithFee(fee));
        factory.setPool(secondToken, address(olas), fee, pool);

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = secondToken;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        bbb.setV3Pools(secondTokens, pools);
    }

    // -----------------------------------------------------------------------
    // L-06: transfer() blocks V3-eligible secondTokens
    // -----------------------------------------------------------------------

    function test_transfer_revertsOnV3SecondToken() public {
        _wireV3(address(usdc), FEE_3000);

        usdc.mint(address(bbb), 1_000e18);

        // Even though USDC has no V2 oracle, the V3-side check blocks the sweep
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, address(usdc)));
        bbb.transfer(address(usdc));

        assertEq(usdc.balanceOf(TREASURY), 0);
        assertEq(usdc.balanceOf(address(bbb)), 1_000e18);
    }

    function test_transfer_succeedsAfterV3PoolDelisted() public {
        _wireV3(address(usdc), FEE_3000);

        usdc.mint(address(bbb), 1_000e18);

        // Delist the V3 pool — pool == address(0) clears the entry
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = address(0);
        bbb.setV3Pools(secondTokens, pools);
        assertEq(bbb.mapV3Pools(address(usdc)), address(0));

        // Now transfer() succeeds
        bbb.transfer(address(usdc));
        assertEq(usdc.balanceOf(TREASURY), 1_000e18);
        assertEq(usdc.balanceOf(address(bbb)), 0);
    }

    function test_transfer_blocksV3SecondToken_evenWhenSweptAtAnyFeeTier() public {
        // The L-06 attack vector — caller picks a non-whitelisted fee tier — is no longer exploitable
        // because transfer() doesn't take a fee tier; the V3 check is keyed by secondToken alone.
        _wireV3(address(usdc), FEE_3000);
        usdc.mint(address(bbb), 1_000e18);

        // The attacker has no fee-tier degree of freedom — transfer reverts unconditionally
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, address(usdc)));
        bbb.transfer(address(usdc));
    }

    function test_transfer_succeedsForUnrelatedToken() public {
        _wireV3(address(usdc), FEE_3000);

        // WETH is not in any swap path — must remain sweepable
        weth.mint(address(bbb), 5e18);
        bbb.transfer(address(weth));

        assertEq(weth.balanceOf(TREASURY), 5e18);
    }

    function test_transfer_stillBlocksV2OracleToken() public {
        // The V2 leg of the combined check must still hold
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        address[] memory oracles = new address[](1);
        oracles[0] = address(0xBABE);
        bbb.setV2Oracles(tokens, oracles);

        usdc.mint(address(bbb), 100e18);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, address(usdc)));
        bbb.transfer(address(usdc));
    }

    // -----------------------------------------------------------------------
    // I-01: setV3Pools verifies factory ancestry
    // -----------------------------------------------------------------------

    function test_setV3Pools_revertsOnNonCanonicalPool() public {
        // Pool's fee() = 3000 but factory.getPool(USDC, OLAS, 3000) returns a DIFFERENT address
        address fakePool = address(new MockV3PoolWithFee(FEE_3000));
        address realPool = address(new MockV3PoolWithFee(FEE_3000));
        factory.setPool(address(usdc), address(olas), FEE_3000, realPool); // canonical pool != fakePool

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = fakePool;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, fakePool));
        bbb.setV3Pools(secondTokens, pools);

        // No state side effects from the failed call
        assertEq(bbb.mapV3Pools(address(usdc)), address(0));
    }

    function test_setV3Pools_revertsWhenFactoryReturnsZero() public {
        // Factory has no pool registered for (USDC, OLAS, 3000) → returns address(0). Operator-supplied
        // pool address is non-zero, so the canonicality check fails.
        address pool = address(new MockV3PoolWithFee(FEE_3000));

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = pool;

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, pool));
        bbb.setV3Pools(secondTokens, pools);
    }

    function test_setV3Pools_acceptsCanonicalPool() public {
        address pool = address(new MockV3PoolWithFee(FEE_3000));
        factory.setPool(address(usdc), address(olas), FEE_3000, pool);

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = pool;

        bbb.setV3Pools(secondTokens, pools);
        assertEq(bbb.mapV3Pools(address(usdc)), pool);
    }

    function test_setV3Pools_zeroPoolDelistsWithoutCanonicalityCheck() public {
        // Configure first
        _wireV3(address(usdc), FEE_3000);

        // Delist by passing pool=0 — must not require any factory lookup
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = address(0);

        bbb.setV3Pools(secondTokens, pools);
        assertEq(bbb.mapV3Pools(address(usdc)), address(0));
    }

    function test_setV3Pools_revertsOnZeroSecondToken() public {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(0);
        address[] memory pools = new address[](1);
        pools[0] = address(0xBEEF);

        vm.expectRevert(ZeroAddress.selector);
        bbb.setV3Pools(secondTokens, pools);
    }

    function test_setV3Pools_revertsWhenSecondTokenIsOLAS() public {
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(olas);
        address[] memory pools = new address[](1);
        pools[0] = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedToken.selector, address(olas)));
        bbb.setV3Pools(secondTokens, pools);
    }

    function test_setV3Pools_revertsOnArrayMismatch() public {
        address[] memory secondTokens = new address[](2);
        secondTokens[0] = address(usdc);
        secondTokens[1] = address(weth);
        address[] memory pools = new address[](1);
        pools[0] = address(0xBEEF);

        vm.expectRevert(WrongArrayLength.selector);
        bbb.setV3Pools(secondTokens, pools);
    }

    function test_setV3Pools_emitsEvent() public {
        address pool = address(new MockV3PoolWithFee(FEE_3000));
        factory.setPool(address(usdc), address(olas), FEE_3000, pool);

        address[] memory secondTokens = new address[](1);
        secondTokens[0] = address(usdc);
        address[] memory pools = new address[](1);
        pools[0] = pool;

        vm.recordLogs();
        bbb.setV3Pools(secondTokens, pools);
        // Sanity — log captured (full event-payload equality is overkill here; we just confirm it fires)
        assertGt(vm.getRecordedLogs().length, 0);
    }
}
