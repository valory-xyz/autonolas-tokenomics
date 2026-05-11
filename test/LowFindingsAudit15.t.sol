// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    BuyBackBurner, DeadlineExpired, ReentrancyGuard, ZeroValue
} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";
import {LiquidityManagerCore, Overflow} from "../contracts/pol/LiquidityManagerCore.sol";

/// @dev Minimal concrete LiquidityManagerCore for unit-testing changeMaxSlippage.
///      All abstract virtuals are stubbed.
contract TestLiquidityManagerCoreMaxSlippage is LiquidityManagerCore {
    constructor(address _positionManager, address _neighborhoodScanner)
        LiquidityManagerCore(
            address(1), // _olas
            address(2), // _treasury
            _positionManager,
            _neighborhoodScanner,
            1 // _observationCardinality
        )
    {}

    function _burn(uint256) internal override {}

    function _checkTokensAndRemoveLiquidityV2(address[] memory, bytes32)
        internal
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
    }

    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing) internal pure override returns (int24) {
        return feeTierOrTickSpacing;
    }

    function _getV3Pool(address[] memory, int24) internal pure override returns (address) {
        return address(0);
    }

    function _mintV3(address[] memory, uint256[] memory, uint256[] memory, int24[] memory, int24, uint160)
        internal
        override
        returns (uint256, uint128, uint256[] memory)
    {
        uint256[] memory a = new uint256[](2);
        return (0, 0, a);
    }
}

/// @dev Minimal mock exposing factory() for the constructor's positionManagerV3.factory() call.
contract MockFactory {
    address public factoryAddr;

    constructor(address _factory) {
        factoryAddr = _factory;
    }

    function factory() external view returns (address) {
        return factoryAddr;
    }
}

/// @dev Unit tests for Internal Audit 15 Low findings.
///      L-01: buyBack(...) honours the deadline parameter.
///      L-05: LiquidityManagerCore.changeMaxSlippage reverts when newMaxSlippage > MAX_BPS.
contract LowFindingsAudit15 is Test {
    // ------------------------------------------------------------------
    // L-01 — buyBack deadline
    // ------------------------------------------------------------------

    BuyBackBurnerUniswap internal buyBackBurner;

    // Dummy non-zero addresses — deadline check fires before any of these are touched.
    address internal constant DUMMY_LIQUIDITY_MANAGER = address(0xa1);
    address internal constant DUMMY_BRIDGE2BURNER = address(0xa2);
    address internal constant DUMMY_TREASURY = address(0xa3);
    address internal constant DUMMY_SWAP_ROUTER = address(0xa4);
    address internal constant DUMMY_OLAS = address(0xb1);
    address internal constant DUMMY_NATIVE = address(0xb2);
    address internal constant DUMMY_ORACLE = address(0xb3);
    address internal constant DUMMY_ROUTER = address(0xb4);

    function _deployBuyBackBurner() internal {
        BuyBackBurnerUniswap impl = new BuyBackBurnerUniswap(
            DUMMY_LIQUIDITY_MANAGER, DUMMY_BRIDGE2BURNER, DUMMY_TREASURY, DUMMY_SWAP_ROUTER
        );

        address[] memory accounts = new address[](4);
        accounts[0] = DUMMY_OLAS;
        accounts[1] = DUMMY_NATIVE;
        accounts[2] = DUMMY_ORACLE;
        accounts[3] = DUMMY_ROUTER;

        bytes memory initPayload = abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));

        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        buyBackBurner = BuyBackBurnerUniswap(payable(address(proxy)));
    }

    function test_L01_buyBack_V2_revertsWhenDeadlinePassed() public {
        _deployBuyBackBurner();

        // Pin block time so we can reason about deadline
        vm.warp(10_000);

        // deadline in the past → must revert with DeadlineExpired
        uint256 pastDeadline = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(DeadlineExpired.selector, pastDeadline, block.timestamp));
        buyBackBurner.buyBack(DUMMY_NATIVE, 1 ether, pastDeadline);
    }

    function test_L01_buyBack_V2_deadlineZeroOptsOut() public {
        _deployBuyBackBurner();

        vm.warp(10_000);

        // Stub balanceOf(address(this)) to zero so the path proceeds past the deadline guard
        vm.mockCall(
            DUMMY_NATIVE,
            abi.encodeWithSignature("balanceOf(address)", address(buyBackBurner)),
            abi.encode(uint256(0))
        );

        // deadline == 0 → check is skipped; call proceeds past the deadline guard and fails
        // later on the ZeroValue balance check, NOT on DeadlineExpired.
        vm.expectRevert(ZeroValue.selector);
        buyBackBurner.buyBack(DUMMY_NATIVE, 0, 0);
    }

    function test_L01_buyBack_V2_deadlineEqualsNowSucceedsDeadlineCheck() public {
        _deployBuyBackBurner();

        vm.warp(10_000);

        // Stub balanceOf(address(this)) to zero so the path proceeds past the deadline guard
        vm.mockCall(
            DUMMY_NATIVE,
            abi.encodeWithSignature("balanceOf(address)", address(buyBackBurner)),
            abi.encode(uint256(0))
        );

        // deadline == block.timestamp → not expired; call proceeds past the guard.
        // Test asserts the revert is NOT DeadlineExpired (fails instead on ZeroValue balance).
        vm.expectRevert(ZeroValue.selector);
        buyBackBurner.buyBack(DUMMY_NATIVE, 0, block.timestamp);
    }

    // The former V3-specific deadline tests were folded into the V2-shape tests above when the V3
    // 4-arg `buyBack(address, uint256, int24, uint256)` overload was removed (auto-routing collapsed
    // it into the unified `buyBack(address, uint256, uint256)`). Both V2 and V3 paths now share the
    // same deadline guard at the top of buyBack — covered by the two tests above.

    // ------------------------------------------------------------------
    // L-05 — changeMaxSlippage upper bound
    // ------------------------------------------------------------------

    TestLiquidityManagerCoreMaxSlippage internal lm;

    function _deployLM() internal {
        MockFactory pm = new MockFactory(address(0xf));
        address scanner = address(new MockFactory(address(0)));
        lm = new TestLiquidityManagerCoreMaxSlippage(address(pm), scanner);
        // initialize with a valid slippage so owner is set and subsequent calls are authorised
        lm.initialize(500);
    }

    function test_L05_changeMaxSlippage_revertsAboveMaxBps() public {
        _deployLM();

        uint16 tooHigh = 10_001;
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, tooHigh, uint256(lm.MAX_BPS())));
        lm.changeMaxSlippage(tooHigh);
    }

    function test_L05_changeMaxSlippage_acceptsExactMaxBps() public {
        _deployLM();

        lm.changeMaxSlippage(10_000);
        assertEq(lm.maxSlippage(), 10_000, "maxSlippage should be set to MAX_BPS");
    }

    function test_L05_changeMaxSlippage_revertsZero() public {
        _deployLM();

        vm.expectRevert(ZeroValue.selector);
        lm.changeMaxSlippage(0);
    }

    function test_L05_changeMaxSlippage_acceptsWithinRange() public {
        _deployLM();

        lm.changeMaxSlippage(750);
        assertEq(lm.maxSlippage(), 750);
    }
}
