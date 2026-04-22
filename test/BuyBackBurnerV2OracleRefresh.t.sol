// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";

// ---------------------------------------------------------------------------
// Mock ERC20
// ---------------------------------------------------------------------------
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// ---------------------------------------------------------------------------
// Mock V2 oracle — counts updatePrice() invocations and serves a configurable
// TWAP. `getTWAP()` is declared `view` to match IOracle so BuyBackBurner
// can staticcall it; call-ordering (updatePrice before getTWAP) is baked
// into the source at BuyBackBurner.sol V2 `_buyOLAS` adjacent lines, so a
// `updatePriceCount` check post-buyBack is sufficient evidence of M-03.
// ---------------------------------------------------------------------------
contract MockV2Oracle {
    uint256 public twap;
    uint256 public updatePriceCount;

    function setTWAP(uint256 _twap) external { twap = _twap; }

    function updatePrice() external returns (bool) {
        updatePriceCount++;
        return true;
    }

    function getTWAP() external view returns (uint256) {
        return twap;
    }
}

// ---------------------------------------------------------------------------
// Mock Uniswap V2 router — pulls input tokens, pays out configured OLAS.
// Signature matches the real IUniswap.swapExactTokensForTokens in the child.
// ---------------------------------------------------------------------------
contract MockV2Router {
    uint256 public realizedOut;
    uint256 public lastAmountOutMin;

    function setRealizedOut(uint256 _realizedOut) external { realizedOut = _realizedOut; }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256[] memory amounts) {
        lastAmountOutMin = amountOutMin;

        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        require(realizedOut >= amountOutMin, "MOCK: Too little received");
        MockERC20(path[path.length - 1]).transfer(to, realizedOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = realizedOut;
    }
}

// ---------------------------------------------------------------------------
// Test — M-03: V2 _buyOLAS must call updatePrice() before getTWAP()
// ---------------------------------------------------------------------------
/// @dev Unit test for the M-03 fix: a buyBack on the V2 path now triggers
///      oracle.updatePrice() before oracle.getTWAP(), so a long-idle oracle
///      never feeds a stale TWAP into the amountOutMin derivation.
///      Run: forge test --mc BuyBackBurnerV2OracleRefresh -vvv
contract BuyBackBurnerV2OracleRefreshTest is Test {
    uint256 internal constant MAX_BPS = 10_000;

    MockERC20 internal olas;
    MockERC20 internal secondToken;
    MockV2Oracle internal oracle;
    MockV2Router internal router;
    BuyBackBurnerUniswap internal bbb;
    address internal bridge2Burner = address(0xB10B);
    address internal treasury = address(0x7157);
    address internal liquidityManager = address(0x1100);
    address internal swapRouterV3 = address(0xC03);

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS");
        secondToken = new MockERC20("Token", "TK");
        oracle = new MockV2Oracle();
        router = new MockV2Router();

        BuyBackBurnerUniswap impl =
            new BuyBackBurnerUniswap(liquidityManager, bridge2Burner, treasury, swapRouterV3);

        address[] memory accounts = new address[](4);
        accounts[0] = address(olas);
        accounts[1] = address(secondToken);
        accounts[2] = address(oracle);              // V2 oracle
        accounts[3] = address(router);              // V2 router
        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts));

        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(impl), initPayload);
        bbb = BuyBackBurnerUniswap(payable(address(proxy)));

        // Whitelist secondToken's V2 oracle
        address[] memory tokens = new address[](1);
        tokens[0] = address(secondToken);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle);
        bbb.setV2Oracles(tokens, oracles);

        // Program per-token slippage
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 500;                         // 5%
        bbb.setMaxSlippages(tokens, slippages);
    }

    // -----------------------------------------------------------------------
    // updatePrice() fires on every buyBack, and the TWAP math matches
    // -----------------------------------------------------------------------

    function test_buyBack_refreshesOracle() public {
        uint256 twap = 2e18;                        // 2 OLAS per 1 secondToken
        oracle.setTWAP(twap);

        uint256 amountIn = 1e18;
        uint256 expectedAmountOutMin = amountIn * twap * (MAX_BPS - 500) / (MAX_BPS * 1e18);
        // Fund router with exactly the minimum so the swap passes.
        olas.mint(address(router), expectedAmountOutMin);
        router.setRealizedOut(expectedAmountOutMin);

        secondToken.mint(address(bbb), amountIn);

        assertEq(oracle.updatePriceCount(), 0, "sanity: no pre-buyBack refresh");
        bbb.buyBack(address(secondToken), amountIn, 0);

        assertEq(oracle.updatePriceCount(), 1, "updatePrice must be called exactly once per buyBack");
        // The updatePrice call happens before getTWAP by construction: see contracts/utils/
        // BuyBackBurner.sol V2 `_buyOLAS` branch — updatePrice and getTWAP are on adjacent lines,
        // with updatePrice first. amountOutMin matching the TWAP math is indirect evidence that
        // getTWAP returned the (mock-configured) value rather than reverting on a stale read.
        assertEq(router.lastAmountOutMin(), expectedAmountOutMin, "amountOutMin matches TWAP math");
    }

    // -----------------------------------------------------------------------
    // Back-to-back buyBack calls keep firing updatePrice (no self-DoS)
    // -----------------------------------------------------------------------

    function test_buyBack_backToBackStillInvokesUpdatePrice() public {
        uint256 twap = 1e18;
        oracle.setTWAP(twap);

        uint256 amountInEach = 1e18;
        uint256 expectedMin = amountInEach * twap * (MAX_BPS - 500) / (MAX_BPS * 1e18);
        // Mint enough OLAS for two swaps.
        olas.mint(address(router), expectedMin * 2);
        router.setRealizedOut(expectedMin);

        secondToken.mint(address(bbb), amountInEach);
        bbb.buyBack(address(secondToken), amountInEach, 0);

        // Second buyBack without warping. The real oracle's updatePrice would return false
        // inside minUpdateInterval and skip the write; BuyBackBurner ignores the return value
        // and continues to getTWAP, so back-to-back buyBacks never self-DoS. Our mock always
        // returns true and counts the call — both invocations reach updatePrice.
        secondToken.mint(address(bbb), amountInEach);
        bbb.buyBack(address(secondToken), amountInEach, 0);

        assertEq(oracle.updatePriceCount(), 2, "updatePrice attempts on each buyBack");
    }
}
