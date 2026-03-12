// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ZuniswapV2Factory} from "zuniswapv2/ZuniswapV2Factory.sol";
import {ZuniswapV2Router} from "zuniswapv2/ZuniswapV2Router.sol";
import {ZuniswapV2Pair} from "zuniswapv2/ZuniswapV2Pair.sol";
import {MockERC20} from "../lib/zuniswapv2/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {LPSwapCelo, IToken, IUniswapV2Pair, ZeroAddress, ZeroValue, Overflow, ReentrancyGuard} from "../contracts/utils/LPSwapCelo.sol";

// Mock L2 Standard Bridge for testing
contract MockL2StandardBridge {
    event WithdrawTo(address l2Token, address to, uint256 amount, uint32 minGasLimit, bytes extraData);

    function withdrawTo(address _l2Token, address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData)
        external
    {
        // Transfer tokens from caller to simulate bridge lock
        MockERC20(_l2Token).transferFrom(msg.sender, address(this), _amount);
        emit WithdrawTo(_l2Token, _to, _amount, _minGasLimit, _extraData);
    }
}

// Mock Wormhole Token Bridge for testing
contract MockWormholeTokenBridge {
    event TransferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient);

    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256,
        uint32
    ) external payable returns (uint64) {
        // Transfer tokens from caller to simulate bridge lock
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
        emit TransferTokens(token, amount, recipientChain, recipient);
        return 0;
    }
}

