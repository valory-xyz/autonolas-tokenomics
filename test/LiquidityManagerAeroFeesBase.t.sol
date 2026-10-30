// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup, ISlipstream, INPMMintSlipstream, IProxy} from "./LiquidityManagerBase.t.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {FullMath} from "../contracts/libraries/FullMath.sol";
import {ZeroValue} from "../contracts/pol/LiquidityManagerCore.sol";

interface IAeroFeePool {
    struct SwapParams {
        address caller;
        address recipient;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        bytes data;
        uint160 sqrtPriceX96;
        int24 tick;
    }
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, bool);
    function liquidity() external view returns (uint128);
    function stakedLiquidity() external view returns (uint128);
    function unstakedFee() external view returns (uint24);
    function beforeSwapFee(SwapParams calldata params) external view returns (uint24);
    function feeGrowthGlobal0X128() external view returns (uint256);
    function feeGrowthGlobal1X128() external view returns (uint256);
    function getFeeGrowthInside(int24 lower, int24 upper) external view returns (uint256, uint256);
    function gaugeFees() external view returns (uint128, uint128);
}

interface IAeroFeeNPM {
    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    function positions(uint256 tokenId) external view returns (Position memory);
}

interface IAeroFeeFactory {
    function getPoolSwapHook(address pool) external view returns (address);
    function swapFeeManager() external view returns (address);
    function unstakedFeeManager() external view returns (address);
    function unstakedFeeModule() external view returns (address);
    function defaultUnstakedFee() external view returns (uint24);
    function setDefaultUnstakedFee(uint24 fee) external;
    function voter() external view returns (address);
    function discountRegistry() external view returns (address);
}

interface IAeroFeeVoter {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function isActivated(address gauge) external view returns (bool);
}

interface IAeroGovernanceCreation {
    function createGauge(address target, address gaugeFactory, bytes calldata factoryData, bool activate)
        external returns (address);
}

interface IAeroDynamicHook {
    function setCustomFee(address pool, uint24 fee) external;
    function setDefaultScalingFactor(uint256 factor) external;
    function setInitialFee(address pool, uint24 fee) external;
    function disableInitialFee(address pool) external;
    function blockFee(address pool, uint256 height) external view returns (uint256);
    function mevTaxModule() external view returns (address);
    function defaultScalingFactor() external view returns (uint256);
    function defaultFeeCap() external view returns (uint256);
    function setFeeCap(address pool, uint24 cap) external;
    function setScalingFactor(address pool, uint64 factor) external;
}

interface IAeroDiscount {
    function owner() external view returns (address);
    function registerPoolDiscount(address account, address pool, uint24 discount) external;
    function getDiscount(address pool, address caller) external view returns (uint24);
}

interface IAeroMevTax {
    function owner() external view returns (address);
    function setMultiplier(uint64 value) external;
    function setMinThreshold(uint96 value) external;
    function setBaseFeeFactor(uint96 value) external;
    function priorityFeeMultiplier() external view returns (uint64);
    function minThreshold() external view returns (uint96);
    function baseFeeFactor() external view returns (uint96);
    function getMevTax() external view returns (uint24, bool);
}

