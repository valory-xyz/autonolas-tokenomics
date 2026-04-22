// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "../contracts/libraries/TickMath.sol";
import {BuyBackBurner, UnauthorizedPool} from "../contracts/utils/BuyBackBurner.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

// ---------------------------------------------------------------------------
// Mock ERC20 — mintable by anyone for test convenience
// ---------------------------------------------------------------------------
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// ---------------------------------------------------------------------------
// Mock Uniswap V3 factory — returns a single fixed pool for any triple
// ---------------------------------------------------------------------------
contract MockFactory {
    address public pool;
    function setPool(address _pool) external { pool = _pool; }
    function getPool(address, address, uint24) external view returns (address) { return pool; }
}

// ---------------------------------------------------------------------------
// Mock LiquidityManager — returns a configured sqrt price from checkPoolAndGetCenterPrice
// ---------------------------------------------------------------------------
contract MockLiquidityManager {
    address public factoryV3Addr;
    uint160 public centerSqrtPriceX96;

    constructor(address _factory) { factoryV3Addr = _factory; }
    function factoryV3() external view returns (address) { return factoryV3Addr; }
    function setCenterSqrtPriceX96(uint160 _sqrtPriceX96) external { centerSqrtPriceX96 = _sqrtPriceX96; }
    function checkPoolAndGetCenterPrice(address) external view returns (uint160) { return centerSqrtPriceX96; }
}

// ---------------------------------------------------------------------------
// Mock V3 swap router — records the amountOutMinimum handed in and returns
// a configurable realized OLAS output; reverts if realized < amountOutMinimum
// ---------------------------------------------------------------------------
contract MockSwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    uint256 public lastAmountOutMinimum;
    uint256 public realizedOut;

    function setRealizedOut(uint256 _realizedOut) external { realizedOut = _realizedOut; }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256) {
        lastAmountOutMinimum = params.amountOutMinimum;

        // Pull amountIn from caller
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Enforce slippage floor the same way a real V3 router would
        require(realizedOut >= params.amountOutMinimum, "Too little received");

        // Pay out OLAS
        MockERC20(params.tokenOut).transfer(params.recipient, realizedOut);
        return realizedOut;
    }
}