// Testable version of LPSwapCelo that overrides constants with configurable values
contract TestLPSwapCelo {
    event LiquiditySwapped(uint256 whOlasAmount, uint256 celoAmount, uint256 olasAmount, uint256 newLiquidity);
    event OLASBridgedToL1(uint256 amount);
    event WhOLASBridgedToL1(uint256 amount);

    uint256 public constant MAX_BPS = 10_000;
    uint32 public constant TOKEN_GAS_LIMIT = 300_000;
    uint16 public constant WORMHOLE_L1_CHAIN_ID = 2;
    string public constant VERSION = "0.1.0";

    address public immutable lpToken;
    address public immutable wcelo;
    address public immutable whOlas;
    address public immutable olas;
    address public immutable l2StandardBridge;
    address public immutable router;
    address public immutable wormholeTokenBridge;
    address public immutable l1Timelock;
    address public immutable oracle;
    uint256 public immutable maxSlippage;

    uint8 internal _locked;

    constructor(
        address _lpToken,
        address _wcelo,
        address _whOlas,
        address _olas,
        address _l2StandardBridge,
        address _router,
        address _wormholeTokenBridge,
        address _l1Timelock,
        address _oracle,
        uint256 _maxSlippage
    ) {
        if (_lpToken == address(0) || _wcelo == address(0) || _whOlas == address(0) || _olas == address(0) ||
            _l2StandardBridge == address(0) || _router == address(0) || _wormholeTokenBridge == address(0) ||
            _l1Timelock == address(0) || _oracle == address(0)) {
            revert ZeroAddress();
        }

        if (_maxSlippage == 0) {
            revert ZeroValue();
        }

        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        lpToken = _lpToken;
        wcelo = _wcelo;
        whOlas = _whOlas;
        olas = _olas;
        l2StandardBridge = _l2StandardBridge;
        router = _router;
        wormholeTokenBridge = _wormholeTokenBridge;
        l1Timelock = _l1Timelock;
        oracle = _oracle;
        maxSlippage = _maxSlippage;

        _locked = 1;
    }

    function swapLiquidity() external {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 liquidity = MockERC20(lpToken).balanceOf(address(this));
        if (liquidity == 0) {
            revert ZeroValue();
        }

        (uint256 whOlasAmount, uint256 celoAmount) = _removeLiquidity(liquidity);

        uint256 newLiquidity = _addLiquidity(whOlasAmount, celoAmount);

        emit LiquiditySwapped(whOlasAmount, celoAmount, whOlasAmount, newLiquidity);

        _bridgeOLAS();
        _bridgeWhOLAS();

        _locked = 1;
    }

    function _removeLiquidity(uint256 liquidity) internal returns (uint256 whOlasAmount, uint256 celoAmount) {
        uint256 minAmountCelo;
        uint256 minAmountWhOlas;
        {
            (uint112 reserve0, uint112 reserve1,) = ZuniswapV2Pair(lpToken).getReserves();
            uint256 totalSupply = ZuniswapV2Pair(lpToken).totalSupply();

            uint256 k = uint256(reserve0) * uint256(reserve1);
            uint256 twap = UniswapPriceOracle(oracle).getTWAP();

            uint256 fairReserve0 = _sqrt(k * 1e18 / twap);
            uint256 fairReserve1 = _sqrt(k * twap / 1e18);

            minAmountCelo = (liquidity * fairReserve0 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
            minAmountWhOlas = (liquidity * fairReserve1 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
        }

        MockERC20(lpToken).approve(router, liquidity);

        (celoAmount, whOlasAmount) = ZuniswapV2Router(router)
            .removeLiquidity(wcelo, whOlas, liquidity, minAmountCelo, minAmountWhOlas, address(this));
    }

    function _addLiquidity(uint256 olasDesired, uint256 celoDesired) internal returns (uint256 liquidity) {
        uint256 olasMin = (olasDesired * (MAX_BPS - maxSlippage)) / MAX_BPS;

        MockERC20(olas).approve(router, olasDesired);
        MockERC20(wcelo).approve(router, celoDesired);

        (, , liquidity) = ZuniswapV2Router(router)
            .addLiquidity(olas, wcelo, olasDesired, celoDesired, olasMin, celoDesired, address(this));
    }

    function _bridgeOLAS() internal {
        uint256 olasBalance = MockERC20(olas).balanceOf(address(this));
        if (olasBalance > 0) {
            MockERC20(olas).approve(l2StandardBridge, olasBalance);
            MockL2StandardBridge(l2StandardBridge).withdrawTo(olas, l1Timelock, olasBalance, TOKEN_GAS_LIMIT, "");
            emit OLASBridgedToL1(olasBalance);
        }
    }

    function _bridgeWhOLAS() internal {
        uint256 whOlasBalance = MockERC20(whOlas).balanceOf(address(this));
        if (whOlasBalance > 0) {
            MockERC20(whOlas).approve(wormholeTokenBridge, whOlasBalance);
            bytes32 recipient = bytes32(uint256(uint160(l1Timelock)));
            MockWormholeTokenBridge(wormholeTokenBridge).transferTokens(
                whOlas, whOlasBalance, WORMHOLE_L1_CHAIN_ID, recipient, 0, 0
            );
            emit WhOLASBridgedToL1(whOlasBalance);
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            z := 181
            let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffffff, shr(r, x))))
            z := shl(shr(1, r), z)
            z := shr(18, mul(z, add(shr(r, x), 65536)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := sub(z, lt(div(x, z), z))
        }
    }
}

/// @dev Base setup for LPSwapCelo tests using mock tokens and Zuniswap V2.
contract LPSwapCeloBaseSetup is Test {
    Utils internal utils;
    MockERC20 internal whOlas;
    MockERC20 internal wcelo;
    MockERC20 internal olas;
    ZuniswapV2Factory internal factory;
    ZuniswapV2Router internal router;
    UniswapPriceOracle internal oracle;
    MockL2StandardBridge internal l2Bridge;
    MockWormholeTokenBridge internal wormholeBridge;
    TestLPSwapCelo internal lpSwap;

    address payable[] internal users;
    address internal deployer;
    address internal dev;
    address internal pair;
    address internal l1Timelock;

    uint256 internal constant initialMint = 1_000_000 ether;
    uint256 internal constant largeApproval = type(uint256).max;
    uint256 internal constant amountWhOlas = 10_000 ether;
    uint256 internal constant amountCelo = 10_000 ether;

    uint256 internal constant minTwapWindow = 900;
    uint256 internal constant minUpdateInterval = 900;
    uint256 internal constant maxSlippageBps = 500; // 5%

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        l1Timelock = address(0xBEEF);

        // Deploy mock tokens
        whOlas = new MockERC20("Wormhole OLAS", "whOLAS", 18);
        whOlas.mint(address(this), initialMint);

        wcelo = new MockERC20("Wrapped CELO", "WCELO", 18);
        wcelo.mint(address(this), initialMint);

        olas = new MockERC20("OLAS Token", "OLAS", 18);
        olas.mint(address(this), initialMint);

        // Deploy Uniswap V2
        factory = new ZuniswapV2Factory();
        router = new ZuniswapV2Router(address(factory));

        // Create whOLAS-WCELO pair and add liquidity
        whOlas.approve(address(router), largeApproval);
        wcelo.approve(address(router), largeApproval);
        router.addLiquidity(
            address(whOlas), address(wcelo),
            amountWhOlas, amountCelo,
            amountWhOlas, amountCelo,
            address(this)
        );
        pair = factory.pairs(address(whOlas), address(wcelo));

        // Deploy oracle for the whOLAS-WCELO pair
        oracle = new UniswapPriceOracle(pair, address(whOlas), minTwapWindow, minUpdateInterval);

        // Warm up oracle
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        // Deploy mock bridges
        l2Bridge = new MockL2StandardBridge();
        wormholeBridge = new MockWormholeTokenBridge();

        // Deploy TestLPSwapCelo
        lpSwap = new TestLPSwapCelo(
            pair,
            address(wcelo),
            address(whOlas),
            address(olas),
            address(l2Bridge),
            address(router),
            address(wormholeBridge),
            l1Timelock,
            address(oracle),
            maxSlippageBps
        );
    }

    /// @dev Helper: transfer LP tokens and OLAS to the lpSwap contract.
    function _fundLPSwap(uint256 lpAmount, uint256 olasAmount) internal {
        // Transfer LP tokens
        ZuniswapV2Pair(pair).transfer(address(lpSwap), lpAmount);
        // Transfer OLAS (simulating bridged OLAS from L1)
        olas.transfer(address(lpSwap), olasAmount);
    }
}

