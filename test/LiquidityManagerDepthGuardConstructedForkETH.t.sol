// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerUniV2UniV3} from "../contracts/pol/LiquidityManagerUniV2UniV3.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";

/// @dev Harness exposing the internal depth check and a direct factor setter.
contract LMForkHarness is LiquidityManagerUniV2UniV3 {
    constructor()
        LiquidityManagerUniV2UniV3(
            0x0001A500A6B18995B03f44bb040A5fFc28E45CB0,
            address(0xBEEF),
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88, // real NonfungiblePositionManager (factory() read in ctor)
            address(0xCAFE),
            1,
            address(0xD00D)
        )
    {}

    function setFactor(uint256 f) external {
        minDepthFactor = f;
    }

    function checkDepth(address pool, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96) external view {
        _checkPoolDepth(pool, amount0, amount1, sqrtPriceX96);
    }
}

interface IV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1);
    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256 amount0, uint256 amount1);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function liquidity() external view returns (uint128);
}

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Constructed-pool validation of the depth precondition against real Uniswap V3 mechanics.
///         Deploys its own V3 pool, warms a full SECONDS_AGO observation window with controlled liquidity, and
///         compares the guard's ESTIMATED band-inventory value against ACTUAL executable depth across the band
///         for: a wide (≈uniform) position, a narrow position concentrated around price, and a
///         high-history-then-depleted pool. Produces the evidence for the §10.1a validation items 1–3 and the
///         at-execution companion-check decision. Requires ETH_RPC_URL; skips cleanly when unset.
contract LiquidityManagerDepthGuardConstructedForkETH is Test {
    IV3Factory constant FACTORY = IV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24 constant FEE = 3000;
    uint256 constant PIN_BLOCK = 21_000_000;
    uint32 constant SECONDS_AGO = 1800;
    uint160 constant SQRT_1 = uint160(1) << 96; // price 1, tick 0
    int24 constant BAND_TICKS = 198; // ±2%, matches the contract

    LMForkHarness lm;
    MockERC20 t0;
    MockERC20 t1;

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, PIN_BLOCK);
        lm = new LMForkHarness();

        // Deterministic token ordering: token0 < token1.
        MockERC20 a = new MockERC20();
        MockERC20 b = new MockERC20();
        (t0, t1) = address(a) < address(b) ? (a, b) : (b, a);
        t0.mint(address(this), type(uint128).max);
        t1.mint(address(this), type(uint128).max);
    }

    modifier onFork() {
        if (address(lm) == address(0)) {
            emit log("ETH_RPC_URL not set - skipping constructed-pool fork test");
            return;
        }
        _;
    }

    // ---- Uniswap V3 callbacks (this contract is the LP and the swapper) ----
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (amount0Owed > 0) t0.transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) t1.transfer(msg.sender, amount1Owed);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) t0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) t1.transfer(msg.sender, uint256(amount1Delta));
    }

    function _newPool() internal returns (IV3Pool pool) {
        pool = IV3Pool(FACTORY.createPool(address(t0), address(t1), FEE));
        pool.initialize(SQRT_1);
        pool.increaseObservationCardinalityNext(300);
    }

    // Write an observation at the current timestamp with a negligible swap.
    function _poke(IV3Pool pool) internal {
        pool.swap(address(this), true, int256(1), TickMath.getSqrtRatioAtTick(-1), "");
    }

    // Warm a full SECONDS_AGO window at the pool's current (sustained) liquidity.
    function _warmSustained(IV3Pool pool) internal {
        vm.warp(block.timestamp + 1);
        _poke(pool);
        vm.warp(block.timestamp + SECONDS_AGO + 60);
        _poke(pool);
    }

    function _sqrtBand() internal pure returns (uint160 lower, uint160 upper) {
        lower = TickMath.getSqrtRatioAtTick(-BAND_TICKS);
        upper = TickMath.getSqrtRatioAtTick(BAND_TICKS);
    }

    // Actual executable depth across ±BAND_TICKS, valued in token1: token1 out moving price to the lower
    // bound, plus token0 out moving to the upper bound valued at price 1. Measured without persisting state.
    function _actualBandDepthToken1(IV3Pool pool) internal returns (uint256 depth1) {
        (uint160 lower, uint160 upper) = _sqrtBand();
        uint256 snap = vm.snapshotState();

        // Move price down to -2%: token0 in, token1 out.
        (, int256 d1Down) = pool.swap(address(this), true, type(int256).max / 2, lower, "");
        uint256 token1Out = d1Down < 0 ? uint256(-d1Down) : 0;
        vm.revertToState(snap);

        snap = vm.snapshotState();
        // Move price up to +2%: token1 in, token0 out.
        (int256 d0Up,) = pool.swap(address(this), false, type(int256).max / 2, upper, "");
        uint256 token0Out = d0Up < 0 ? uint256(-d0Up) : 0;
        vm.revertToState(snap);

        // Value token0 at price 1 (1:1 tokens, 18 decimals): token0Out == token1-equivalent.
        depth1 = token1Out + token0Out;
    }

    function _estimate(IV3Pool pool) internal view returns (uint256) {
        (uint160 sqrtP,,,,,,) = pool.slot0();
        return lm.estimatedBandInventoryToken1(address(pool), sqrtP);
    }

    // --- Scenario WIDE: liquidity spread well beyond the band → estimate ≈ actual executable depth. ---
    function test_constructed_wide_estimateMatchesActual() public onFork {
        IV3Pool pool = _newPool();
        pool.mint(address(this), -6000, 6000, 1e18, ""); // ±~80%, uniform across the ±2% band
        _warmSustained(pool);

        uint256 est = _estimate(pool);
        uint256 actual = _actualBandDepthToken1(pool);
        emit log_named_uint("WIDE estimate (token1)", est);
        emit log_named_uint("WIDE actual   (token1)", actual);
        assertGt(est, 0, "wide estimate must be positive");
        // Uniform liquidity across the band: estimate should be close to actual (within 5%).
        assertApproxEqRel(est, actual, 5e16, "wide: estimate should track actual executable depth");
    }

    // --- Scenario NARROW (T-nr2): same in-range liquidity concentrated tightly around price. ---
    //     Estimate (uniform ±198-tick assumption) OVER-states true executable depth to ±2%.
    function test_constructed_narrow_estimateOverstatesActual() public onFork {
        IV3Pool pool = _newPool();
        pool.mint(address(this), -60, 60, 1e18, ""); // ±~0.6%, same L as wide while price is centered
        _warmSustained(pool);

        uint256 est = _estimate(pool);
        uint256 actual = _actualBandDepthToken1(pool);
        emit log_named_uint("NARROW estimate (token1)", est);
        emit log_named_uint("NARROW actual   (token1)", actual);
        // Same in-range L while centered, so the estimate ~matches the wide case, but real executable depth to
        // ±2% is far smaller because liquidity ends at ±0.6%. This is the over-statement motivating a companion
        // check. Require the estimate to exceed actual by a wide margin.
        assertGt(est, actual * 2, "narrow: estimate must materially over-state actual executable depth");
    }

    // --- Scenario DEPLETION (T2b): high history, then liquidity removed just before execution. ---
    //     The window metric stays high while current executable depth collapses.
    function test_constructed_depletion_metricStaysHighWhileDepthCollapses() public onFork {
        IV3Pool pool = _newPool();
        pool.mint(address(this), -6000, 6000, 1e18, "");
        _warmSustained(pool);

        uint256 estBefore = _estimate(pool);
        uint256 actualBefore = _actualBandDepthToken1(pool);

        // Remove ~99% of liquidity, then write one more observation (one block later).
        pool.burn(-6000, 6000, uint128(99e16));
        vm.warp(block.timestamp + 12);
        _poke(pool);

        uint256 estAfter = _estimate(pool);
        uint256 actualAfter = _actualBandDepthToken1(pool);
        emit log_named_uint("DEPLETION est before", estBefore);
        emit log_named_uint("DEPLETION est after ", estAfter);
        emit log_named_uint("DEPLETION actual before", actualBefore);
        emit log_named_uint("DEPLETION actual after ", actualAfter);

        // Current executable depth collapses immediately...
        assertLt(actualAfter, actualBefore / 10, "actual depth should collapse after depletion");
        // ...while the window-aggregate estimate stays high (history dominates the 30-min mean).
        assertGt(estAfter, estBefore / 2, "window estimate should stay high right after depletion");
    }
}