/// @dev Exact balance and fee-growth checks on Base block 53153049. No fee/rounding tolerances.
///      High-fee cases change fee-manager settings ONLY on the fork; they are stress scenarios.
contract LiquidityManagerAeroFeesBaseTest is BaseSetup {
    address internal GOVERNANCE_CREATION_MODULE = 0xD035217F89511eAE97daC11bF9604406EF431D17;
    uint256 private constant Q96 = 1 << 96;
    uint256 private constant Q128 = 1 << 128;
    uint256 private constant PIPS = 1_000_000;

    struct Facts {
        uint160 sqrtP;
        int24 tick;
        uint128 liquidity;
        uint256 growth0;
        uint256 growth1;
        uint128 gauge0;
        uint128 gauge1;
        uint256 balance0;
        uint256 balance1;
    }

    struct FeeTotals {
        uint256 gross0;
        uint256 gross1;
        uint256 deduction0;
        uint256 deduction1;
        uint256 expected0;
        uint256 expected1;
    }

    struct RecipientBalances {
        uint256 treasury0;
        uint256 treasury1;
        uint256 bridge0;
        uint256 bridge1;
        uint256 pool0;
        uint256 pool1;
    }

    function _configureSlipstream() internal virtual override {
        assertEq(block.chainid, 8453);
        ROUTER_V3 = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;
        FACTORY_V3 = 0x9CB220581b91b0C83223012FE69688b92aD07a76;
        POSITION_MANAGER_V3 = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
    }

    function _openPosition() private returns (IAeroFeePool pool, uint256 id) {
        int24[] memory shifts = new int24[](2);
        shifts[0] = -27000;
        shifts[1] = 17000;
        // Fixed test capital: the historical V2 holder has only a residual balance at this block.
        deal(WETH, address(liquidityManager), 1 ether);
        deal(OLAS, address(liquidityManager), 40_000 ether);
        (id,,) = liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, shifts, 0, true);
        pool = IAeroFeePool(ISlipstream(FACTORY_V3).getPool(WETH, OLAS, TICK_SPACING));
        IAeroFeeNPM.Position memory position = IAeroFeeNPM(POSITION_MANAGER_V3).positions(id);
        assertEq(position.token0, WETH);
        assertEq(position.token1, OLAS);
        assertGt(position.liquidity, 0);
        assertEq(pool.liquidity(), position.liquidity, "fixture must have one active LP");
        assertEq(pool.stakedLiquidity(), 0, "LM is unstaked");
        vm.txGasPrice(block.basefee); // No priority-fee MEV tax in these accounting scenarios.
    }

    function _facts(IAeroFeePool pool) private view returns (Facts memory f) {
        (f.sqrtP, f.tick,,,,) = pool.slot0();
        f.liquidity = pool.liquidity();
        f.growth0 = pool.feeGrowthGlobal0X128();
        f.growth1 = pool.feeGrowthGlobal1X128();
        (f.gauge0, f.gauge1) = pool.gaugeFees();
        f.balance0 = IToken(WETH).balanceOf(address(pool));
        f.balance1 = IToken(OLAS).balanceOf(address(pool));
    }

    function _fee(IAeroFeePool pool, bool zeroForOne, uint256 amount) private view returns (uint24) {
        (uint160 sqrtP, int24 tick,,,,) = pool.slot0();
        return pool.beforeSwapFee(IAeroFeePool.SwapParams({
            caller: ROUTER_V3, recipient: address(this), zeroForOne: zeroForOne,
            amountSpecified: int256(amount), sqrtPriceLimitX96: zeroForOne ? 4295128740 :
                1461446703485210103287273052203988822378723970341,
            data: "", sqrtPriceX96: sqrtP, tick: tick
        }));
    }

    function _word(int24 tick) private pure returns (int24) {
        int24 compressed = tick / TICK_SPACING;
        if (tick < 0 && tick % TICK_SPACING != 0) --compressed;
        return compressed >> 8;
    }

    function _expectedSqrt(Facts memory f, uint256 inputBudget, bool zeroForOne) private pure returns (uint256) {
        if (zeroForOne) {
            uint256 numerator = uint256(f.liquidity) << 96;
            return FullMath.mulDivRoundingUp(numerator, f.sqrtP, numerator + inputBudget * f.sqrtP);
        }
        return uint256(f.sqrtP) + FullMath.mulDiv(inputBudget, Q96, f.liquidity);
    }

    /// @dev Derives fee paid from exact token movement and the AMM price/liquidity identity.
    ///      Restricts each probe to one bitmap word and constant active liquidity, avoiding
    ///      a duplicated multi-step swap simulator or an approximate fee calculation.
    function _swapAndReconcile(IAeroFeePool pool, bool zeroForOne, uint256 amount)
        private returns (uint256 grossFee, uint256 gaugeDeduction)
    {
        Facts memory before_ = _facts(pool);
        uint24 feePips = _fee(pool, zeroForOne, amount);
        uint24 unstakedPips = pool.unstakedFee();
        address input = zeroForOne ? WETH : OLAS;
        address output = zeroForOne ? OLAS : WETH;
        uint256 out = _swap(input, output, amount);
        Facts memory after_ = _facts(pool);
        assertEq(_word(before_.tick), _word(after_.tick), "probe crossed a bitmap word");
        assertEq(before_.liquidity, after_.liquidity);
        assertEq(pool.stakedLiquidity(), 0);

        uint160 lower = zeroForOne ? after_.sqrtP : before_.sqrtP;
        uint160 upper = zeroForOne ? before_.sqrtP : after_.sqrtP;
        uint256 principalIn;
        uint256 principalOut;
        if (zeroForOne) {
            principalIn = FullMath.mulDivRoundingUp(uint256(before_.liquidity) << 96, upper - lower, upper);
            principalIn = (principalIn + lower - 1) / lower;
            principalOut = FullMath.mulDiv(before_.liquidity, upper - lower, Q96);
            assertEq(after_.balance0 - before_.balance0, amount);
            assertEq(before_.balance1 - after_.balance1, out);
        } else {
            principalIn = FullMath.mulDivRoundingUp(before_.liquidity, upper - lower, Q96);
            principalOut = FullMath.mulDiv(uint256(before_.liquidity) << 96, upper - lower, upper) / lower;
            assertEq(after_.balance1 - before_.balance1, amount);
            assertEq(before_.balance0 - after_.balance0, out);
        }
        // The deployed dynamic hook has no post-swap output fee in these scenarios.
        assertEq(out, principalOut, "unexpected output-side deduction");
        uint256 inputBudget = FullMath.mulDiv(amount, PIPS - feePips, PIPS);
        assertEq(after_.sqrtP, _expectedSqrt(before_, inputBudget, zeroForOne), "fee-adjusted price movement");
        assertLe(principalIn, inputBudget);
        grossFee = amount - principalIn;
        gaugeDeduction = FullMath.mulDivRoundingUp(grossFee, unstakedPips, PIPS);
        uint256 lpFee = grossFee - gaugeDeduction;
        uint256 growthDelta = FullMath.mulDiv(lpFee, Q128, before_.liquidity);
        if (zeroForOne) {
            assertEq(after_.gauge0 - before_.gauge0, gaugeDeduction);
            assertEq(after_.gauge1, before_.gauge1);
            assertEq(after_.growth0 - before_.growth0, growthDelta);
            assertEq(after_.growth1, before_.growth1);
        } else {
            assertEq(after_.gauge1 - before_.gauge1, gaugeDeduction);
            assertEq(after_.gauge0, before_.gauge0);
            assertEq(after_.growth1 - before_.growth1, growthDelta);
            assertEq(after_.growth0, before_.growth0);
        }
        emit log_named_uint(zeroForOne ? "WETH swap fee pips" : "OLAS swap fee pips", feePips);
        emit log_named_uint(zeroForOne ? "WETH gross fee atoms" : "OLAS gross fee atoms", grossFee);
        emit log_named_uint(zeroForOne ? "WETH gauge deduction atoms" : "OLAS gauge deduction atoms", gaugeDeduction);
        emit log_named_uint("Unstaked deduction pips", unstakedPips);
    }

    function _enableDynamicAndMovePrice(IAeroFeePool pool) private {
        IAeroFeeFactory factory = IAeroFeeFactory(FACTORY_V3);
        IAeroDynamicHook hook = IAeroDynamicHook(factory.getPoolSwapHook(address(pool)));
        emit log_named_uint("Pinned default scaling factor", hook.defaultScalingFactor());
        emit log_named_uint("Pinned default fee cap pips", hook.defaultFeeCap());
        vm.startPrank(factory.swapFeeManager());
        hook.setFeeCap(address(pool), 50_000);
        hook.setScalingFactor(address(pool), 1_000_000_000);
        vm.stopPrank();
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        Facts memory f = _facts(pool);
        // Exact fixture input, expressed as a fraction of the virtual WETH reserve.
        _swap(WETH, OLAS, FullMath.mulDiv(f.liquidity, Q96, f.sqrtP) / 2000);
        liquidityManager.checkPoolAndGetCenterPrice(address(pool));
    }

    function _enableUnstakedDeduction(IAeroFeePool pool) private {
        IAeroFeeFactory factory = IAeroFeeFactory(FACTORY_V3);
        IAeroFeeVoter voter = IAeroFeeVoter(factory.voter());
        address governor = voter.getRoleMember(keccak256("GOVERNANCE_ROLE"), 0);
        vm.prank(governor);
        address gauge = IAeroGovernanceCreation(GOVERNANCE_CREATION_MODULE).createGauge(
            address(pool), 0xf437f62053ACB121665b8fDBfeA8F214FB8E589d, "", true);
        assertTrue(voter.isActivated(gauge));
        assertEq(factory.unstakedFeeModule(), address(0));
        emit log_named_uint("Pinned default unstaked deduction pips", factory.defaultUnstakedFee());
        vm.prank(factory.unstakedFeeManager());
        factory.setDefaultUnstakedFee(333_333);
        assertEq(pool.unstakedFee(), 333_333);
    }

    function _reconcileFees(bool reverse, bool elevated, bool deduction) private {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        if (deduction) _enableUnstakedDeduction(pool);
        if (elevated) {
            _enableDynamicAndMovePrice(pool);
            liquidityManager.collectFees(TOKENS, TICK_SPACING); // settle the price-move swap separately
            uint24 cachedFee = _fee(pool, true, 1e10);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            assertGt(_fee(pool, true, 1e10), cachedFee, "dynamic fee did not increase");
        }
        _reconcilePosition(pool, id, reverse);
    }

    function _reconcilePosition(IAeroFeePool pool, uint256 id, bool reverse) private {
        IAeroFeeNPM.Position memory p = IAeroFeeNPM(POSITION_MANAGER_V3).positions(id);
        FeeTotals memory fees;
        (fees.gross0, fees.deduction0) = _swapAndReconcile(pool, true, 1e10 + 123);
        (fees.gross1, fees.deduction1) = _swapAndReconcile(pool, false, 1e14 + 321);
        if (pool.unstakedFee() > 0) {
            assertGt(fees.deduction0, 0);
            assertGt(fees.deduction1, 0);
        }
        (uint256 inside0, uint256 inside1) = pool.getFeeGrowthInside(p.tickLower, p.tickUpper);
        fees.expected0 = p.tokensOwed0 + FullMath.mulDiv(inside0 - p.feeGrowthInside0LastX128, p.liquidity, Q128);
        fees.expected1 = p.tokensOwed1 + FullMath.mulDiv(inside1 - p.feeGrowthInside1LastX128, p.liquidity, Q128);
        assertGt(fees.expected0, 0);
        assertGt(fees.expected1, 0);
        // Derive collectable amounts independently from swap fees and both integer floors.
        assertEq(fees.expected0, FullMath.mulDiv(
            FullMath.mulDiv(fees.gross0 - fees.deduction0, Q128, p.liquidity), p.liquidity, Q128));
        assertEq(fees.expected1, FullMath.mulDiv(
            FullMath.mulDiv(fees.gross1 - fees.deduction1, Q128, p.liquidity), p.liquidity, Q128));
        _collectAndReconcile(pool, id, p.liquidity, reverse, fees);
    }

    function _collectAndReconcile(IAeroFeePool pool, uint256 id, uint128 positionLiquidity,
        bool reverse, FeeTotals memory fees) private {
        // Both tokens are staged before permissionless fee collection; neither may be swept.
        deal(WETH, address(liquidityManager), 7 ether);
        deal(OLAS, address(liquidityManager), 11 ether);
        RecipientBalances memory before_ = RecipientBalances({
            treasury0: IToken(WETH).balanceOf(TIMELOCK),
            treasury1: IToken(OLAS).balanceOf(TIMELOCK),
            bridge0: IToken(WETH).balanceOf(address(bridge2Burner)),
            bridge1: IToken(OLAS).balanceOf(address(bridge2Burner)),
            pool0: IToken(WETH).balanceOf(address(pool)),
            pool1: IToken(OLAS).balanceOf(address(pool))
        });
        address[] memory tokens = new address[](2);
        tokens[0] = reverse ? OLAS : WETH;
        tokens[1] = reverse ? WETH : OLAS;
        vm.prank(dev); // collectFees is permissionless, not an owner withdrawal.
        uint256[] memory collected = liquidityManager.collectFees(tokens, TICK_SPACING);
        assertEq(collected[reverse ? 1 : 0], fees.expected0);
        assertEq(collected[reverse ? 0 : 1], fees.expected1);
        assertEq(IToken(WETH).balanceOf(TIMELOCK) - before_.treasury0, fees.expected0);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)) - before_.bridge1, fees.expected1);
        assertEq(IToken(OLAS).balanceOf(TIMELOCK), before_.treasury1);
        assertEq(IToken(WETH).balanceOf(address(bridge2Burner)), before_.bridge0);
        assertEq(before_.pool0 - IToken(WETH).balanceOf(address(pool)), fees.expected0);
        assertEq(before_.pool1 - IToken(OLAS).balanceOf(address(pool)), fees.expected1);
        assertEq(IToken(WETH).balanceOf(address(liquidityManager)), 7 ether);
        assertEq(IToken(OLAS).balanceOf(address(liquidityManager)), 11 ether);
        assertEq(IAeroFeeNPM(POSITION_MANAGER_V3).positions(id).liquidity, positionLiquidity);
        // Account explicitly for integer fee-growth/position rounding; no tolerance is used.
        emit log_named_uint("Collected WETH atoms", fees.expected0);
        emit log_named_uint("Collected OLAS atoms", fees.expected1);
        emit log_named_uint("WETH LP rounding dust atoms", fees.gross0 - fees.deduction0 - fees.expected0);
        emit log_named_uint("OLAS LP rounding dust atoms", fees.gross1 - fees.deduction1 - fees.expected1);
        vm.expectRevert(ZeroValue.selector);
        liquidityManager.collectFees(tokens, TICK_SPACING);
    }

    function _hook(IAeroFeePool pool) private view returns (IAeroDynamicHook) {
        return IAeroDynamicHook(IAeroFeeFactory(FACTORY_V3).getPoolSwapHook(address(pool)));
    }

    function _policyMaintenance(IAeroFeePool pool, uint256 id) private {
        _reconcilePosition(pool, id, false);
        _policyBuyback(pool);
        uint128 previous = IAeroFeeNPM(POSITION_MANAGER_V3).positions(id).liquidity;
        deal(WETH, address(liquidityManager), 1 ether);
        deal(OLAS, address(liquidityManager), 40_000 ether);
        (uint256 sameId, uint256 added,) = liquidityManager.increaseLiquidity(TOKENS, TICK_SPACING, 0);
        assertEq(sameId, id);
        assertGt(added, 0);
        assertEq(IAeroFeeNPM(POSITION_MANAGER_V3).positions(id).liquidity, previous + added);
        (, uint128 removed,) = liquidityManager.decreaseLiquidity(TOKENS, TICK_SPACING, 1000, 0);
        assertEq(removed, (uint256(previous) + added) / 10);
        int24[] memory shifts = new int24[](2);
        shifts[0] = -27000;
        shifts[1] = 17000;
        (uint256 nextId, uint256 nextLiq,) = liquidityManager.changeRanges(TOKENS, TICK_SPACING, shifts, true);
        assertTrue(nextId != id);
        assertGt(nextLiq, 0);
        (, removed,) = liquidityManager.decreaseLiquidity(TOKENS, TICK_SPACING, MAX_BPS, 0);
        assertEq(removed, nextLiq);
        assertEq(IAeroFeeNPM(POSITION_MANAGER_V3).positions(nextId).liquidity, 0);
        assertEq(pool.liquidity(), 0);
    }

    function _policyBuyback(IAeroFeePool pool) private {
        uint256 amount = 1e10;
        uint256 snapshot = vm.snapshotState();
        uint256 expected = _swap(WETH, OLAS, amount);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        assertLt(expected, _twapQuote(pool, amount));
        deal(WETH, BUY_BACK_BURNER, amount);
        uint256 bridgeBefore = IToken(OLAS).balanceOf(address(bridge2Burner));
        _setBuybackSlippage(1);
        Facts memory before_ = _facts(pool);
        vm.expectRevert(bytes("Too little received"));
        buyBackBurner.buyBack(WETH, amount, 0);
        assertEq(keccak256(abi.encode(_facts(pool))), keccak256(abi.encode(before_)));
        assertEq(IToken(WETH).balanceOf(BUY_BACK_BURNER), amount);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)), bridgeBefore);
        // Stress-test allowance only, including the pool's 10% total-fee ceiling.
        _setBuybackSlippage(2000);
        buyBackBurner.buyBack(WETH, amount, 0);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)) - bridgeBefore, expected);
        assertEq(IToken(WETH).balanceOf(BUY_BACK_BURNER), 0);
    }

    function testPolicy_dynamicFeeCapAndMaintenance() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        _enableDynamicAndMovePrice(pool);
        liquidityManager.collectFees(TOKENS, TICK_SPACING);
        IAeroDynamicHook hook = _hook(pool);
        vm.prank(IAeroFeeFactory(FACTORY_V3).swapFeeManager());
        hook.setScalingFactor(address(pool), 1e18);
        vm.roll(block.number + 1);
        assertEq(_fee(pool, true, 1e10), 50_000);
        _policyMaintenance(pool, id);
    }

    function testPolicy_initialTransactionOverrideAndMaintenance() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        IAeroDynamicHook hook = _hook(pool);
        vm.prank(IAeroFeeFactory(FACTORY_V3).swapFeeManager());
        hook.setInitialFee(address(pool), 40_000);
        vm.roll(block.number + 1);
        assertEq(_fee(pool, true, 1e10), 40_000);
        _policyMaintenance(pool, id);
        assertEq(hook.blockFee(address(pool), block.number), 10_000, "raw block fee differs from first tx override");
    }

    function testPolicy_zeroScalingFallsBackAndSentinelPinsSpacingFee() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        _enableDynamicAndMovePrice(pool);
        liquidityManager.collectFees(TOKENS, TICK_SPACING);
        IAeroDynamicHook hook = _hook(pool);
        vm.startPrank(IAeroFeeFactory(FACTORY_V3).swapFeeManager());
        hook.setDefaultScalingFactor(1e9);
        hook.setScalingFactor(address(pool), 0);
        vm.stopPrank();
        vm.roll(block.number + 1);
        assertGt(_fee(pool, true, 1e10), 10_000, "zero per-pool scaling inherits global dynamics");
        vm.prank(IAeroFeeFactory(FACTORY_V3).swapFeeManager());
        hook.setCustomFee(address(pool), type(uint24).max);
        assertEq(_fee(pool, true, 1e10), 10_000, "sentinel selects spacing fee, not a zero swap fee");
        _policyMaintenance(pool, id);
    }

    function testPolicy_initialBaseAndSpacingSentinels() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        IAeroDynamicHook hook = _hook(pool);
        address manager = IAeroFeeFactory(FACTORY_V3).swapFeeManager();
        vm.startPrank(manager);
        hook.setCustomFee(address(pool), 20_000);
        hook.setInitialFee(address(pool), 0);
        vm.stopPrank();
        vm.roll(block.number + 1);
        assertEq(_fee(pool, true, 1e10), 20_000, "initial zero selects custom base fee");
        uint256 snapshot = vm.snapshotState();
        _policyMaintenance(pool, id);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.prank(manager);
        hook.setInitialFee(address(pool), type(uint24).max);
        assertEq(_fee(pool, true, 1e10), 10_000, "initial sentinel selects spacing fee");
        snapshot = vm.snapshotState();
        _policyMaintenance(pool, id);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.prank(manager);
        hook.disableInitialFee(address(pool));
        assertEq(_fee(pool, true, 1e10), 20_000);
        _policyMaintenance(pool, id);
    }

    function testPolicy_routerDiscountAndMaintenance() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        IAeroDiscount registry = IAeroDiscount(IAeroFeeFactory(FACTORY_V3).discountRegistry());
        vm.prank(registry.owner());
        registry.registerPoolDiscount(ROUTER_V3, address(pool), 500_000);
        assertEq(registry.getDiscount(address(pool), ROUTER_V3), 500_000);
        assertEq(_fee(pool, true, 1e10), 5_000);
        _policyMaintenance(pool, id);
    }

    function testPolicy_priorityFeeThresholdAndPoolCeiling() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        IAeroMevTax tax = IAeroMevTax(_hook(pool).mevTaxModule());
        emit log_named_uint("Pinned MEV multiplier", tax.priorityFeeMultiplier());
        // Activate the deployed module only on this fork, with an exact threshold/multiplier.
        vm.startPrank(tax.owner());
        tax.setMultiplier(1e12);
        tax.setMinThreshold(100);
        tax.setBaseFeeFactor(0);
        vm.stopPrank();
        uint256 threshold = uint256(tax.baseFeeFactor()) * block.basefee;
        if (threshold < tax.minThreshold()) threshold = tax.minThreshold();
        vm.txGasPrice(block.basefee + threshold);
        (uint24 fee, bool toxic) = tax.getMevTax();
        assertEq(fee, 0);
        assertFalse(toxic);
        assertEq(_fee(pool, true, 1e10), 10_000);
        uint256 multiplier = tax.priorityFeeMultiplier();
        assertGt(multiplier, 0);
        vm.txGasPrice(block.basefee + threshold + 1);
        (fee, toxic) = tax.getMevTax();
        assertTrue(toxic);
        assertEq(fee, FullMath.mulDivRoundingUp(1, multiplier, 1e12));
        assertEq(_fee(pool, true, 1e10), 10_000 + fee);
        vm.txGasPrice(block.basefee + threshold + FullMath.mulDivRoundingUp(100_000, 1e12, multiplier));
        (fee, toxic) = tax.getMevTax();
        assertEq(fee, 100_000);
        assertTrue(toxic);
        // Raw hook fee is base + tax; the pool clamps their sum to 100,000 pips.
        assertEq(_fee(pool, true, 1e10), 100_000);
        _enableUnstakedDeduction(pool);
        _policyMaintenance(pool, id);
    }

    struct CrossingFees {
        uint256 gross;
        uint256 gauge;
        uint256 lm;
        uint256 other;
    }

    // Independent two-segment accounting: one initialized boundary, no bitmap-word edge.
    // Both LPs are unstaked. The second LP exits/re-enters at its lower boundary.
    function _segment(uint160 low, uint160 high, uint128 active, bool zeroForOne, uint24 fee, uint24 deduction)
        private pure returns (uint256 principalIn, uint256 out, uint256 gross, uint256 gauge, uint256 growth)
    {
        uint256 amount0Up = FullMath.mulDivRoundingUp(uint256(active) << 96, high - low, high);
        amount0Up = (amount0Up + low - 1) / low;
        uint256 amount0Down = FullMath.mulDiv(uint256(active) << 96, high - low, high) / low;
        principalIn = zeroForOne ? amount0Up : FullMath.mulDivRoundingUp(active, high - low, Q96);
        out = zeroForOne ? FullMath.mulDiv(active, high - low, Q96) : amount0Down;
        gross = FullMath.mulDivRoundingUp(principalIn, fee, PIPS - fee);
        gauge = FullMath.mulDivRoundingUp(gross, deduction, PIPS);
        growth = FullMath.mulDiv(gross - gauge, Q128, active);
    }

    function _crossAndReconcile(IAeroFeePool pool, uint128 lmL, uint128 otherL, uint160 boundary,
        uint160 destination, bool zeroForOne) private returns (CrossingFees memory fees)
    {
        Facts memory before_ = _facts(pool);
        uint24 fee = _fee(pool, zeroForOne, 1);
        uint24 deduction = pool.unstakedFee();
        uint160 high = zeroForOne ? before_.sqrtP : destination;
        uint160 low = zeroForOne ? destination : before_.sqrtP;
        (uint256 sharedIn, uint256 sharedOut, uint256 sharedFee, uint256 sharedGauge, uint256 sharedGrowth) =
            _segment(boundary, high, lmL + otherL, zeroForOne, fee, deduction);
        (uint256 soloIn, uint256 soloOut, uint256 soloFee, uint256 soloGauge, uint256 soloGrowth) =
            _segment(low, boundary, lmL, zeroForOne, fee, deduction);
        fees.gross = sharedFee + soloFee;
        fees.gauge = sharedGauge + soloGauge;
        fees.lm = FullMath.mulDiv(sharedGrowth + soloGrowth, lmL, Q128);
        fees.other = FullMath.mulDiv(sharedGrowth, otherL, Q128);
        uint256 expectedIn = sharedIn + soloIn + fees.gross;
        address input = zeroForOne ? WETH : OLAS;
        address output = zeroForOne ? OLAS : WETH;
        deal(input, address(this), expectedIn + 1); // Extra atom ensures both steps reach their exact targets.
        IToken(input).approve(ROUTER_V3, expectedIn + 1);
        uint256 out = ISlipstream(ROUTER_V3).exactInputSingle(ISlipstream.ExactInputSingleParams(
            input, output, TICK_SPACING, address(this), block.timestamp, expectedIn + 1, 0, destination));
        Facts memory after_ = _facts(pool);
        assertEq(after_.sqrtP, destination);
        assertEq(_word(before_.tick), _word(after_.tick), "unexpected bitmap step");
        assertEq(out, sharedOut + soloOut);
        assertEq(after_.liquidity, zeroForOne ? lmL : lmL + otherL);
        assertTrue(after_.liquidity != before_.liquidity, "initialized boundary was not crossed");
        assertEq(IToken(input).balanceOf(address(this)), 1);
        if (zeroForOne) {
            assertEq(after_.balance0 - before_.balance0, expectedIn);
            assertEq(before_.balance1 - after_.balance1, out);
            assertEq(after_.growth0 - before_.growth0, sharedGrowth + soloGrowth);
            assertEq(after_.growth1, before_.growth1);
            assertEq(after_.gauge0 - before_.gauge0, fees.gauge);
        } else {
            assertEq(after_.balance1 - before_.balance1, expectedIn);
            assertEq(before_.balance0 - after_.balance0, out);
            assertEq(after_.growth1 - before_.growth1, sharedGrowth + soloGrowth);
            assertEq(after_.growth0, before_.growth0);
            assertEq(after_.gauge1 - before_.gauge1, fees.gauge);
        }
        assertGe(fees.gross, fees.gauge + fees.lm + fees.other);
    }

    function testFees_multipleLPsCrossingInitializedTicksBothDirections() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        _enableUnstakedDeduction(pool);
        _enableDynamicAndMovePrice(pool);
        liquidityManager.collectFees(TOKENS, TICK_SPACING);
        vm.roll(block.number + 1);
        Facts memory start = _facts(pool);
        int24 lower = (start.tick / TICK_SPACING) * TICK_SPACING - TICK_SPACING;
        int24 upper = lower + 3 * TICK_SPACING;
        IAeroFeeNPM.Position memory lm = IAeroFeeNPM(POSITION_MANAGER_V3).positions(id);
        assertLt(lm.tickLower, lower - TICK_SPACING);
        assertGt(lm.tickUpper, upper);
        deal(WETH, address(this), 1 ether);
        deal(OLAS, address(this), 40_000 ether);
        IToken(WETH).approve(POSITION_MANAGER_V3, 1 ether);
        IToken(OLAS).approve(POSITION_MANAGER_V3, 40_000 ether);
        (uint256 otherId, uint128 otherL,,) = INPMMintSlipstream(POSITION_MANAGER_V3).mint(
            INPMMintSlipstream.MintParams(WETH, OLAS, TICK_SPACING, lower, upper,
                1 ether, 40_000 ether, 0, 0, address(this), block.timestamp, 0));
        assertGt(otherL, 0);
        assertEq(pool.liquidity(), lm.liquidity + otherL);
        uint160 boundary = TickMath.getSqrtRatioAtTick(lower);
        CrossingFees memory wethFees = _crossAndReconcile(pool, lm.liquidity, otherL, boundary,
            TickMath.getSqrtRatioAtTick(lower - TICK_SPACING), true);
        CrossingFees memory olasFees = _crossAndReconcile(pool, lm.liquidity, otherL, boundary, start.sqrtP, false);
        (uint256 inside0, uint256 inside1) = pool.getFeeGrowthInside(lm.tickLower, lm.tickUpper);
        assertEq(FullMath.mulDiv(inside0 - lm.feeGrowthInside0LastX128, lm.liquidity, Q128), wethFees.lm);
        assertEq(FullMath.mulDiv(inside1 - lm.feeGrowthInside1LastX128, lm.liquidity, Q128), olasFees.lm);
        FeeTotals memory fees = FeeTotals(wethFees.gross, olasFees.gross,
            wethFees.gauge + wethFees.other, olasFees.gauge + olasFees.other, wethFees.lm, olasFees.lm);
        // The helper checks LM recipients and preserved staged funds; the other LP is reconciled below.
        _collectAndReconcile(pool, id, lm.liquidity, false, fees);
        uint256 before0 = IToken(WETH).balanceOf(address(this));
        uint256 before1 = IToken(OLAS).balanceOf(address(this));
        Facts memory beforePool = _facts(pool);
        (uint256 received0, uint256 received1) = INPMMintSlipstream(POSITION_MANAGER_V3).collect(
            INPMMintSlipstream.CollectParams(otherId, address(this), type(uint128).max, type(uint128).max));
        assertEq(received0, wethFees.other);
        assertEq(received1, olasFees.other);
        assertEq(IToken(WETH).balanceOf(address(this)) - before0, received0);
        assertEq(IToken(OLAS).balanceOf(address(this)) - before1, received1);
        assertEq(beforePool.balance0 - IToken(WETH).balanceOf(address(pool)), received0);
        assertEq(beforePool.balance1 - IToken(OLAS).balanceOf(address(pool)), received1);
        assertEq(IAeroFeeNPM(POSITION_MANAGER_V3).positions(otherId).liquidity, otherL);
        emit log_named_uint("Other LP WETH fees", received0);
        emit log_named_uint("Other LP OLAS fees", received1);
    }

    function testFees_exactBothTokensAndRecipients() public { _reconcileFees(false, false, false); }
    function testFees_reversedTokenOrderPreservesStagedFunds() public { _reconcileFees(true, false, false); }
    function testFees_elevatedDynamicFeeExactAccounting() public { _reconcileFees(false, true, false); }
    function testFees_activeGaugeDeductionAndDynamicFeeExactAccounting() public { _reconcileFees(false, true, true); }

    function testWithdrawal_fullExternalExitReturnsBothTokens() public {
        (IAeroFeePool pool, uint256 id) = _openPosition();
        _swapAndReconcile(pool, true, 1e10 + 123);
        _swapAndReconcile(pool, false, 1e14 + 321);
        uint128 previousLiquidity = IAeroFeeNPM(POSITION_MANAGER_V3).positions(id).liquidity;
        Facts memory before_ = _facts(pool);
        uint256 treasury0 = IToken(WETH).balanceOf(TIMELOCK);
        uint256 treasury1 = IToken(OLAS).balanceOf(TIMELOCK);
        (uint256 returnedId, uint128 removed, uint256[] memory amounts) =
            liquidityManager.decreaseLiquidity(TOKENS, TICK_SPACING, MAX_BPS, 0);
        assertEq(returnedId, id);
        assertEq(removed, previousLiquidity);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertEq(IAeroFeeNPM(POSITION_MANAGER_V3).positions(id).liquidity, 0);
        assertEq(pool.liquidity(), 0);
        assertEq(IToken(WETH).balanceOf(TIMELOCK) - treasury0, amounts[0]);
        assertEq(IToken(OLAS).balanceOf(TIMELOCK) - treasury1, amounts[1]);
        assertEq(before_.balance0 - IToken(WETH).balanceOf(address(pool)), amounts[0]);
        assertEq(before_.balance1 - IToken(OLAS).balanceOf(address(pool)), amounts[1]);
        assertEq(IToken(WETH).balanceOf(address(liquidityManager)), 0);
        assertEq(IToken(OLAS).balanceOf(address(liquidityManager)), 0);
    }

    function _twapQuote(IAeroFeePool pool, uint256 amount) private view returns (uint256) {
        uint160 sqrtP = liquidityManager.checkPoolAndGetCenterPrice(address(pool));
        return FullMath.mulDiv(amount, FullMath.mulDiv(sqrtP, sqrtP, 1 << 64), Q128);
    }

    function _setBuybackSlippage(uint256 bps) private {
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        uint256[] memory limits = new uint256[](1);
        limits[0] = bps;
        vm.prank(IProxy(BUY_BACK_BURNER).owner());
        buyBackBurner.setMaxSlippages(tokens, limits);
    }

    function testDynamicFee_buybackOutputAndAtomicMinimumOutputRevert() public {
        (IAeroFeePool pool,) = _openPosition();
        _enableDynamicAndMovePrice(pool);
        uint256 amount = 1e10;
        uint24 lowFee = _fee(pool, true, amount);
        uint256 lowQuote = _twapQuote(pool, amount);
        uint256 snapshot = vm.snapshotState();
        uint256 lowOut = _swap(WETH, OLAS, amount);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        snapshot = vm.snapshotState();
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        uint24 highFee = _fee(pool, true, amount);
        uint256 highQuote = _twapQuote(pool, amount);
        uint256 highOut = _swap(WETH, OLAS, amount);
        assertGt(highFee, lowFee);
        assertLt(highOut, lowOut);
        assertTrue(vm.revertToStateAndDelete(snapshot));

        // Choose an exact BPS boundary between the two observed outputs, rather than guessing a fee.
        uint256 quote = lowQuote > highQuote ? lowQuote : highQuote;
        uint256 tolerance = MAX_BPS - FullMath.mulDiv(lowOut, MAX_BPS, quote) + 1;
        assertLt(tolerance, 1000);
        assertLe(FullMath.mulDiv(lowQuote, MAX_BPS - tolerance, MAX_BPS), lowOut);
        assertGt(FullMath.mulDiv(highQuote, MAX_BPS - tolerance, MAX_BPS), highOut);
        _setBuybackSlippage(tolerance);
        deal(WETH, BUY_BACK_BURNER, amount);
        uint256 bridgeBefore = IToken(OLAS).balanceOf(address(bridge2Burner));
        snapshot = vm.snapshotState();
        buyBackBurner.buyBack(WETH, amount, 0);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)) - bridgeBefore, lowOut);
        assertTrue(vm.revertToStateAndDelete(snapshot));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        Facts memory before_ = _facts(pool);
        vm.expectRevert(bytes("Too little received"));
        buyBackBurner.buyBack(WETH, amount, 0);
        Facts memory after_ = _facts(pool);
        assertEq(after_.sqrtP, before_.sqrtP);
        assertEq(after_.growth0, before_.growth0);
        assertEq(after_.growth1, before_.growth1);
        assertEq(after_.balance0, before_.balance0);
        assertEq(after_.balance1, before_.balance1);
        assertEq(IToken(WETH).balanceOf(BUY_BACK_BURNER), amount);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)), bridgeBefore);
        // Explicit test-only wider tolerance. This is not a production recommendation.
        _setBuybackSlippage(1000);
        buyBackBurner.buyBack(WETH, amount, 0);
        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)) - bridgeBefore, highOut);
        emit log_named_uint("Cached swap fee pips", lowFee);
        emit log_named_uint("Recomputed dynamic swap fee pips", highFee);
        emit log_named_uint("Low-fee buyback OLAS output atoms", lowOut);
        emit log_named_uint("High-fee buyback OLAS output atoms", highOut);
        emit log_named_uint("Tight buyback tolerance bps", tolerance);
    }
}

