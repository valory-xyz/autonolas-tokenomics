pragma solidity ^0.8.30;

import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {Bridge2BurnerOptimism} from "../contracts/utils/Bridge2BurnerOptimism.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {LiquidityManagerOptimism} from "../contracts/pol/LiquidityManagerOptimism.sol";
import {NotEnoughHistory} from "../contracts/pol/LiquidityManagerCore.sol";
import {LiquidityManagerProxy} from "../contracts/proxies/LiquidityManagerProxy.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";

// Balancer interface
interface IBalancer {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /// @dev Swaps tokens on Balancer.
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
    external payable returns (uint256);

    function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );
}

interface ISlipstream {
    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param tickSpacing The desired tick spacing for the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool, as a Q64.96
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. The call will
    /// revert if the pool already exists, the tick spacing is invalid, or the token arguments are invalid
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
    external
    returns (address pool);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);

    function slot0() external view
    returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality,
        uint16 observationCardinalityNext, bool unlocked);

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}

interface INPMMintSlipstream {
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface IProxy {
    function changeImplementation(address implementation) external;
    function owner() external view returns (address);
}

contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracleV2;
    Bridge2BurnerOptimism internal bridge2Burner;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerOptimism internal liquidityManager;
    BuyBackBurnerBalancer internal buyBackBurner;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    uint256[2] internal initialAmounts;
    uint160 internal sqrtPriceX96;
    address internal constant OLAS = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address[] internal TOKENS = [WETH, OLAS];
    address internal constant TIMELOCK = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant L2_TOKEN_RELAYER = 0x4200000000000000000000000000000000000010;
    address internal constant POOL_V2 = 0x2da6e67C45aF2aaA539294D9FA27ea50CE4e2C5f;
    bytes32 internal constant POOL_V2_BYTES32 = 0x2da6e67c45af2aaa539294d9fa27ea50ce4e2c5f0002000000000000000001a3;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant ROUTER_V3 = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address internal constant FACTORY_V3 = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address internal constant POSITION_MANAGER_V3 = 0x827922686190790b37229fd06084350E74485b72;
    address internal constant BUY_BACK_BURNER = 0x3FD8C757dE190bcc82cF69Df3Cd9Ab15bCec1426;
    address internal constant BBB_OWNER = 0x6F7a4938AB3bbF69480E7C109Af778ee78099Be7;
    uint16 internal constant observationCardinality = 60;
    uint256 internal constant maxSlippageBps = 5000;
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 900;
    int24 internal constant TICK_SPACING = 100;
    // Allowed rounding delta in 1e18 = 1%
    uint256 internal constant DELTA = 1e16;
    // Max bps value
    uint16 public constant MAX_BPS = 10_000;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy V2 oracle
        oracleV2 = new BalancerPriceOracle(BALANCER_VAULT, POOL_V2_BYTES32, OLAS, minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds);

        // Warm up oracle: two observations needed so both prevObservation and lastObservation are populated
        oracleV2.updatePrice();
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracleV2.updatePrice();

        // Deploy Bridge2Burner
        bridge2Burner = new Bridge2BurnerOptimism(OLAS, L2_TOKEN_RELAYER);

        // Deploy neighborhood scanner
        neighborhoodScanner = new NeighborhoodScanner();

        // Deploy LiquidityManagerOptimism implementation
        LiquidityManagerOptimism liquidityManagerImplementation = new LiquidityManagerOptimism(OLAS, TIMELOCK,
            POSITION_MANAGER_V3, address(neighborhoodScanner), observationCardinality, address(oracleV2),
            BALANCER_VAULT, address(bridge2Burner));

        // Deploy LiquidityManagerProxy
        bytes memory initPayload = abi.encodeWithSignature("initialize(uint16)", maxSlippageBps);
        LiquidityManagerProxy liquidityManagerProxy =
            new LiquidityManagerProxy(address(liquidityManagerImplementation), initPayload);

        // Wrap proxy into implementation
        liquidityManager = LiquidityManagerOptimism(address(liquidityManagerProxy));

        // Get pool total supply
        uint256 totalSupply = IToken(POOL_V2).totalSupply();

