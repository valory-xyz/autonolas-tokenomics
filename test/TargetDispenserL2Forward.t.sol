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

    /// @dev Builds the message data of a single-target batch.
    function _batch(uint256 amount, bytes32 batchHash) internal view returns (bytes memory) {
        address[] memory targets = new address[](1);
        targets[0] = address(stakingTarget);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return abi.encode(targets, amounts, batchHash);
    }

    /// @dev Migrates, then restores the new dispenser's withheld amount to its balance (the cutover's restore step).
    function _migrateAndRestore() internal {
        _migrate();
        newDispenser.updateWithheldAmountMaintenance(olas.balanceOf(address(newDispenser)));
        assertEq(newDispenser.withheldAmount(), CARRIED, "withheld restored to the migrated balance");
    }

    /// @dev The full recovery of a claim in flight at migration time, as the forward() NatSpec describes: forward the
    ///      token leg, restore the withheld amount to the new balance, then replay the message with `true`. The
    ///      target is paid and withheldAmount stays equal to the balance.
    function test_forward_thenReplayMessageOnNewDispenser_depositsToTarget() public {
        _migrateAndRestore();
        bytes32 batchHash = keccak256("late batch");
        // The old dispenser never processed this batch: it is to be replayed
        assertFalse(oldDispenser.processedHashes(batchHash), "batch not processed on the old dispenser");

        // Token leg lands late on the old dispenser and is forwarded
        olas.mint(address(oldDispenser), LATE);
        oldDispenser.forward();

        // Restore the withheld amount to the new balance, then replay the message with true
        newDispenser.updateWithheldAmountMaintenance(olas.balanceOf(address(newDispenser)));
        newDispenser.processDataMaintenance(_batch(LATE, batchHash), true);

        assertEq(stakingTarget.balance(), LATE, "late incentive deposited to the staking target");
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED, "only the late amount was spent");
        assertEq(newDispenser.withheldAmount(), olas.balanceOf(address(newDispenser)), "withheld equals balance");
    }

    /// @dev A claim partly netted against OLAS already on L2: its token leg carries less than its message. The same
    ///      sequence keeps withheldAmount equal to the balance.
    function test_forward_thenReplayNettedClaim_keepsWithheldEqualToBalance() public {
        _migrateAndRestore();
        bytes32 batchHash = keccak256("netted late batch");

        // The message pays LATE, but only half of it travelled as tokens: the rest was netted on L1 against OLAS
        // already held on L2 (part of the migrated balance)
        olas.mint(address(oldDispenser), LATE / 2);
        oldDispenser.forward();

        newDispenser.updateWithheldAmountMaintenance(olas.balanceOf(address(newDispenser)));
        newDispenser.processDataMaintenance(_batch(LATE, batchHash), true);

        assertEq(stakingTarget.balance(), LATE, "full incentive deposited");
        assertEq(olas.balanceOf(address(newDispenser)), CARRIED - LATE / 2, "netted part drawn from the balance");
        assertEq(newDispenser.withheldAmount(), olas.balanceOf(address(newDispenser)), "withheld equals balance");
    }

    /// @dev A batch the old dispenser processed against a short balance: the first request was paid, the second was
    ///      left queued. Recovery replays only the unpaid request, with the original batchHash; the paid one is not
    ///      replayed, and withheldAmount stays equal to the balance.
    function test_forward_processedBatchWithQueuedRequest_recoversUnpaidOnly() public {
        // A dispenser pair whose old side holds less than the batch needs
        OptimismTargetDispenserL2 oldShort = new OptimismTargetDispenserL2(address(olas), address(stakingFactory),
            L2_MESSENGER, OLD_L1_PROCESSOR, L1_SOURCE_CHAIN_ID);
        OptimismTargetDispenserL2 newShort = new OptimismTargetDispenserL2(address(olas), address(stakingFactory),
            L2_MESSENGER, NEW_L1_PROCESSOR, L1_SOURCE_CHAIN_ID);
        MockStakingProxy secondTarget = new MockStakingProxy(address(olas));
        stakingFactory.addImplementation(address(secondTarget), address(0x1A1));
        olas.mint(address(oldShort), 60 ether);

        // The message arrives before its token leg: 50 is paid, the next 50 does not fit the remaining 10 and queues
        address[] memory targets = new address[](2);
        targets[0] = address(stakingTarget);
        targets[1] = address(secondTarget);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50 ether;
        amounts[1] = 50 ether;
        bytes32 batchHash = keccak256("short batch");
        oldShort.processDataMaintenance(abi.encode(targets, amounts, batchHash), false);
        assertEq(stakingTarget.balance(), 50 ether, "first request paid");
        assertEq(secondTarget.balance(), 0, "second request queued");
        bytes32 queueHash = keccak256(abi.encode(address(secondTarget), uint256(50 ether), batchHash, block.chainid,
            address(oldShort)));
        assertTrue(oldShort.processedHashes(batchHash), "batch processed on the old dispenser");
        assertTrue(oldShort.queuedHashes(queueHash), "unpaid request still queued on the old dispenser");

        // Migrate and restore, then the late token leg arrives and is forwarded
        oldShort.pause();
        oldShort.migrate(address(newShort));
        newShort.updateWithheldAmountMaintenance(olas.balanceOf(address(newShort)));
        olas.mint(address(oldShort), 100 ether);
        oldShort.forward();
        newShort.updateWithheldAmountMaintenance(olas.balanceOf(address(newShort)));

        // Replay only the unpaid request, with the original batchHash
        address[] memory unpaidTargets = new address[](1);
        unpaidTargets[0] = address(secondTarget);
        uint256[] memory unpaidAmounts = new uint256[](1);
        unpaidAmounts[0] = 50 ether;
        newShort.processDataMaintenance(abi.encode(unpaidTargets, unpaidAmounts, batchHash), true);

        assertEq(stakingTarget.balance(), 50 ether, "paid request not paid again");
        assertEq(secondTarget.balance(), 50 ether, "unpaid request recovered");
        assertEq(newShort.withheldAmount(), olas.balanceOf(address(newShort)), "withheld equals balance");
    }

    /// @dev Documents why the operator must check the old dispenser's processedHashes before replaying: nothing on-chain
    ///      prevents a second payment. A batch the old dispenser already paid from its balance (before its token leg
    ///      arrived) reads true there after migration; its late token leg is still forwarded and accounted for, but a
    ///      replay on the new dispenser, whose processedHashes starts empty, is accepted and pays the target again.
    function test_forward_processedBatch_replayWouldPayTwice() public {
        bytes32 batchHash = keccak256("processed batch");
        // Before migration, the old dispenser processes the message from its existing balance
        oldDispenser.processDataMaintenance(_batch(LATE, batchHash), false);
        assertEq(stakingTarget.balance(), LATE, "paid by the old dispenser");

        _migrate();
        newDispenser.updateWithheldAmountMaintenance(olas.balanceOf(address(newDispenser)));
        assertTrue(oldDispenser.processedHashes(batchHash), "processed flag readable after migration");

        // The token leg arrives late: forward it and account for it, but do not replay the message
        olas.mint(address(oldDispenser), LATE);
        oldDispenser.forward();
        newDispenser.updateWithheldAmountMaintenance(olas.balanceOf(address(newDispenser)));
        assertEq(stakingTarget.balance(), LATE, "target paid once");
        assertEq(newDispenser.withheldAmount(), olas.balanceOf(address(newDispenser)), "withheld equals balance");

        // The new dispenser accepts the replay and pays the target a second time: the check is the operator's
        uint256 snapshot = vm.snapshotState();
        newDispenser.processDataMaintenance(_batch(LATE, batchHash), true);
        assertEq(stakingTarget.balance(), 2 * LATE, "a replay would pay twice");
        vm.revertToState(snapshot);
    }
}
