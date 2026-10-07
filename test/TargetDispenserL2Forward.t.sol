// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OptimismTargetDispenserL2} from "../contracts/staking/OptimismTargetDispenserL2.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {MockStakingFactory} from "../contracts/staking/test/MockStakingFactory.sol";
import {MockStakingProxy} from "../contracts/staking/test/MockStakingProxy.sol";

/// @dev Regression tests for vulnerability-list #39: OLAS reaching an L2 target dispenser after migrate() is
///      forwarded to the new L2 target dispenser by the permissionless forward(), instead of being stranded.
///      Every chain's L2 target dispenser inherits forward() from DefaultTargetDispenserL2; the OP build is used
///      as the concrete contract. Token legs are plain credits on every bridge (no callback), so a late transfer
///      is modelled as a mint to the old dispenser's address.
///      Run: forge test --mc TargetDispenserL2ForwardTest -vvv
contract TargetDispenserL2ForwardTest is Test {
    address internal constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;
    address internal constant OLD_L1_PROCESSOR = address(0x01D);
    address internal constant NEW_L1_PROCESSOR = address(0x0E3);
    uint256 internal constant L1_SOURCE_CHAIN_ID = 1;
    // OLAS held by the old dispenser at migration time
    uint256 internal constant CARRIED = 1_000 ether;
    // OLAS of a token leg still in flight at migration time (within the mock factory's 100 ether emissions limit)
    uint256 internal constant LATE = 50 ether;

    // Mirror of DefaultTargetDispenserL2.Forwarded for expectEmit
    event Forwarded(address indexed sender, address indexed newL2TargetDispenser, uint256 amount);

    ERC20Token internal olas;
    MockStakingFactory internal stakingFactory;
    MockStakingProxy internal stakingTarget;
    OptimismTargetDispenserL2 internal oldDispenser;
    OptimismTargetDispenserL2 internal newDispenser;

    function setUp() public {
        olas = new ERC20Token();
        stakingFactory = new MockStakingFactory();
        stakingTarget = new MockStakingProxy(address(olas));
        stakingFactory.addImplementation(address(stakingTarget), address(0x1A1));

        oldDispenser = new OptimismTargetDispenserL2(address(olas), address(stakingFactory), L2_MESSENGER,
            OLD_L1_PROCESSOR, L1_SOURCE_CHAIN_ID);
        newDispenser = new OptimismTargetDispenserL2(address(olas), address(stakingFactory), L2_MESSENGER,
            NEW_L1_PROCESSOR, L1_SOURCE_CHAIN_ID);

        olas.mint(address(oldDispenser), CARRIED);
    }

    /// @dev Pauses and migrates the old dispenser to the new one.
    function _migrate() internal {
        oldDispenser.pause();
        oldDispenser.migrate(address(newDispenser));
    }

    /// @dev Before migration there is no recorded destination, so forward() reverts even with a balance.
    function test_forward_beforeMigration_reverts() public {
        assertEq(oldDispenser.migratedTo(), address(0), "not migrated");

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oldDispenser.forward();

        // Also while paused, ahead of the migration
        oldDispenser.pause();
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oldDispenser.forward();
    }

    /// @dev migrate() records the new dispenser, and OLAS arriving afterwards is forwarded to it by anyone.
    ///      On the pre-fix code there is no forward(): the old dispenser's owner is zeroed and the late OLAS is
    ///      stranded for good.
    function test_forward_afterMigration_movesLateTokens() public {
        _migrate();
        assertEq(oldDispenser.migratedTo(), address(newDispenser), "migratedTo recorded");
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED, "balance migrated");

        // A token leg in flight at migration time lands on the old address
        olas.mint(address(oldDispenser), LATE);

        // Permissionless
        address caller = address(0xCA11);
        vm.expectEmit(true, true, false, true, address(oldDispenser));
        emit Forwarded(caller, address(newDispenser), LATE);
        vm.prank(caller);
        uint256 amount = oldDispenser.forward();

        assertEq(amount, LATE, "returned amount");
        assertEq(olas.balanceOf(address(oldDispenser)), 0, "old emptied");
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED + LATE, "late OLAS forwarded");
    }

    /// @dev Several late arrivals are each forwarded; with nothing to forward, forward() reverts.
    function test_forward_repeatable_andZeroBalanceReverts() public {
        _migrate();

        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        oldDispenser.forward();

        olas.mint(address(oldDispenser), LATE);
        oldDispenser.forward();
        olas.mint(address(oldDispenser), 2 * LATE);
        oldDispenser.forward();

        assertEq(olas.balanceOf(address(newDispenser)), CARRIED + 3 * LATE, "every late arrival forwarded");

        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        oldDispenser.forward();
    }

    /// @dev forward() needs no owner and ignores the reentrancy lock, both of which migrate() leaves disabled.
    function test_forward_worksOnBrickedContract() public {
        _migrate();
        assertEq(oldDispenser.owner(), address(0), "owner zeroed by migrate");

        // The old dispenser can no longer process anything: owner-gated and lock-gated paths are closed
        vm.expectRevert();
        oldDispenser.processDataMaintenance(abi.encode(new address[](0), new uint256[](0), bytes32(0)), false);

        olas.mint(address(oldDispenser), LATE);
        oldDispenser.forward();
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED + LATE, "forwarded despite the brick");
    }

    /// @dev The full recovery of a claim in flight at migration time: its token leg is forwarded, and its message
    ///      leg is replayed by the DAO on the new dispenser, which deposits to the staking target.
    function test_forward_thenReplayMessageOnNewDispenser_depositsToTarget() public {
        _migrate();

        // Token leg lands late on the old dispenser and is forwarded
        olas.mint(address(oldDispenser), LATE);
        oldDispenser.forward();

        // Message leg: the DAO replays it on the new dispenser (its processedHashes starts empty)
        address[] memory targets = new address[](1);
        targets[0] = address(stakingTarget);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = LATE;
        bytes32 batchHash = keccak256("late batch");
        newDispenser.processDataMaintenance(abi.encode(targets, amounts, batchHash), false);

        assertEq(stakingTarget.balance(), LATE, "late incentive deposited to the staking target");
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED, "only the late amount was spent");
    }
}
