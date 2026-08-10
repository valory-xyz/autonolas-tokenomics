// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OptimismTargetDispenserL2} from "../contracts/staking/OptimismTargetDispenserL2.sol";

/// @dev Optimism-mainnet fork test of the migration's L2 leg (runbook §6 Phase 3): the per-chain
///      pause -> migrate -> updateWithheldAmountMaintenance cutover of an L2 target dispenser onto its
///      new instance, driven against the REAL Optimism OLAS token and the real OP-stack bridge addresses
///      (baked as the dispensers' immutables).
///
///      What this uniquely exercises vs the mock-bridge unit tests in StakingBridging.js:
///        - `DefaultTargetDispenserL2.l1DepositProcessor` is `immutable`, so a new L1 processor forces a new
///          L2 dispenser — both are deployed fresh here and the OLAS balance is migrated between them on the
///          live token;
///        - `migrate()` transfers the full real-OLAS balance to the new dispenser, zeroes the old owner and
///          locks the old contract permanently (one-way brick) — verified against live OLAS, not a mock ERC20;
///        - the `Migrated` event surfaces `withheldAmount` (the value the DAO must restore), and
///          `updateWithheldAmountMaintenance` re-establishes it on the new dispenser, which deploys at 0.
///
///      The contract name avoids the "Dispenser"/"Treasury"/"Depository" substrings so CI's fork-less
///      `forge test --mc Dispenser|Treasury|Depository` allowlist does not pick it up and run it without a fork.
///
///      Run: forge test -f $FORK_OPTIMISM_NODE_URL --mc StakingL2MigrateForkOP -vvv

interface IOLASForkL2 {
    function balanceOf(address account) external view returns (uint256);
}

contract StakingL2MigrateForkOP is Test {
    // Optimism mainnet addresses
    address internal constant OLAS = 0xFC2E6e6BCbd49ccf3A5f029c79984372DcBFE527;
    address internal constant STAKING_FACTORY = 0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8;
    address internal constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;
    // A distinct new L1 deposit processor forces a new L2 target dispenser (immutable coupling)
    address internal constant OLD_L1_PROCESSOR = 0x990aBa4b05adc3761EfAf38FB871b93C7b162D03;
    address internal constant NEW_L1_PROCESSOR = 0x00000000000000000000000000000000DeaDBeef;
    uint256 internal constant L1_SOURCE_CHAIN_ID = 1;

    // OLAS carried on the L2 dispenser (withheld inflation) to be migrated
    uint256 internal constant CARRIED = 12_345 ether;

    // Mirror of DefaultTargetDispenserL2.Migrated for expectEmit
    event Migrated(address indexed sender, address indexed newL2TargetDispenser, uint256 amount,
        uint256 withheldAmount);

    OptimismTargetDispenserL2 internal oldDispenser;
    OptimismTargetDispenserL2 internal newDispenser;

    function setUp() public {
        // The new L1 processor forces a new L2 dispenser; deploy both (old bound to the old processor)
        oldDispenser = new OptimismTargetDispenserL2(OLAS, STAKING_FACTORY, L2_MESSENGER, OLD_L1_PROCESSOR,
            L1_SOURCE_CHAIN_ID);
        newDispenser = new OptimismTargetDispenserL2(OLAS, STAKING_FACTORY, L2_MESSENGER, NEW_L1_PROCESSOR,
            L1_SOURCE_CHAIN_ID);

        // Seed the OLD dispenser with real OLAS (as undelivered/withheld inflation would sit on L2) and set its
        // accounting withheldAmount to match (Phase 0 records this; it must be restored on the new contract)
        deal(OLAS, address(oldDispenser), CARRIED);
        oldDispenser.updateWithheldAmountMaintenance(CARRIED);
    }

    // -----------------------------------------------------------------------
    // Phase 3 happy path: pause -> migrate -> restore withheld on the new dispenser
    // -----------------------------------------------------------------------

    function test_migrateCarriesRealOlasAndBricksOld() public {
        assertEq(IOLASForkL2(OLAS).balanceOf(address(oldDispenser)), CARRIED, "old seeded with real OLAS");
        assertEq(newDispenser.withheldAmount(), 0, "new dispenser deploys with withheldAmount == 0");
        assertEq(newDispenser.l1DepositProcessor(), NEW_L1_PROCESSOR, "new dispenser bound to the new L1 processor");

        // migrate requires paused
        oldDispenser.pause();

        // The Migrated event carries the exact amount + withheldAmount the DAO must restore
        vm.expectEmit(true, true, false, true, address(oldDispenser));
        emit Migrated(address(this), address(newDispenser), CARRIED, CARRIED);
        oldDispenser.migrate(address(newDispenser));

        // Real OLAS moved old -> new, in full
        assertEq(IOLASForkL2(OLAS).balanceOf(address(oldDispenser)), 0, "old drained");
        assertEq(IOLASForkL2(OLAS).balanceOf(address(newDispenser)), CARRIED, "new holds the migrated OLAS");

        // Old contract is permanently bricked: owner zeroed, no further owner-gated interaction possible
        assertEq(oldDispenser.owner(), address(0), "old owner zeroed");
        vm.expectRevert();
        oldDispenser.pause();
        vm.expectRevert();
        oldDispenser.migrate(address(newDispenser));

        // Restore the withheld accounting on the new dispenser (Phase 3 step 12)
        newDispenser.updateWithheldAmountMaintenance(CARRIED);
        assertEq(newDispenser.withheldAmount(), CARRIED, "withheld restored on the new dispenser");
    }

    // -----------------------------------------------------------------------
    // Guards on the live fork (belt-and-braces over the mock-bridge unit tests)
    // -----------------------------------------------------------------------

    function test_migrateGuards() public {
        // Cannot migrate while unpaused
        vm.expectRevert();
        oldDispenser.migrate(address(newDispenser));

        oldDispenser.pause();

        // Cannot migrate to an EOA (must be a contract)
        vm.expectRevert();
        oldDispenser.migrate(address(0xBEEF));

        // Cannot migrate to self
        vm.expectRevert();
        oldDispenser.migrate(address(oldDispenser));

        // Not-owner cannot migrate
        vm.prank(address(0xBAD));
        vm.expectRevert();
        oldDispenser.migrate(address(newDispenser));
    }
}