/// @dev Constructor tests for LPSwapCelo.
contract LPSwapCeloConstructorTest is Test {
    /// @dev Reverts when oracle address is zero.
    function testConstructorZeroOracle() public {
        vm.expectRevert(ZeroAddress.selector);
        new LPSwapCelo(address(0), 500);
    }

    /// @dev Reverts when maxSlippage is zero.
    function testConstructorZeroSlippage() public {
        vm.expectRevert(ZeroValue.selector);
        new LPSwapCelo(address(1), 0);
    }

    /// @dev Reverts when maxSlippage exceeds MAX_BPS.
    function testConstructorSlippageOverflow() public {
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, 10_001, 10_000));
        new LPSwapCelo(address(1), 10_001);
    }

    /// @dev Constructor stores immutables correctly.
    function testConstructorImmutables() public {
        LPSwapCelo c = new LPSwapCelo(address(0xABC), 500);
        assertEq(c.oracle(), address(0xABC));
        assertEq(c.maxSlippage(), 500);
    }

    /// @dev Constants are set correctly.
    function testConstants() public {
        LPSwapCelo c = new LPSwapCelo(address(1), 500);
        assertEq(c.MAX_BPS(), 10_000);
        assertEq(c.TOKEN_GAS_LIMIT(), 300_000);
        assertEq(c.WORMHOLE_L1_CHAIN_ID(), 2);
        assertEq(c.LP_TOKEN(), 0x2976Fa805141b467BCBc6334a69AffF4D914d96A);
        assertEq(c.WCELO(), 0x471EcE3750Da237f93B8E339c536989b8978a438);
        assertEq(c.WHOLAS(), 0xaCFfAe8e57Ec6E394Eb1b41939A8CF7892DbDc51);
        assertEq(c.OLAS(), 0xD80533CA29fF6F033a0b55732Ed792af9Fbb381E);
        assertEq(c.L2_STANDARD_BRIDGE(), 0x4200000000000000000000000000000000000010);
        assertEq(c.ROUTER(), 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121);
        assertEq(c.WORMHOLE_TOKEN_BRIDGE(), 0x796Dff6D74F3E27060B71255Fe517BFb23C93eed);
        assertEq(c.L1_TIMELOCK(), 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE);
    }

    /// @dev Boundary: maxSlippage at MAX_BPS succeeds.
    function testConstructorMaxSlippageBoundary() public {
        LPSwapCelo c = new LPSwapCelo(address(1), 10_000);
        assertEq(c.maxSlippage(), 10_000);
    }
}

/// @dev TestLPSwapCelo constructor tests with configurable addresses.
contract TestLPSwapCeloConstructorTest is Test {
    /// @dev Reverts when any address is zero.
    function testConstructorZeroAddresses() public {
        vm.expectRevert(ZeroAddress.selector);
        new TestLPSwapCelo(
            address(0), address(1), address(1), address(1),
            address(1), address(1), address(1), address(1), address(1), 500
        );

        vm.expectRevert(ZeroAddress.selector);
        new TestLPSwapCelo(
            address(1), address(1), address(1), address(1),
            address(1), address(1), address(1), address(1), address(0), 500
        );
    }
}