        // Mock liquidity transfer
        uint256 v2Liquidity = IToken(POOL_V2).balanceOf(0x4eDB5dd988b78B40E1b38592A4761F694E05ef05);
        vm.prank(0x4eDB5dd988b78B40E1b38592A4761F694E05ef05);
        IToken(POOL_V2).transfer(address(liquidityManager), v2Liquidity);

        (, uint256[] memory amounts, ) = IBalancer(BALANCER_VAULT).getPoolTokens(POOL_V2_BYTES32);
        initialAmounts[0] = amounts[0];
        initialAmounts[1] = amounts[1];
        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
        uint256 price = FixedPointMathLib.divWadDown(initialAmounts[1], initialAmounts[0]);

        // Calculate the square root of the price ratio in X96 format
        sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Create V3 pool
        ISlipstream(FACTORY_V3).createPool(WETH, OLAS, TICK_SPACING, sqrtPriceX96);

        // TODO Note that initial amount is smaller due to Balancer protocol fee
        // ProtocolFeesCollector::getSwapFeePercentage() ← [Return] 500000000000000000 [5e17]
        // Get V2 initial amounts on LiquidityManager
        initialAmounts[0] = (v2Liquidity * initialAmounts[0]) / totalSupply;
        initialAmounts[1] = (v2Liquidity * initialAmounts[1]) / totalSupply;

        // Deploy BuyBackBurner
        buyBackBurner = new BuyBackBurnerBalancer(address(liquidityManager), address(bridge2Burner), TIMELOCK, ROUTER_V3);

        // Read the live BBB proxy owner (it has drifted from the historical BBB_OWNER to the Timelock
        // on-chain; read it dynamically so the test works at the current block).
        address bbbOwner = IProxy(BUY_BACK_BURNER).owner();

        // Change BBB implementation
        vm.prank(bbbOwner);
        IProxy(BUY_BACK_BURNER).changeImplementation(address(buyBackBurner));

        // Wrap BBB implementation
        buyBackBurner = BuyBackBurnerBalancer(payable(BUY_BACK_BURNER));

