// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {LiquidityManagerCore, RatioDeviation} from "../contracts/pol/LiquidityManagerCore.sol";
import {LiquidityManagerSourceUniV2} from "../contracts/pol/LiquidityManagerSourceUniV2.sol";
import {LiquidityManagerSourceBalancer, IBalancerV2} from "../contracts/pol/LiquidityManagerSourceBalancer.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";

/// @dev Deterministic source fixture: the production adapters perform the withdrawal calls.
contract WithdrawalSource is MockERC20 {
    address public token0;
    address public token1;
    uint256 public amount0;
    uint256 public amount1;

    constructor(address t0, address t1) MockERC20("LP", "LP", 18) {
        token0 = t0;
        token1 = t1;
    }

    function fund(uint256 a0, uint256 a1) external {
        amount0 = a0;
        amount1 = a1;
        MockERC20(token0).mint(address(this), a0);
        MockERC20(token1).mint(address(this), a1);
    }

    function _withdraw(address sender, address recipient, uint256 lp) internal {
        burn(sender, lp);
        MockERC20(token0).transfer(recipient, amount0);
        MockERC20(token1).transfer(recipient, amount1);
    }

    function removeLiquidity(address t0, address t1, uint256 lp, uint256, uint256, address to, uint256)
        external
        returns (uint256, uint256)
    {
        require(t0 == token0 && t1 == token1);
        _withdraw(msg.sender, to, lp);
        return (amount0, amount1);
    }

    function getPool(bytes32) external view returns (address, IBalancerV2.PoolSpecialization) {
        return (address(this), IBalancerV2.PoolSpecialization.TWO_TOKEN);
    }

    function getPoolTokens(bytes32)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256)
    {
        tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        balances = new uint256[](2);
        balances[0] = MockERC20(token0).balanceOf(address(this));
        balances[1] = MockERC20(token1).balanceOf(address(this));
        return (tokens, balances, block.number);
    }

    function exitPool(bytes32, address sender, address payable recipient, IBalancerV2.ExitPoolRequest memory request)
        external
    {
        (IBalancerV2.ExitKind kind, uint256 lp) = abi.decode(request.userData, (IBalancerV2.ExitKind, uint256));
        require(kind == IBalancerV2.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT);
        _withdraw(sender, recipient, lp);
    }
}

/// @dev Stable 1:1 destination price; no fork or live-pool assumptions.
contract WithdrawalDestination {
    function factory() external view returns (address) {
        return address(this);
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (uint160(1 << 96), 0, 0, 2, 2, 0, true);
    }

    function observations(uint256) external view returns (uint32, int56, uint160, bool) {
        return (uint32(block.timestamp), 0, 0, true);
    }

    function observe(uint32[] calldata) external pure returns (int56[] memory, uint160[] memory) {
        return (new int56[](2), new uint160[](2));
    }
    function increaseObservationCardinalityNext(uint16) external {}
}

/// @dev Retains the production conversion, scanner, price guard, ratio guard and disposal flow.
/// Only destination minting is replaced with token transfers; this tests source accounting, not V3 mint mechanics.
abstract contract WithdrawalTarget is LiquidityManagerCore {
    constructor(address token, address treasury_, address destination, address scanner)
        LiquidityManagerCore(token, treasury_, destination, scanner, 2)
    {}

    function _burn(uint256 amount) internal override {
        MockERC20(olas).burn(address(this), amount);
    }

    function _getV3Pool(address[] memory, int24) internal view override returns (address) {
        return positionManagerV3;
    }

    function _feeAmountTickSpacing(int24) internal pure override returns (int24) {
        return 60;
    }

    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory,
        int24[] memory,
        int24,
        uint160
    ) internal override returns (uint256, uint128, uint256[] memory) {
        MockERC20(tokens[0]).transfer(positionManagerV3, amounts[0]);
        MockERC20(tokens[1]).transfer(positionManagerV3, amounts[1]);
        return (1, 1, amounts);
    }
}

contract WithdrawalUniManager is WithdrawalTarget, LiquidityManagerSourceUniV2 {
    constructor(address token, address treasury_, address destination, address scanner, address source)
        WithdrawalTarget(token, treasury_, destination, scanner)
        LiquidityManagerSourceUniV2(source)
    {}
}

contract WithdrawalBalancerManager is WithdrawalTarget, LiquidityManagerSourceBalancer {
    constructor(address token, address treasury_, address destination, address scanner, address source)
        WithdrawalTarget(token, treasury_, destination, scanner)
        LiquidityManagerSourceBalancer(source)
    {}
}