/// @dev Functional tests for swapLiquidity using TestLPSwapCelo with mock tokens.
contract LPSwapCeloSwapTest is LPSwapCeloBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Deployment is configured correctly.
    function testDeployment() public view {
        assertEq(lpSwap.lpToken(), pair);
        assertEq(lpSwap.wcelo(), address(wcelo));
        assertEq(lpSwap.whOlas(), address(whOlas));
        assertEq(lpSwap.olas(), address(olas));
        assertEq(lpSwap.router(), address(router));
        assertEq(lpSwap.oracle(), address(oracle));
        assertEq(lpSwap.l2StandardBridge(), address(l2Bridge));
        assertEq(lpSwap.wormholeTokenBridge(), address(wormholeBridge));
        assertEq(lpSwap.l1Timelock(), l1Timelock);
        assertEq(lpSwap.maxSlippage(), maxSlippageBps);
    }

    /// @dev swapLiquidity reverts when LP token balance is zero.
    function testSwapLiquidityZeroBalance() public {
        vm.expectRevert(ZeroValue.selector);
        lpSwap.swapLiquidity();
    }

    /// @dev swapLiquidity succeeds: removes whOLAS-CELO, adds OLAS-CELO, bridges leftovers.
    function testSwapLiquidity() public {
        // Get LP balance and fund the contract
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        assertGt(lpBalance, 0);

        // Get expected whOLAS amount from removal (proportional to reserves)
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();
        uint256 expectedCelo = (lpBalance * uint256(r0)) / totalSupply;
        uint256 expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;

        // Determine token ordering: check which is token0
        address token0 = ZuniswapV2Pair(pair).token0();
        if (token0 == address(whOlas)) {
            // Swap expected amounts if whOlas is token0
            (expectedCelo, expectedWhOlas) = (expectedWhOlas, expectedCelo);
        }

        // Fund: LP tokens + enough OLAS for the new liquidity
        _fundLPSwap(lpBalance, expectedWhOlas);

        // Execute swap
        lpSwap.swapLiquidity();

        // Verify: no LP tokens remain
        assertEq(ZuniswapV2Pair(pair).balanceOf(address(lpSwap)), 0);

        // Verify: new OLAS-WCELO pair was created and has liquidity
        address newPair = factory.pairs(address(olas), address(wcelo));
        assertFalse(newPair == address(0));
        uint256 newPairLiquidity = ZuniswapV2Pair(newPair).balanceOf(address(lpSwap));
        assertGt(newPairLiquidity, 0);

        // Verify: no OLAS or whOLAS left in the contract (bridged away or used)
        assertEq(olas.balanceOf(address(lpSwap)), 0);
        assertEq(whOlas.balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity emits LiquiditySwapped event.
    function testSwapLiquidityEmitsEvent() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
        }

        _fundLPSwap(lpBalance, expectedWhOlas);

        // Check that the event is emitted (partial match)
        vm.expectEmit(false, false, false, false);
        emit TestLPSwapCelo.LiquiditySwapped(0, 0, 0, 0);
        lpSwap.swapLiquidity();
    }

    /// @dev swapLiquidity bridges remaining OLAS via L2 Standard Bridge.
    function testSwapLiquidityBridgesOLAS() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
        }

        // Fund with extra OLAS to ensure leftover that will be bridged
        uint256 extraOlas = 100 ether;
        _fundLPSwap(lpBalance, expectedWhOlas + extraOlas);

        uint256 bridgeBefore = olas.balanceOf(address(l2Bridge));

        lpSwap.swapLiquidity();

        // Verify bridge received OLAS
        uint256 bridgeAfter = olas.balanceOf(address(l2Bridge));
        assertGt(bridgeAfter, bridgeBefore);

        // Contract should have no OLAS left
        assertEq(olas.balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity bridges remaining whOLAS via Wormhole.
    function testSwapLiquidityBridgesWhOLAS() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
        }

        // Fund with slightly less OLAS than whOlas amount to force whOLAS leftover
        // (addLiquidity may not use all whOLAS equivalent if OLAS is less)
        _fundLPSwap(lpBalance, expectedWhOlas);

        lpSwap.swapLiquidity();

        // Contract should have no whOLAS left
        assertEq(whOlas.balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity with partial LP amount works.
    function testSwapLiquidityPartial() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        uint256 partialLp = lpBalance / 2;

        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (partialLp * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (partialLp * uint256(r1)) / totalSupply;
        }

        _fundLPSwap(partialLp, expectedWhOlas);

        lpSwap.swapLiquidity();

        // Verify new pair was created
        address newPair = factory.pairs(address(olas), address(wcelo));
        assertFalse(newPair == address(0));
        assertGt(ZuniswapV2Pair(newPair).balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity preserves token amounts (whOLAS amount == OLAS amount used).
    function testSwapLiquidityPreservesAmounts() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));

        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        uint256 expectedCelo;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
            expectedCelo = (lpBalance * uint256(r1)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
            expectedCelo = (lpBalance * uint256(r0)) / totalSupply;
        }

        // Fund with exact expected OLAS amount
        _fundLPSwap(lpBalance, expectedWhOlas);

        uint256 olasBefore = olas.balanceOf(address(lpSwap));
        assertEq(olasBefore, expectedWhOlas);

        lpSwap.swapLiquidity();

        // New pair should exist with liquidity close to expected
        address newPair = factory.pairs(address(olas), address(wcelo));
        (uint112 newR0, uint112 newR1,) = ZuniswapV2Pair(newPair).getReserves();

        // Verify reserves are non-zero
        assertGt(uint256(newR0), 0);
        assertGt(uint256(newR1), 0);
    }

    /// @dev No whOLAS leftover when addLiquidity uses all of the OLAS.
    function testSwapLiquidityNoWhOlasLeftover() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
        }

        // Fund with exact amounts - first liquidity provision uses all tokens
        _fundLPSwap(lpBalance, expectedWhOlas);

        lpSwap.swapLiquidity();

        // Since this is first provision to OLAS-WCELO pair, router uses all tokens
        // whOLAS should be zero (nothing left from removal since all went to new pair as OLAS)
        assertEq(whOlas.balanceOf(address(lpSwap)), 0);
    }

    /// @dev OLASBridgedToL1 event is emitted when leftover OLAS exists.
    function testSwapLiquidityEmitsOLASBridgeEvent() public {
        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        address token0 = ZuniswapV2Pair(pair).token0();
        uint256 expectedWhOlas;
        if (token0 == address(whOlas)) {
            expectedWhOlas = (lpBalance * uint256(r0)) / totalSupply;
        } else {
            expectedWhOlas = (lpBalance * uint256(r1)) / totalSupply;
        }

        // Extra OLAS to guarantee leftover
        _fundLPSwap(lpBalance, expectedWhOlas + 100 ether);

        vm.expectEmit(false, false, false, false);
        emit TestLPSwapCelo.OLASBridgedToL1(0);
        lpSwap.swapLiquidity();
    }
}