        // Configure V3 pool for WETH (the secondToken; OLAS is in TOKENS but the API is keyed by secondToken)
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = ISlipstream(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], TICK_SPACING);
        vm.prank(bbbOwner);
        buyBackBurner.setV3Pools(secondTokens, pools);

        // Per-token max slippage for the WETH buyBack. Without it mapTokenMaxSlippages[WETH] == 0, so the V3
        // buyBack demands the exact zero-slippage oracle quote (H-02 fail-closed) and reverts on any price
        // impact. 10% mirrors the ETH suite.
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1000;
        vm.prank(bbbOwner);
        buyBackBurner.setMaxSlippages(secondTokens, slippages);

        // Pre-warm the freshly-created Slipstream pool so checkPoolAndGetCenterPrice can produce a
        // verifiable TWAP (the guard now fails closed). Mirrors the migration runbook.
        _warmUpV3Pool(pools[0]);
    }

    /// @dev Pre-warms a freshly-created Slipstream pool for the fail-closed guard: bump the observation
    ///      cardinality, seed wide-range liquidity, and create two observations spanning > SECONDS_AGO
    ///      via small swaps. The long warp needed for the V3 window would push the Balancer V2-exit
    ///      oracle past its maxStaleness (900s), so updatePrice() is interleaved to keep it warm and
    ///      leave a usable rolling window (prev >= 900s old, last <= 900s old) at test time.
    function _warmUpV3Pool(address pool) internal {
        // Grow the observation buffer
        ISlipstream(pool).increaseObservationCardinalityNext(observationCardinality);

        // Seed real wide-range liquidity (token0 = WETH < token1 = OLAS by address)
        int24 centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 lower = ((centerTick - 30000) / TICK_SPACING) * TICK_SPACING;
        int24 upper = ((centerTick + 30000) / TICK_SPACING) * TICK_SPACING;
        uint256 seedWeth = 20 ether;
        uint256 seedOlas = 500_000 ether;
        deal(WETH, address(this), seedWeth);
        deal(OLAS, address(this), seedOlas);
        IToken(WETH).approve(POSITION_MANAGER_V3, seedWeth);
        IToken(OLAS).approve(POSITION_MANAGER_V3, seedOlas);
        (uint256 seedId, uint128 seedLiq,,) = INPMMintSlipstream(POSITION_MANAGER_V3).mint(
            INPMMintSlipstream.MintParams({
                token0: WETH,
                token1: OLAS,
                tickSpacing: TICK_SPACING,
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: seedWeth,
                amount1Desired: seedOlas,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        );

        // An observation is only written when a swap changes the tick, so each swap must be large enough
        // to cross ticks. To avoid displacing the TWAP, do a quick up-then-back round trip at each end of
        // the window: the price is only away from the seed for ~1s per round trip, so the ~1800s TWAP
        // stays at the seed price and the deviation guard (slot0 vs TWAP <= 10%) is satisfied.
        vm.warp(block.timestamp + 1);
        _roundTrip();

        // Keep the Balancer V2-exit oracle warm across the long warp (updatePrice every >= 900s)
        vm.warp(block.timestamp + 900);
        oracleV2.updatePrice();
        vm.warp(block.timestamp + 900);
        oracleV2.updatePrice();

        // Second round trip near the end of the window: writes the recent observation and restores price
        vm.warp(block.timestamp + 1);
        _roundTrip();

        // Remove the seed liquidity so it does not compete with the LM's own position for swap fees in
        // later tests. Observations are pool-level and persist, so the guard stays satisfiable; the pool
        // is simply empty again (the convert under test re-adds the real liquidity).
        INPMMintSlipstream(POSITION_MANAGER_V3).decreaseLiquidity(
            INPMMintSlipstream.DecreaseLiquidityParams({
                tokenId: seedId,
                liquidity: seedLiq,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
        INPMMintSlipstream(POSITION_MANAGER_V3).collect(
            INPMMintSlipstream.CollectParams({
                tokenId: seedId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Sanity: both guards are now satisfiable
        liquidityManager.checkPoolAndGetCenterPrice(pool);
        oracleV2.getTWAP();
    }

    /// @dev A swap up then (next second) back, so two observations are written at distinct timestamps
    ///      while the price ends near where it started. The amount is kept small: per-tick liquidity in
    ///      the wide seed position is thin, so even 0.01 WETH crosses ticks (writing an observation)
    ///      while moving the price only ~0.05%, keeping slot0 within the deviation band of the TWAP.
    function _roundTrip() internal {
        uint256 olasOut = _swap(WETH, OLAS, 0.01 ether);
        vm.warp(block.timestamp + 1);
        _swap(OLAS, WETH, olasOut);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        deal(tokenIn, address(this), amountIn);
        IToken(tokenIn).approve(ROUTER_V3, amountIn);
        amountOut = ISlipstream(ROUTER_V3).exactInputSingle(
            ISlipstream.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: TICK_SPACING,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @dev Mints wide-range OLAS/WETH liquidity around the pool price so a subsequent buyBack has real depth
    ///      to trade against. The warm-up seed is removed after warming (so it does not steal the LM's fees in
    ///      the collectFees test); on-chain the pool would carry other LPs' liquidity, which this models. It is
    ///      balanced at the current (round-trip-restored) price, so it moves neither slot0 nor the TWAP.
    function _seedWideLiquidity() internal {
        int24 centerTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 lower = ((centerTick - 30000) / TICK_SPACING) * TICK_SPACING;
        int24 upper = ((centerTick + 30000) / TICK_SPACING) * TICK_SPACING;
        // Deep enough that a 0.5 WETH buyBack has negligible price impact (well inside the BBB slippage
        // tolerance). OLAS is the binding token at this price, so it is oversupplied relative to WETH.
        uint256 seedWeth = 400 ether;
        uint256 seedOlas = 10_000_000 ether;
        deal(WETH, address(this), seedWeth);
        deal(OLAS, address(this), seedOlas);
        IToken(WETH).approve(POSITION_MANAGER_V3, seedWeth);
        IToken(OLAS).approve(POSITION_MANAGER_V3, seedOlas);
        INPMMintSlipstream(POSITION_MANAGER_V3).mint(
            INPMMintSlipstream.MintParams({
                token0: WETH,
                token1: OLAS,
                tickSpacing: TICK_SPACING,
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: seedWeth,
                amount1Desired: seedOlas,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        );
    }
}

contract LiquidityManagerBaseTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev T9: changeRanges consumes the guard's price to re-mint. Once the seeded pool goes inactive
    ///      (> SECONDS_AGO without a trade) it fails closed with NotEnoughHistory rather than repricing
    ///      against a stale slot0. A subsequent swap would repopulate the buffer and unstick it.
    function testChangeRanges_inactivePool_revertsNotEnoughHistory() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;

        liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, 0, true);
        address pool = ISlipstream(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], TICK_SPACING);

        // Let the pool go quiet beyond the TWAP window
        vm.warp(block.timestamp + 1801);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughHistory.selector, pool));
        liquidityManager.changeRanges(TOKENS, TICK_SPACING, tickShifts, true);
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan.
    function testConvertToV3FullScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        // Checking low-level encoding
        address pool = ISlipstream(FACTORY_V3).getPool(TOKENS[0], TOKENS[1], TICK_SPACING);
        bytes memory payload = abi.encodeCall(ISlipstream.slot0, ());
        (,bytes memory returnData) = pool.call(payload);

        uint160 sqrtP;
        uint16 observationIndex;
        assembly {
            sqrtP := mload(add(returnData, 32))
            observationIndex := mload(add(returnData, 96))
        }

        // Sqrt price must be within limits (from TickMath)
        require(sqrtP >= 4295128739 && sqrtP <= 1461446703485210103287273052203988822378723970342, "sqrtP is wrong");
        // The pool has been pre-warmed (see BaseSetup._warmUpV3Pool), so observationIndex has advanced
        require(observationIndex > 0, "observationIndex must be non-zero after pre-warm");

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with 95% amount (5% of OLAS burn, 5% of WETH transferred) and optimized ticks scan.
    function testConvertToV3Conversion95Scan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 500;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        uint256 wethAmount = (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[0] = initialAmounts[0] - wethAmount;
        uint256 olasAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        uint256 deviation;
        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        // Get Bridge2Burner OLAS balance
        uint256 bridge2BurnerBalance = IToken(OLAS).balanceOf(address(bridge2Burner));

        // Amounts are different since Balancer fee is applied to OLAS initial amount (initialAmounts[1]) on pool exit
        deviation = FixedPointMathLib.divWadDown((olasAmount - bridge2BurnerBalance), bridge2BurnerBalance);
        require(deviation <= DELTA, "Bridge2Burner amount diverts more than expected");

        // Check Bridge2Burner balance
        require(IToken(OLAS).balanceOf(address(bridge2Burner)) > 0, "Bridge2Burner OLAS balance must be > 0");

        // Mock fund more OLAS, not to fail for min OLAS transfer
        deal(OLAS, address(bridge2Burner), bridge2Burner.MIN_OLAS_BALANCE());

        // Bridge OLAS to burn
        bridge2Burner.relayToL1Burner();
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and NO optimized ticks scan.
    function testConvertToV3FullNoScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = false;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // No scan = ticks are not optimized, deviation might not respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            // Increase DELTA by a factor of 50
            require(deviation <= DELTA * 50, "Price deviation too high");
        }
    }

    /// @dev Converts V2 pool into V3 with 95% amount (5% of OLAS burn, 5% of WETH transferred) and optimized ticks scan,
    ///      then decrease liquidity and reposition to new ticks.
    function testConvertToV3Conversion95ScanDecreaseLiquidityReposition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 1000;
        bool scan = true;

        // Initial OLAS burn amount
        uint256 olasAmount = (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;
        //console.log("Initial amounts[0]", initialAmounts[0]);
        //console.log("Initial amounts[1]", initialAmounts[1]);

        // Convert V2 to V3
        (uint256 positionId, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);


        // Decrease liquidity
        olasBurnRate = 500;
        uint16 decreaseRate = 1000;
        uint256[] memory decreaseAmounts = new uint256[](2);
        // Since we decreased - decreaseAmountsOut must be <= decreaseAmounts
        decreaseAmounts[0] = (amountsOut[0] * decreaseRate) / MAX_BPS;
        decreaseAmounts[1] = (amountsOut[1] * decreaseRate) / MAX_BPS;
        //console.log("Initial DECREASE amounts[0]", decreaseAmounts[0]);
        //console.log("Initial DECREASE amounts[1]", decreaseAmounts[1]);

        // Additional OLAS burn amount while decreasing liquidity
        olasAmount += (decreaseAmounts[1] * olasBurnRate) / MAX_BPS;

        (, , uint256[] memory decreaseAmountsOut) =
            liquidityManager.decreaseLiquidity(TOKENS, TICK_SPACING, decreaseRate, olasBurnRate);
        //console.log("DECREASE amountsOut[0]", decreaseAmountsOut[0]);
        //console.log("DECREASE amountsOut[1]", decreaseAmountsOut[1]);

        uint256 deviation;
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            deviation = FixedPointMathLib.divWadDown((decreaseAmounts[i] - decreaseAmountsOut[i]), decreaseAmountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }


        // Change ranges
        initialAmounts[0] -= decreaseAmounts[0];
        initialAmounts[1] -= decreaseAmounts[1];

        tickShifts[0] = -40000;
        tickShifts[1] = 35000;
        uint256 newPositionId;
        (newPositionId, , amountsOut) = liquidityManager.changeRanges(TOKENS, TICK_SPACING, tickShifts, scan);
        require(newPositionId != positionId, "Positions must be different");

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }

        // Get Bridge2Burner OLAS balance
        uint256 bridge2BurnerBalance = IToken(OLAS).balanceOf(address(bridge2Burner));

        // Amounts are different since Balancer fee is applied to OLAS initial amount (initialAmounts[1]) on pool exit
        deviation = FixedPointMathLib.divWadDown((olasAmount - bridge2BurnerBalance), bridge2BurnerBalance);
        require(deviation <= DELTA, "Bridge2Burner amount diverts more than expected");

        // Check Bridge2Burner balance
        require(IToken(OLAS).balanceOf(address(bridge2Burner)) > 0, "Bridge2Burner OLAS balance must be > 0");

        // Mock fund more OLAS, not to fail for min OLAS transfer
        deal(OLAS, address(bridge2Burner), bridge2Burner.MIN_OLAS_BALANCE());

        // Bridge OLAS to burn
        bridge2Burner.relayToL1Burner();
    }

    /// @dev Full maintenance lifecycle under the fail-closed price guard (Slipstream): convert V2->V3
    ///      (95%, scan), generate real fees via a price-neutral round-trip, collect them, reconvert, increase
    ///      liquidity, buyBack, and bridge OLAS to burn.
    /// @notice Fees are generated by a round-trip swap (OLAS->WETH then the WETH straight back) rather than a
    ///         one-way drain. Both legs accrue fees on the LM position, but slot0 returns to ~the pre-warmed
    ///         TWAP, so: the reconvert's TWAP-anchored `increaseLiquidity` re-add stays balanced (no `PSC`),
    ///         the price stays inside the LM position's tick range so the buyBack has active liquidity, and
    ///         every entry op satisfies the deviation gate. A one-way 10% drain would move slot0
    ///         >MAX_ALLOWED_DEVIATION and the guard would (rightly) reject the re-add — that refusal is
    ///         covered by the price-guard regression suite (I3). Mirrors the ETH suite copy.
    function testConvertToV3Conversion95ScanCollectFees() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -25000;
        tickShifts[1] = 15000;
        uint16 olasBurnRate = 500;
        bool scan = true;

        // Adjust initial amounts due to OLAS burn rate
        initialAmounts[0] = initialAmounts[0] - (initialAmounts[0] * olasBurnRate) / MAX_BPS;
        initialAmounts[1] = initialAmounts[1] - (initialAmounts[1] * olasBurnRate) / MAX_BPS;

        // Convert V2 to V3
        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        uint256 olasAmountToSwap = initialAmounts[0] / 10;
        // Fund deployer with OLAS
        deal(OLAS, deployer, olasAmountToSwap);

        // Approve tokens
        vm.startPrank(deployer);
        IToken(OLAS).approve(ROUTER_V3, olasAmountToSwap);

        // Leg 1: swap OLAS -> WETH (accrues OLAS-side fees on the LM position, moves slot0)
        uint256 wethOut = ISlipstream(ROUTER_V3).exactInputSingle(
            ISlipstream.ExactInputSingleParams({
                tokenIn: OLAS,
                tokenOut: WETH,
                tickSpacing: TICK_SPACING,
                recipient: deployer,
                deadline: block.timestamp + 1000,
                amountIn: olasAmountToSwap,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        // Leg 2: swap the WETH straight back to OLAS, restoring slot0 to ~its starting value (fees already
        // accrued on both legs). This keeps the price within the deviation gate and inside the LM tick range.
        IToken(WETH).approve(ROUTER_V3, wethOut);
        ISlipstream(ROUTER_V3).exactInputSingle(
            ISlipstream.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: OLAS,
                tickSpacing: TICK_SPACING,
                recipient: deployer,
                deadline: block.timestamp + 1000,
                amountIn: wethOut,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        // Collect fees
        amountsOut = liquidityManager.collectFees(TOKENS, TICK_SPACING);
        // OLAS collected fee must be > 0
        require(amountsOut[1] > 0);

        // Fund LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Convert to V3 again without a pair
        (, , amountsOut) =
            liquidityManager.convertToV3(TOKENS, 0, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // Fund more LiquidityManager with OLAS and WETH
        deal(OLAS, address(liquidityManager), olasAmountToSwap);
        deal(WETH, address(liquidityManager), wethOut);

        // Increase liquidity
        (, , amountsOut) = liquidityManager.increaseLiquidity(TOKENS, TICK_SPACING, olasBurnRate);

        // Check Bridge2Burner balance
        require(IToken(OLAS).balanceOf(address(bridge2Burner)) > 0, "Bridge2Burner OLAS balance must be > 0");

        // Mock fund more OLAS, not to fail for min OLAS transfer
        deal(OLAS, address(bridge2Burner), bridge2Burner.MIN_OLAS_BALANCE());

        // Mock WETH balance on BBB
        deal(WETH, BUY_BACK_BURNER, 0.5 ether);

        // Provide real pool depth for the buyBack (the warm-up seed was removed after warming; on-chain the
        // pool would carry other LPs). Balanced at the current price, so it moves neither slot0 nor the TWAP.
        _seedWideLiquidity();

        // Perform V3 swap in BBB using the whitelisted tick-spacing Slipstream pool (pre-warmed in setUp).
        // The Balancer V2 pool is too shallow after the 95% LP migration; the V3 path prices the buyBack off
        // the pool's verifiable TWAP, now with active liquidity to fill against.
        buyBackBurner.buyBack(WETH, 0.5 ether, 0);

        // Bridge OLAS to burn
        bridge2Burner.relayToL1Burner();
    }

    /// @dev Converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan, transfers position.
    function testConvertToV3FullScanTransferPosition() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 olasBurnRate = 0;
        bool scan = true;

        liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        liquidityManager.transferPositionId(TOKENS, TICK_SPACING, TIMELOCK);
    }

    /// @dev Fuzz: converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan,
    ///      safe tick shifts for deviation calculation.
    function testConvertToV3FullScanFuzz(uint24 lowerTickShift, uint24 upperTickShift) public {
        // Tick shifts: tick ± [5000, MAX_TICK]
        lowerTickShift = uint24(bound(lowerTickShift, 5000, 887272));
        upperTickShift = uint24(bound(upperTickShift, 5000, 887272));

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -int24(lowerTickShift);
        tickShifts[1] = int24(upperTickShift);
        uint16 olasBurnRate = 0;
        bool scan = true;

        (, , uint256[] memory amountsOut) =
            liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);

        // scan = ticks are optimized, deviation must respect DELTA
        for (uint256 i = 0; i < 2; ++i) {
            // initialAmounts[i] is always >= amountsOut[i]
            uint256 deviation = FixedPointMathLib.divWadDown((initialAmounts[i] - amountsOut[i]), amountsOut[i]);
            require(deviation <= DELTA, "Price deviation too high");
        }
    }

    /// @dev Fuzz: converts V2 pool into V3 with full amount (no OLAS burnt) and optimized ticks scan,
    ///     any possible tick shifts without measuring deviation.
    function testConvertToV3FullScanFuzzAllRange(uint24 lowerTickShift, uint24 upperTickShift) public {
        // Tick shifts: tick ± [1, MAX_TICK]
        lowerTickShift = uint24(bound(lowerTickShift, 1, 887272));
        upperTickShift = uint24(bound(upperTickShift, 1, 887272));

        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -int24(lowerTickShift);
        tickShifts[1] = int24(upperTickShift);

        uint16 olasBurnRate = 0;
        bool scan = true;

        liquidityManager.convertToV3(TOKENS, POOL_V2_BYTES32, TICK_SPACING, tickShifts, olasBurnRate, scan);
    }
}
