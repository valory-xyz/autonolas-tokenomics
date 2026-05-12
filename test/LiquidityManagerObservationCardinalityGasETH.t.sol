// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";

/// @dev Empirical proof that `IUniswapV3.increaseObservationCardinalityNext` scales linearly
///      with the requested cardinality (~22k gas per new slot — one cold SLOAD + one
///      0→non-zero SSTORE — plus loop overhead). `LiquidityManagerCore.convertToV3` calls it
///      once per fresh pool on top of the V3 mint, so the `observationCardinality` constructor
///      arg is a tax on the very first convertToV3 against any given pool.
///
///      Block cap on ETH is 30M with realistic single-tx ceilings around 25M. Cardinality
///      values that approach SECONDS_AGO/block_time (e.g. 1024 to "fully" cover the 1800s
///      TWAP window on 2s-block L2s) push the bump alone to ~22M gas — leaving no room for
///      the V3 mint or anything else convertToV3 does, and OOG-ing the tx.
///
///      Production picks of 60 (ETH, 12s blocks) and 120 (Base/Optimism, 2s blocks) keep the
///      bump under ~2.7M gas and rely on (a) the slot0 fallback in `checkPoolAndGetCenterPrice`
///      for freshly-initialized pools and (b) the fact that an observation is written at most
///      once per block, so for sparsely-traded OLAS pools 60–120 observations cover real-time
///      windows that vastly exceed the 1800s `SECONDS_AGO` window in practice.
///
///      Run:
///         forge test -f $FORK_ETH_NODE_URL --mc LiquidityManagerObservationCardinalityGasETH -vvv
///
///      Notes: the test uses freshly-deployed ERC20Token mocks rather than OLAS/WETH so the
///      pools always start at `(cardinality, cardinalityNext) = (1, 1)`, isolating the cost
///      of the bump. The gas behavior is identical against real production pools that haven't
///      seen `increaseObservationCardinalityNext` called against them.
contract LiquidityManagerObservationCardinalityGasETH is Test {
    // ETH mainnet UniswapV3 NonfungiblePositionManager
    address internal constant POSITION_MANAGER_V3 = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // Q64.96 representation of 1:1 = sqrt(1) << 96
    uint160 internal constant INIT_SQRT_PRICE_X96 = 79228162514264337593543950336;

    address internal poolForC60;
    address internal poolForC120;
    address internal poolFor1024;

    function setUp() public {
        ERC20Token tokenA = new ERC20Token();
        ERC20Token tokenB = new ERC20Token();
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        // Fresh V3 pools at three fee tiers — none of these existed for the freshly-deployed
        // mock tokens, so each starts at (cardinality, cardinalityNext) = (1, 1).
        poolForC60 = IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(t0, t1, 100, INIT_SQRT_PRICE_X96);
        poolForC120 = IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(t0, t1, 500, INIT_SQRT_PRICE_X96);
        poolFor1024 = IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(t0, t1, 3000, INIT_SQRT_PRICE_X96);

        _assertPristineCardinality(poolForC60);
        _assertPristineCardinality(poolForC120);
        _assertPristineCardinality(poolFor1024);
    }

    function _assertPristineCardinality(address pool) internal view {
        (,,, uint16 cardinality, uint16 cardinalityNext,,) = IUniswapV3(pool).slot0();
        assertEq(cardinality, 1, "fresh pool should report cardinality=1");
        assertEq(cardinalityNext, 1, "fresh pool should report cardinalityNext=1");
    }

    function _bumpAndMeasure(address pool, uint16 target) internal returns (uint256 gasUsed) {
        uint256 g0 = gasleft();
        IUniswapV3(pool).increaseObservationCardinalityNext(target);
        gasUsed = g0 - gasleft();

        (,,, , uint16 cardinalityNext,,) = IUniswapV3(pool).slot0();
        assertEq(cardinalityNext, target, "cardinalityNext should equal the requested target");
    }

    /// @dev Production ETH choice: observationCardinality=60 (60 × 12s = 720s nominal coverage).
    function testCardinality60_ProductionETH() public {
        uint256 gasUsed = _bumpAndMeasure(poolForC60, 60);
        console.log("increaseObservationCardinalityNext(60) gas:", gasUsed);
        // 59 new slots × ~22.1k cold SSTORE + loop overhead ≈ 1.3M. Comfortable headroom under L1's 30M cap.
        assertLt(gasUsed, 2_000_000, "60 cardinality bump must fit easily on L1");
    }

    /// @dev Production Base/Optimism choice: observationCardinality=120 (120 × 2s = 240s nominal coverage).
    function testCardinality120_ProductionL2() public {
        uint256 gasUsed = _bumpAndMeasure(poolForC120, 120);
        console.log("increaseObservationCardinalityNext(120) gas:", gasUsed);
        // 119 new slots × ~22.1k ≈ 2.63M. Still comfortably under L1's 30M cap.
        assertLt(gasUsed, 3_500_000, "120 cardinality bump must fit easily on L1 and L2");
    }

    /// @dev Hypothetical "full SECONDS_AGO coverage on 2s blocks" choice: cardinality=1024.
    ///      Proves the OOG hazard — the bump alone consumes ~22M gas, which is more than the
    ///      remaining headroom for the V3 mint and the rest of `convertToV3` on Ethereum L1.
    function testCardinality1024_BlowsTheGasBudget() public {
        uint256 gasUsed = _bumpAndMeasure(poolFor1024, 1024);
        console.log("increaseObservationCardinalityNext(1024) gas:", gasUsed);
        // 1023 new slots × ~22.1k ≈ 22.6M. Combined with V3 mint (~500k-1M) and LM accounting,
        // this overruns realistic L1 tx budgets (≤25M).
        assertGt(gasUsed, 18_000_000, "1024 cardinality bump must dominate any realistic L1 tx budget");
    }
}