/// @dev Inherits all exact accounting and dynamic-fee assertions on Optimism block 158748334.
contract LiquidityManagerAeroFeesOptimismTest is LiquidityManagerAeroFeesBaseTest {
    function _configureSlipstream() internal override {
        _configureOptimism(true);
        GOVERNANCE_CREATION_MODULE = 0x97aBFe52c819AB175F6426eC30BBF2dF29f9E94b;
    }
}

/// @dev Foundry executes setUp and the test as separate top-level transactions.
///      This checks actual transient-cache expiry; vm.roll alone does not end a transaction.
contract LiquidityManagerAeroInitialTxBaseTest is BaseSetup {
    IAeroFeePool private initialPool;
    IAeroDynamicHook private initialHook;

    function _configureSlipstream() internal virtual override {
        assertEq(block.chainid, 8453);
        ROUTER_V3 = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;
        FACTORY_V3 = 0x9CB220581b91b0C83223012FE69688b92aD07a76;
        POSITION_MANAGER_V3 = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
    }

    function _initialFee() private view returns (uint24) {
        (uint160 price, int24 tick,,,,) = initialPool.slot0();
        return initialPool.beforeSwapFee(IAeroFeePool.SwapParams(
            ROUTER_V3, address(this), true, 1e10, 4295128740, "", price, tick));
    }

    function setUp() public override {
        super.setUp();
        _seedWideLiquidity();
        initialPool = IAeroFeePool(ISlipstream(FACTORY_V3).getPool(WETH, OLAS, TICK_SPACING));
        initialHook = IAeroDynamicHook(IAeroFeeFactory(FACTORY_V3).getPoolSwapHook(address(initialPool)));
        IAeroDiscount registry = IAeroDiscount(IAeroFeeFactory(FACTORY_V3).discountRegistry());
        vm.prank(registry.owner());
        registry.registerPoolDiscount(ROUTER_V3, address(initialPool), 500_000);
        vm.prank(IAeroFeeFactory(FACTORY_V3).swapFeeManager());
        initialHook.setInitialFee(address(initialPool), 40_000);
        vm.txGasPrice(block.basefee);
        vm.roll(block.number + 1);
        assertEq(_initialFee(), 40_000);
        _swap(WETH, OLAS, 1e10);
        assertEq(_initialFee(), 40_000, "first transaction keeps its override");
        assertEq(initialHook.blockFee(address(initialPool), block.number), 10_000);
    }

    function testPolicy_nextTransactionUsesDiscountedCachedBlockFee() public {
        vm.txGasPrice(block.basefee);
        assertEq(initialHook.blockFee(address(initialPool), block.number), 10_000);
        assertEq(_initialFee(), 5_000, "next transaction discounts the cached fee after override expires");
        assertGt(_swap(WETH, OLAS, 1e10), 0);
        assertEq(_initialFee(), 5_000);
        vm.roll(block.number + 1);
        assertEq(_initialFee(), 40_000, "new block starts another initial transaction");
    }
}

contract LiquidityManagerAeroInitialTxOptimismTest is LiquidityManagerAeroInitialTxBaseTest {
    function _configureSlipstream() internal override { _configureOptimism(true); }
}