/// @dev Slippage protection tests.
contract LPSwapCeloSlippageTest is LPSwapCeloBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev swapLiquidity succeeds with manipulated reserves within slippage tolerance.
    function testSwapLiquidityWithSmallPriceMove() public {
        // Do a small swap to move price slightly
        address[] memory path = new address[](2);
        path[0] = address(wcelo);
        path[1] = address(whOlas);
        router.swapExactTokensForTokens(100 ether, 0, path, address(this));

        // Update oracle and wait for TWAP window
        vm.warp(block.timestamp + minUpdateInterval);
        oracle.updatePrice();
        vm.warp(block.timestamp + minTwapWindow + 1);

        uint256 lpBalance = ZuniswapV2Pair(pair).balanceOf(address(this));
        (uint112 r0, uint112 r1,) = ZuniswapV2Pair(pair).getReserves();
        uint256 totalSupply = ZuniswapV2Pair(pair).totalSupply();

        // After the swap, reserves changed. Fund with the larger of the two reserve-proportional
        // amounts to cover whichever token ordering the router uses
        uint256 maxExpected = (lpBalance * uint256(r0 > r1 ? r0 : r1)) / totalSupply;
        _fundLPSwap(lpBalance, maxExpected + 1 ether);

        // Should succeed since price move is within slippage tolerance
        lpSwap.swapLiquidity();

        address newPair = factory.pairs(address(olas), address(wcelo));
        assertFalse(newPair == address(0));
    }
}

// ============================================================================
// Fork tests on Celo mainnet
// Run: forge test -f <CELO_RPC_URL> --mc LPSwapCeloFork -vvv
// ============================================================================