// ---------------------------------------------------------------------------
// Test — V3 path amountOutMinimum is TWAP-derived and honors mapTokenMaxSlippages
// ---------------------------------------------------------------------------
/// @dev Unit tests for the H-02 fix: V3 `_performSwap` no longer uses amountOutMinimum = 1.
///      Run: forge test --mc BuyBackBurnerV3Swap -vvv
contract BuyBackBurnerV3SwapTest is Test {
    uint256 internal constant MAX_BPS = 10_000;
    uint24 internal constant FEE_TIER = 3000;

    MockERC20 internal olas;
    MockERC20 internal secondToken;
    MockFactory internal factory;
    MockLiquidityManager internal lm;
    MockSwapRouterV3 internal router;
    BuyBackBurnerUniswap internal bbb;
    address internal pool = address(0xBEEF);
    address internal bridge2Burner = address(0xB10B);
    address internal treasury = address(0x7157);

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS");
        secondToken = new MockERC20("Token", "TK");
        factory = new MockFactory();
        factory.setPool(pool);
        lm = new MockLiquidityManager(address(factory));
        router = new MockSwapRouterV3();

        // Deploy implementation + proxy
        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(address(lm), bridge2Burner, treasury, address(router));
        address[] memory accounts = new address[](4);
        accounts[0] = address(olas);
        accounts[1] = address(secondToken);
        accounts[2] = address(0);                    // oracle (unused on V3 path)
        accounts[3] = address(0xDEAD);               // V2 router — unused here
        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));

        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        bbb = BuyBackBurnerUniswap(payable(address(proxy)));

        // Whitelist the V3 pool
        address[] memory pools = new address[](1);
        pools[0] = pool;
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        bbb.setV3PoolStatuses(pools, statuses);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// @dev Recomputes the expected amountOutMin off-chain the same way the contract does on-chain.
    function _expectedAmountOutMin(
        uint160 centerSqrtPriceX96,
        uint256 amountIn,
        bool olasIsToken1,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        uint256 priceX128 =
            FixedPointMathLib.mulDivDown(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), 1 << 64);
        uint256 quote = olasIsToken1
            ? FixedPointMathLib.mulDivDown(amountIn, priceX128, 1 << 128)
            : FixedPointMathLib.mulDivDown(amountIn, 1 << 128, priceX128);
        return FixedPointMathLib.mulDivDown(quote, MAX_BPS - slippageBps, MAX_BPS);
    }

    /// @dev Programs per-token slippage on BBB and funds the router with OLAS to pay out.
    function _prepareSwap(uint256 slippageBps, uint256 realizedOut) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(secondToken);
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = slippageBps;
        bbb.setMaxSlippages(tokens, slippages);

        secondToken.mint(address(bbb), 1e18);
        olas.mint(address(router), realizedOut);
        router.setRealizedOut(realizedOut);
    }

    // -----------------------------------------------------------------------
    // amountOutMinimum is TWAP-derived — olas = token1 branch
    // -----------------------------------------------------------------------

    /// @dev secondToken < olas → olas = token1 → amountOut = amountIn * priceX128 / 2^128.
    ///      Pick a TWAP that puts secondToken ahead of olas address-wise.
    function test_amountOutMinimum_TWAPDerived_OLASIsToken1() public {
        // Only proceed when address(secondToken) < address(olas); setUp's deterministic contract
        // deployment should give secondToken the lower address, but assert to make it explicit.
        require(address(secondToken) < address(olas), "setup assumption: secondToken < olas");

        // TWAP tick = 0 → 1:1 price → sqrtPriceX96 = 2^96
        uint160 centerSqrt = TickMath.getSqrtRatioAtTick(0);
        lm.setCenterSqrtPriceX96(centerSqrt);

        uint256 slippage = 500;                      // 5%
        uint256 amountIn = 1e18;
        uint256 expectedMin = _expectedAmountOutMin(centerSqrt, amountIn, true, slippage);

        // Realized output == expected minimum (swap passes by a hair)
        _prepareSwap(slippage, expectedMin);

        bbb.buyBack(address(secondToken), amountIn, int24(int256(uint256(FEE_TIER))), 0);

        assertEq(router.lastAmountOutMinimum(), expectedMin, "amountOutMin must match TWAP quote x slippage");
    }

    // -----------------------------------------------------------------------
    // amountOutMinimum is TWAP-derived — olas = token0 branch
    // -----------------------------------------------------------------------

    /// @dev Flip ordering by deploying until address(olas) < address(secondToken), covering the
    ///      `olas == tokens[0]` branch in _buyOLAS.
    function test_amountOutMinimum_TWAPDerived_OLASIsToken0() public {
        // Deploy fresh tokens until we land on address(olas) < address(secondToken).
        // Nonce-based addresses are deterministic but depend on deployment order;
        // loop until we have the ordering we want (bounded to avoid flaky tests).
        MockERC20 olasFlipped;
        MockERC20 tokenFlipped;
        while (true) {
            olasFlipped = new MockERC20("OLAS", "OLAS");
            tokenFlipped = new MockERC20("TK", "TK");
            if (address(olasFlipped) < address(tokenFlipped)) break;
        }

        // Rebuild BBB stack pointing at the flipped pair
        MockSwapRouterV3 flippedRouter = new MockSwapRouterV3();
        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(address(lm), bridge2Burner, treasury, address(flippedRouter));
        address[] memory accounts = new address[](4);
        accounts[0] = address(olasFlipped);
        accounts[1] = address(tokenFlipped);
        accounts[2] = address(0);
        accounts[3] = address(0xDEAD);
        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        BuyBackBurnerUniswap localBbb = BuyBackBurnerUniswap(payable(address(proxy)));

        address[] memory pools = new address[](1);
        pools[0] = pool;
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        localBbb.setV3PoolStatuses(pools, statuses);

        uint160 centerSqrt = TickMath.getSqrtRatioAtTick(0);
        lm.setCenterSqrtPriceX96(centerSqrt);

        uint256 slippage = 1000;                     // 10%
        uint256 amountIn = 1e18;
        uint256 expectedMin = _expectedAmountOutMin(centerSqrt, amountIn, false, slippage);

        // Fund
        address[] memory slipTokens = new address[](1);
        slipTokens[0] = address(tokenFlipped);
        uint256[] memory slipValues = new uint256[](1);
        slipValues[0] = slippage;
        localBbb.setMaxSlippages(slipTokens, slipValues);

        tokenFlipped.mint(address(localBbb), amountIn);
        olasFlipped.mint(address(flippedRouter), expectedMin);
        flippedRouter.setRealizedOut(expectedMin);

        localBbb.buyBack(address(tokenFlipped), amountIn, int24(int256(uint256(FEE_TIER))), 0);

        assertEq(flippedRouter.lastAmountOutMinimum(), expectedMin, "amountOutMin must match TWAP quote x slippage");
    }

    // -----------------------------------------------------------------------
    // Realized output below amountOutMinimum → router reverts, buyBack bubbles up
    // -----------------------------------------------------------------------

    function test_buyBack_revertsWhenRouterShortfall() public {
        uint160 centerSqrt = TickMath.getSqrtRatioAtTick(0);
        lm.setCenterSqrtPriceX96(centerSqrt);

        uint256 slippage = 100;                      // 1% — tight
        uint256 amountIn = 1e18;
        uint256 expectedMin = _expectedAmountOutMin(centerSqrt, amountIn, true, slippage);

        // Realized output is 1 wei below the minimum
        _prepareSwap(slippage, expectedMin - 1);

        vm.expectRevert(bytes("Too little received"));
        bbb.buyBack(address(secondToken), amountIn, int24(int256(uint256(FEE_TIER))), 0);
    }

    // -----------------------------------------------------------------------
    // Unconfigured per-token slippage → amountOutMin == full TWAP quote
    // (router reverts unless it matches the TWAP exactly; the point is the gate engages)
    // -----------------------------------------------------------------------

    function test_unsetSlippage_yieldsFullTwapQuoteAsFloor() public {
        uint160 centerSqrt = TickMath.getSqrtRatioAtTick(0);
        lm.setCenterSqrtPriceX96(centerSqrt);

        uint256 amountIn = 1e18;
        uint256 fullQuote = _expectedAmountOutMin(centerSqrt, amountIn, true, 0);

        // Don't call setMaxSlippages — mapTokenMaxSlippages[secondToken] stays 0
        secondToken.mint(address(bbb), amountIn);
        olas.mint(address(router), fullQuote);
        router.setRealizedOut(fullQuote);

        bbb.buyBack(address(secondToken), amountIn, int24(int256(uint256(FEE_TIER))), 0);

        assertEq(router.lastAmountOutMinimum(), fullQuote, "unset slippage -> amountOutMin = full TWAP quote");
    }

    // -----------------------------------------------------------------------
    // Unwhitelisted pool → UnauthorizedPool revert (slippage guard is unreachable
    // unless the pool passes the whitelist)
    // -----------------------------------------------------------------------

    function test_unwhitelistedPool_reverts() public {
        // Re-point factory at a different address that BBB has NOT whitelisted
        factory.setPool(address(0xCAFE));

        uint160 centerSqrt = TickMath.getSqrtRatioAtTick(0);
        lm.setCenterSqrtPriceX96(centerSqrt);

        secondToken.mint(address(bbb), 1e18);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedPool.selector, address(0xCAFE)));
        bbb.buyBack(address(secondToken), 1e18, int24(int256(uint256(FEE_TIER))), 0);
    }
}
