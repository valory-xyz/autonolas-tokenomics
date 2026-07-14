// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LiquidityManagerCore, ZeroValue} from "../contracts/pol/LiquidityManagerCore.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";
import {IPositionManagerV3} from "../contracts/interfaces/IPositionManagerV3.sol";
import {MockERC20} from "../lib/solmate/src/test/utils/mocks/MockERC20.sol";

// ---------------------------------------------------------------------------
// Mock position manager: factory() for the LM constructor, collect() that pays the recipient the
// configured fees (as the real NPM does), positions() exposing a configurable liquidity, and
// decreaseLiquidity() that records the owner-supplied minimums it was called with.
// ---------------------------------------------------------------------------
contract MockNPM {
    address public factoryAddr;
    MockERC20 public token0;
    MockERC20 public token1;
    uint256 public fee0;
    uint256 public fee1;
    uint128 public posLiquidity;

    // Recorded from the last decreaseLiquidity call
    uint128 public lastDecreaseLiquidity;
    uint256 public lastMinAmount0;
    uint256 public lastMinAmount1;

    constructor(address _factory, MockERC20 _t0, MockERC20 _t1) {
        factoryAddr = _factory;
        token0 = _t0;
        token1 = _t1;
    }

    function factory() external view returns (address) {
        return factoryAddr;
    }

    function setFees(uint256 _f0, uint256 _f1) external {
        fee0 = _f0;
        fee1 = _f1;
    }

    function setTokens(MockERC20 _t0, MockERC20 _t1) external {
        token0 = _t0;
        token1 = _t1;
    }

    function setLiquidity(uint128 _l) external {
        posLiquidity = _l;
    }

    function collect(IUniswapV3.CollectParams calldata params) external returns (uint256, uint256) {
        // Pay the recipient the collected fees, mirroring the real position manager.
        if (fee0 > 0) token0.mint(params.recipient, fee0);
        if (fee1 > 0) token1.mint(params.recipient, fee1);
        return (fee0, fee1);
    }

    function positions(uint256)
        external
        view
        returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
    {
        return (0, address(0), address(token0), address(token1), 0, int24(-100), int24(100), posLiquidity, 0, 0, 0, 0);
    }

    function decreaseLiquidity(IPositionManagerV3.DecreaseLiquidityParams calldata params)
        external
        returns (uint256, uint256)
    {
        lastDecreaseLiquidity = params.liquidity;
        lastMinAmount0 = params.amount0Min;
        lastMinAmount1 = params.amount1Min;
        // No token payout needed for these assertions.
        return (0, 0);
    }
}

/// @dev Concrete LiquidityManagerCore harness. `_getV3Pool` returns a configurable pool, `setPositionId`
///      seeds the pool->position map, and `_burn` actually removes OLAS from the contract's balance so a
///      burn is distinguishable from a transfer.
contract Harness is LiquidityManagerCore {
    address public poolAddr;
    MockERC20 public immutable olasToken;

    constructor(address _pm, address _scanner, address _olas, address _treasury)
        LiquidityManagerCore(_olas, _treasury, _pm, _scanner, 1)
    {
        olasToken = MockERC20(_olas);
    }

    function setPool(address p) external {
        poolAddr = p;
    }

    function setPositionId(address p, uint256 id) external {
        mapPoolAddressPositionIds[p] = id;
    }

    function _getV3Pool(address[] memory, int24) internal view override returns (address) {
        return poolAddr;
    }

    function _burn(uint256 amount) internal override {
        olasToken.burn(address(this), amount);
    }

    function _checkTokensAndRemoveLiquidityV2(address[] memory, bytes32)
        internal
        override
        returns (uint256[] memory a)
    {
        a = new uint256[](2);
    }

    function _feeAmountTickSpacing(int24 f) internal pure override returns (int24) {
        return f;
    }

    function _mintV3(address[] memory, uint256[] memory, uint256[] memory, int24[] memory, int24, uint160)
        internal
        override
        returns (uint256, uint128, uint256[] memory)
    {
        return (0, 0, new uint256[](2));
    }
}