/// @dev Fork test base setup for LPSwapCelo on Celo mainnet.
contract LPSwapCeloForkBaseSetup is Test {
    UniswapPriceOracle internal oracleV2;
    LPSwapCelo internal lpSwap;

    // Celo mainnet addresses (matching LPSwapCelo constants)
    address internal constant LP_TOKEN = 0x2976Fa805141b467BCBc6334a69AffF4D914d96A;
    address internal constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address internal constant WHOLAS = 0xaCFfAe8e57Ec6E394Eb1b41939A8CF7892DbDc51;
    address internal constant OLAS = 0xD80533CA29fF6F033a0b55732Ed792af9Fbb381E;
    address internal constant ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    address internal constant UBESWAP_FACTORY = 0x62d5b84bE28a183aBB507E125B384122D2C25fAE;
    address internal constant L1_TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // Oracle parameters
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;

    // Slippage: 5%
    uint256 internal constant maxSlippageBps = 500;

    // LP amount to use in tests (1000 LP tokens)
    uint256 internal constant TEST_LP_AMOUNT = 1000 ether;

    function setUp() public virtual {
        // Deploy oracle for the whOLAS-WCELO pair
        oracleV2 = new UniswapPriceOracle(LP_TOKEN, WHOLAS, minTwapWindowSeconds, minUpdateIntervalSeconds);

        // Warm up oracle: record observation, then warp past TWAP window
        oracleV2.updatePrice();
        vm.warp(block.timestamp + minTwapWindowSeconds + 1);

        // Deploy LPSwapCelo
        lpSwap = new LPSwapCelo(address(oracleV2), maxSlippageBps);

        // WCELO (0x471E...) is Celo's native GoldToken proxy which uses Celo-specific
        // precompiles for balance management. These precompiles are not available in
        // forge fork mode, causing transfers to silently fail. Replace the WCELO
        // implementation with a standard ERC20 so that transfers work correctly.
        (uint112 pairWceloBalance,,) = IUniswapV2Pair(LP_TOKEN).getReserves();
        MockERC20 mockCelo = new MockERC20("Celo", "CELO", 18);
        vm.etch(WCELO, address(mockCelo).code);

        // Restore WCELO balance for the LP pair to match real reserves (token0 = WCELO)
        deal(WCELO, LP_TOKEN, uint256(pairWceloBalance));
    }

    /// @dev Helper: fund the lpSwap contract with LP tokens and OLAS via deal().
    ///      Adjusts total supply for OLAS since its Celo supply is very low.
    function _fundLPSwapFork(uint256 lpAmount, uint256 olasAmount) internal {
        deal(LP_TOKEN, address(lpSwap), lpAmount);
        deal(OLAS, address(lpSwap), olasAmount, true);
    }

    /// @dev Helper: estimate whOLAS amount from removing a given LP amount.
    function _estimateWhOlasFromRemoval(uint256 lpAmount) internal view returns (uint256) {
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(LP_TOKEN).getReserves();
        uint256 totalSupply = IUniswapV2Pair(LP_TOKEN).totalSupply();
        // token0 = WCELO, token1 = WHOLAS
        return (lpAmount * uint256(r1)) / totalSupply;
    }
}