abstract contract WithdrawalBalancesTest is Test {
    MockERC20 internal t0;
    MockERC20 internal t1;
    WithdrawalSource internal source;
    WithdrawalDestination internal destination;
    LiquidityManagerCore internal manager;
    address internal constant TREASURY = address(0x1234);
    bytes32 internal poolId;
    address[] internal tokens;

    function makeManager(address scanner) internal virtual returns (LiquidityManagerCore);

    function setUp() public {
        t0 = new MockERC20("Token0", "T0", 18);
        t1 = new MockERC20("Token1", "T1", 18);
        // Both production adapters require the pool's token order.
        if (address(t0) > address(t1)) (t0, t1) = (t1, t0);
        source = new WithdrawalSource(address(t0), address(t1));
        destination = new WithdrawalDestination();
        manager = makeManager(address(new NeighborhoodScanner()));
        manager.initialize(500);
        source.mint(address(manager), 1e18);
        poolId = bytes32(uint256(uint160(address(source))));
        tokens.push(address(t0));
        tokens.push(address(t1));
    }

    function convert(bytes32 pool, uint16 burnRate) internal {
        int24[] memory shifts = new int24[](2);
        shifts[0] = -600;
        shifts[1] = 600;
        manager.convertToV3(tokens, pool, 3000, shifts, burnRate, false);
    }

    function test_preExistingTokensCannotMaskBadWithdrawal() public {
        source.fund(100e18, 50e18);
        t1.mint(address(manager), 50e18); // Combined balances are 1:1; withdrawal is not.
        vm.expectRevert(abi.encodeWithSelector(RatioDeviation.selector, 5e17, 1e18, uint256(500)));
        convert(poolId, 0);
        assertEq(source.balanceOf(address(manager)), 1e18);
        assertEq(t1.balanceOf(address(manager)), 50e18);
        assertEq(t0.balanceOf(address(source)), 100e18);
        assertEq(t0.balanceOf(address(destination)), 0);
    }

    function test_validWithdrawalWithSkewedExistingBalances() public {
        source.fund(100e18, 100e18);
        t0.mint(address(manager), 100e18); // Combined 2:1 must not fail the source-only guard.
        convert(poolId, 0);
        assertEq(manager.mapPoolAddressPositionIds(address(destination)), 1);
        assertEq(source.balanceOf(address(manager)), 0);
        assertEq(t0.balanceOf(address(manager)), 0);
        assertEq(t1.balanceOf(address(manager)), 0);
        assertEq(t0.balanceOf(address(destination)) + t0.balanceOf(TREASURY), 200e18);
        assertEq(t1.balanceOf(address(destination)) + t1.balanceOf(TREASURY), 100e18);
    }

    function test_withdrawalWithoutExistingBalances() public {
        source.fund(100e18, 100e18);
        convert(poolId, 0);
        assertEq(manager.mapPoolAddressPositionIds(address(destination)), 1);
        assertGt(t0.balanceOf(address(destination)), 0);
    }

    function test_balanceOnlyConversionSkipsSourceRatio() public {
        t0.mint(address(manager), 200e18);
        t1.mint(address(manager), 100e18);
        convert(bytes32(0), 0);
        assertEq(manager.mapPoolAddressPositionIds(address(destination)), 1);
        assertEq(source.balanceOf(address(manager)), 1e18);
        assertEq(t0.balanceOf(address(destination)) + t0.balanceOf(TREASURY), 200e18);
    }

    function test_badWithdrawalRollsBackBurnAndTransfers() public {
        source.fund(100e18, 50e18);
        t1.mint(address(manager), 50e18);
        uint256 supply = t0.totalSupply();
        vm.expectRevert(abi.encodeWithSelector(RatioDeviation.selector, 5e17, 1e18, uint256(500)));
        convert(poolId, 1000);
        assertEq(t0.totalSupply(), supply);
        assertEq(t0.balanceOf(address(source)), 100e18);
        assertEq(t1.balanceOf(address(source)), 50e18);
        assertEq(source.balanceOf(address(manager)), 1e18);
        assertEq(t1.balanceOf(address(manager)), 50e18);
        assertEq(t1.balanceOf(TREASURY), 0);
        assertEq(manager.mapPoolAddressPositionIds(address(destination)), 0);
        // The revert must also restore the reentrancy lock.
        t0.mint(address(manager), 50e18);
        convert(bytes32(0), 0);
        assertEq(manager.mapPoolAddressPositionIds(address(destination)), 1);
    }
}

contract WithdrawalBalancesUniTest is WithdrawalBalancesTest {
    function makeManager(address scanner) internal override returns (LiquidityManagerCore) {
        return new WithdrawalUniManager(address(t0), TREASURY, address(destination), scanner, address(source));
    }
}

contract WithdrawalBalancesBalancerTest is WithdrawalBalancesTest {
    function makeManager(address scanner) internal override returns (LiquidityManagerCore) {
        return new WithdrawalBalancerManager(address(t0), TREASURY, address(destination), scanner, address(source));
    }
}