/// @dev Unit tests for FIX-3 (collectFees scoped burn, VL#15 → T4/T11): collectFees burns/forwards only
///      the just-collected amounts, leaving separately-staged balances untouched, in both token orderings.
///      (decreaseLiquidity's soft-priced exit floor is covered by LiquidityManagerCorePriceGuard.t.sol
///      and the fork suites.)
///      Run: forge test --mc LiquidityManagerCoreCollectDecrease -vvv
contract LiquidityManagerCoreCollectDecreaseTest is Test {
    MockERC20 internal olas;
    MockERC20 internal weth;
    MockNPM internal npm;
    Harness internal lm;

    address internal constant TREASURY = address(0x7EA5);
    address internal constant POOL = address(0xB00);

    function setUp() public {
        olas = new MockERC20("OLAS", "OLAS", 18);
        weth = new MockERC20("WETH", "WETH", 18);
        npm = new MockNPM(address(0xF), olas, weth);
        // scanner just needs to be non-zero; it is never called in these tests
        lm = new Harness(address(npm), address(0x5CA), address(olas), TREASURY);
        lm.setPool(POOL);
        lm.setPositionId(POOL, 42);
        // owner + maxSlippage (decreaseLiquidity is onlyOwner; collectFees is permissionless)
        lm.initialize(1000);
    }

    function _tokens() internal view returns (address[] memory t) {
        t = new address[](2);
        t[0] = address(olas);
        t[1] = address(weth);
    }

    // -----------------------------------------------------------------------
    // T4 / T11 — collectFees burns/forwards ONLY the just-collected fees
    // -----------------------------------------------------------------------

    /// @dev Stage extra OLAS + WETH on the contract (as if pre-funded for a pending convertToV3), then
    ///      collect fees. Only the collected OLAS is burned and only the collected WETH is forwarded to
    ///      treasury; the staged balances are untouched. On the pre-fix code both staged balances would
    ///      have been swept, since it operated on balanceOf.
    function test_collectFees_scopesToCollectedAmounts_leavesStagedUntouched() public {
        uint256 stagedOlas = 1_000e18;
        uint256 stagedWeth = 5e18;
        uint256 feeOlas = 30e18;
        uint256 feeWeth = 1e18;

        olas.mint(address(lm), stagedOlas);
        weth.mint(address(lm), stagedWeth);
        npm.setFees(feeOlas, feeWeth);

        uint256 olasSupplyBefore = olas.totalSupply(); // == stagedOlas

        lm.collectFees(_tokens(), int24(3000));

        // OLAS: collected fee minted in then burned out → staged remains, net supply unchanged
        assertEq(olas.balanceOf(address(lm)), stagedOlas, "staged OLAS must be untouched");
        assertEq(olas.totalSupply(), olasSupplyBefore, "only the collected OLAS is burned");

        // WETH: staged remains on the contract, only the collected fee is forwarded to treasury
        assertEq(weth.balanceOf(address(lm)), stagedWeth, "staged WETH must be untouched");
        assertEq(weth.balanceOf(TREASURY), feeWeth, "only the collected WETH is sent to treasury");
    }

    /// @dev Same scoping holds when OLAS is token1 rather than token0.
    function test_collectFees_scopes_whenOlasIsToken1() public {
        uint256 stagedOlas = 2_000e18;
        uint256 feeOlas = 10e18;
        uint256 feeWeth = 2e18;

        olas.mint(address(lm), stagedOlas);
        // Pool ordering where OLAS is token1: token0 = weth, token1 = olas; fees line up positionally
        npm.setTokens(weth, olas);
        npm.setFees(feeWeth, feeOlas); // fee0 -> weth, fee1 -> olas

        address[] memory t = new address[](2);
        t[0] = address(weth);
        t[1] = address(olas);

        uint256 olasSupplyBefore = olas.totalSupply();
        lm.collectFees(t, int24(3000));

        assertEq(olas.balanceOf(address(lm)), stagedOlas, "staged OLAS untouched (olas as token1)");
        assertEq(olas.totalSupply(), olasSupplyBefore, "only collected OLAS burned (olas as token1)");
        assertEq(weth.balanceOf(TREASURY), feeWeth, "only collected WETH forwarded");
    }

    // decreaseLiquidity now derives its slippage floor at execution from a soft-priced fair value
    // (_getExitSqrtPrice: TWAP when verifiable, else slot0). That soft gate is unit-tested in
    // LiquidityManagerCorePriceGuard.t.sol (which has a mock pool), and the end-to-end decrease is
    // covered by the ETH/Base fork suites.
}