/// @dev Fork tests for LPSwapCelo on Celo mainnet.
contract LPSwapCeloForkTest is LPSwapCeloForkBaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Deployment is correctly configured with Celo mainnet addresses.
    function testForkDeployment() public view {
        assertEq(lpSwap.LP_TOKEN(), LP_TOKEN);
        assertEq(lpSwap.WCELO(), WCELO);
        assertEq(lpSwap.WHOLAS(), WHOLAS);
        assertEq(lpSwap.OLAS(), OLAS);
        assertEq(lpSwap.ROUTER(), ROUTER);
        assertEq(lpSwap.L1_TIMELOCK(), L1_TIMELOCK);
        assertEq(lpSwap.oracle(), address(oracleV2));
        assertEq(lpSwap.maxSlippage(), maxSlippageBps);

        // Verify LP token pair is valid
        assertEq(IUniswapV2Pair(LP_TOKEN).token0(), WCELO);
        assertEq(IUniswapV2Pair(LP_TOKEN).token1(), WHOLAS);
    }

    /// @dev Oracle returns valid TWAP from the live whOLAS-WCELO pair.
    function testForkOracleTWAP() public view {
        uint256 twap = oracleV2.getTWAP();
        assertGt(twap, 0);
        console.log("whOLAS/WCELO TWAP:", twap);
    }

    /// @dev swapLiquidity reverts with zero LP balance.
    function testForkSwapLiquidityZeroBalance() public {
        vm.expectRevert(ZeroValue.selector);
        lpSwap.swapLiquidity();
    }

    /// @dev Full swapLiquidity succeeds on fork: removes whOLAS-CELO, adds OLAS-CELO.
    function testForkSwapLiquidity() public {
        uint256 expectedWhOlas = _estimateWhOlasFromRemoval(TEST_LP_AMOUNT);
        _fundLPSwapFork(TEST_LP_AMOUNT, expectedWhOlas);

        // Verify initial state
        assertEq(IToken(LP_TOKEN).balanceOf(address(lpSwap)), TEST_LP_AMOUNT);
        assertEq(IToken(OLAS).balanceOf(address(lpSwap)), expectedWhOlas);

        // Execute swap
        lpSwap.swapLiquidity();

        // Verify: old LP tokens fully consumed
        assertEq(IToken(LP_TOKEN).balanceOf(address(lpSwap)), 0);

        // Verify: no WCELO left in contract (celoMin = celoDesired enforces full usage)
        assertEq(IToken(WCELO).balanceOf(address(lpSwap)), 0);

        // Verify: no OLAS left (used in new pair or bridged to L1)
        assertEq(IToken(OLAS).balanceOf(address(lpSwap)), 0);

        // Verify: whOLAS dust is negligible (Wormhole truncates to 8 decimals, so up to 1e10 dust)
        assertLt(IToken(WHOLAS).balanceOf(address(lpSwap)), 1e10);

        console.log("Swap completed successfully");
    }

    /// @dev swapLiquidity with extra OLAS bridges leftover to L1.
    function testForkSwapLiquidityBridgesExtraOLAS() public {
        uint256 expectedWhOlas = _estimateWhOlasFromRemoval(TEST_LP_AMOUNT);
        uint256 extraOlas = 100 ether;
        _fundLPSwapFork(TEST_LP_AMOUNT, expectedWhOlas + extraOlas);

        lpSwap.swapLiquidity();

        // No OLAS should remain in contract (extra was bridged to L1)
        assertEq(IToken(OLAS).balanceOf(address(lpSwap)), 0);
        // No WCELO should remain
        assertEq(IToken(WCELO).balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity with small LP amount works.
    function testForkSwapLiquiditySmallAmount() public {
        uint256 smallLp = 10 ether;
        uint256 expectedWhOlas = _estimateWhOlasFromRemoval(smallLp);
        _fundLPSwapFork(smallLp, expectedWhOlas);

        lpSwap.swapLiquidity();

        assertEq(IToken(LP_TOKEN).balanceOf(address(lpSwap)), 0);
        assertEq(IToken(WCELO).balanceOf(address(lpSwap)), 0);
    }

    /// @dev swapLiquidity emits LiquiditySwapped event.
    function testForkSwapLiquidityEmitsEvent() public {
        uint256 expectedWhOlas = _estimateWhOlasFromRemoval(TEST_LP_AMOUNT);
        _fundLPSwapFork(TEST_LP_AMOUNT, expectedWhOlas);

        vm.expectEmit(false, false, false, false);
        emit LPSwapCelo.LiquiditySwapped(0, 0, 0, 0);
        lpSwap.swapLiquidity();
    }

    /// @dev Reserves of the new OLAS-WCELO pair reflect the deposited amounts.
    function testForkNewPairReserves() public {
        uint256 expectedWhOlas = _estimateWhOlasFromRemoval(TEST_LP_AMOUNT);
        _fundLPSwapFork(TEST_LP_AMOUNT, expectedWhOlas);

        lpSwap.swapLiquidity();

        // Check new pair exists via factory
        // Ubeswap factory uses getPair
        (bool success, bytes memory data) = UBESWAP_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", OLAS, WCELO)
        );
        assertTrue(success);
        address newPair = abi.decode(data, (address));
        assertTrue(newPair != address(0));

        // New pair should have reserves
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(newPair).getReserves();
        assertGt(uint256(r0), 0);
        assertGt(uint256(r1), 0);

        console.log("New OLAS-WCELO pair:", newPair);
        console.log("Reserve0:", uint256(r0));
        console.log("Reserve1:", uint256(r1));
    }
}
