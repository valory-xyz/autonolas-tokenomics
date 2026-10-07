pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {Dispenser, Unpaused} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";
import "../contracts/Tokenomics.sol";
import {TokenomicsProxy} from "../contracts/proxies/TokenomicsProxy.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {MockRegistry} from "../contracts/test/MockRegistry.sol";
import {MockVE} from "../contracts/test/MockVE.sol";
import {MockVoteWeighting} from "../contracts/test/MockVoteWeighting.sol";

/// @dev Minimal deposit processor: enough surface for the dispenser claim / withheld-sync flows.
contract MockDepositProcessor {
    uint256 public lastTransferAmount;
    uint256 public lastStakingIncentive;

    function getBridgingDecimals() external pure returns (uint256) {
        return 18;
    }

    function sendMessage(address, uint256 stakingIncentive, bytes memory, uint256 transferAmount) external payable {
        lastStakingIncentive = stakingIncentive;
        lastTransferAmount = transferAmount;
    }

    function sendMessageBatch(address[] memory, uint256[] memory stakingIncentives, bytes memory,
        uint256 transferAmount) external payable {
        lastStakingIncentive = stakingIncentives[stakingIncentives.length - 1];
        lastTransferAmount = transferAmount;
    }

    function updateHashMaintenance(bytes32) external {}
}

/// @dev Regression tests for the Dispenser vulnerability-list fixes (each fails on the pre-fix code):
///      #12 calculateStakingIncentives is view — a standalone call mutates nothing (cannot strand a
///          zero-weight epoch's refund); the claim path refunds it exactly once and never double-refunds;
///      #9  the withheld-covered portion of claimed incentives is returned to staking inflation
///          (single and batch claim paths);
///      #25 addNominee clears mapRemovedNomineeEpochs so a removed-then-re-added nominee is claimable;
///      #8  changeManagers only swaps voteWeighting while staking incentives are paused;
///      #30 an epoch with a zero staking fraction but a non-zero (carried refund) staking incentive is claimed;
///      #31 a claim that sends no bridge message rejects a non-zero value (single and batch claim paths).
///      Run: forge test --mc DispenserFixesTest -vvv
contract DispenserFixesTest is Test {
    Utils internal utils;
    Dispenser internal dispenser;
    ERC20Token internal olas;
    MockRegistry internal componentRegistry;
    MockRegistry internal agentRegistry;
    MockRegistry internal serviceRegistry;
    MockVE internal ve;
    Treasury internal treasury;
    Tokenomics internal tokenomics;
    MockVoteWeighting internal vw;
    MockDepositProcessor internal depositProcessor;

    address payable[] internal users;
    address internal deployer;
    bytes32 internal retainer;
    uint256 internal epochLen = 30 days;
    uint256 internal constant CHAIN_ID = 100;
    address internal constant STAKING_TARGET = address(0x57A6);

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        retainer = bytes32(uint256(uint160(deployer)));

        // Deploy contracts
        olas = new ERC20Token();
        ve = new MockVE();
        componentRegistry = new MockRegistry();
        agentRegistry = new MockRegistry();
        serviceRegistry = new MockRegistry();

        // Depository and dispenser contracts are irrelevant at this point, so we are using a deployer's address
        treasury = new Treasury(address(olas), deployer, deployer, deployer);

        Tokenomics tokenomicsMaster = new Tokenomics();
        bytes memory proxyData = abi.encodeWithSelector(tokenomicsMaster.initializeTokenomics.selector,
            address(olas), address(treasury), deployer, deployer, address(ve), epochLen,
            address(componentRegistry), address(agentRegistry), address(serviceRegistry), address(0));
        TokenomicsProxy tokenomicsProxy = new TokenomicsProxy(address(tokenomicsMaster), proxyData);
        tokenomics = Tokenomics(address(tokenomicsProxy));

        // Deploy dispenser implementation and proxy
        Dispenser dispenserMaster = new Dispenser(address(olas), address(tokenomics), retainer);
        bytes memory dispenserData = abi.encodeWithSelector(dispenserMaster.initialize.selector,
            address(treasury), deployer, 100, 100);
        DispenserProxy dispenserProxy = new DispenserProxy(address(dispenserMaster), dispenserData);
        dispenser = Dispenser(address(dispenserProxy));

        // Vote Weighting mock over the deployed dispenser
        vw = new MockVoteWeighting(address(dispenser));
        // Staking incentives are paused after initialize, so the vote weighting swap guard (#8) is satisfied
        dispenser.changeManagers(address(0), address(vw));

        // Wire the rest
        treasury.changeManagers(address(tokenomics), address(0), address(dispenser));
        tokenomics.changeManagers(address(0), address(0), address(dispenser));
        olas.changeMinter(address(treasury));

        // Deposit processor for the test L2 chain Id
        depositProcessor = new MockDepositProcessor();
        address[] memory processors = new address[](1);
        processors[0] = address(depositProcessor);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        dispenser.setDepositProcessorChainIds(processors, chainIds);

        // Enable staking inflation from the next epoch and settle two epochs so a claimable epoch exists
        tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 50);
        // Staking parameters (maxStakingIncentive, minStakingWeight) — always non-zero on a live Tokenomics
        tokenomics.changeStakingParams(1 ether, 100);

        // Unpause staking incentives (nominees cannot be added while paused)
        dispenser.setPauseState(Dispenser.Pause.Unpaused);
    }

    /// @dev Advances one epoch: warp past the epoch length and checkpoint.
    function _advanceEpoch() internal {
        vm.warp(block.timestamp + epochLen + 10);
        vm.roll(block.number + 1);
        tokenomics.checkpoint();
    }

    function _targetBytes32() internal pure returns (bytes32) {
        return bytes32(uint256(uint160(STAKING_TARGET)));
    }

    /// @dev Reads the staking incentive of an epoch from the public tuple getter.
    function _stakingIncentiveOf(uint256 epoch) internal view returns (uint256 amount) {
        (amount, , , ) = tokenomics.mapEpochStakingPoints(epoch);
    }

    function _nomineeHash() internal pure returns (bytes32) {
        return keccak256(abi.encode(_targetBytes32(), CHAIN_ID));
    }

    /// @dev True if `value` appears in `arr` (used to check the sparse zeroWeightEpochs return).
    function _arrayContains(uint256[] memory arr, uint256 value) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] == value) {
                return true;
            }
        }
        return false;
    }

    // -----------------------------------------------------------------------
    // #12 — zero-weight epoch refund is atomic with the one-way flag
    // -----------------------------------------------------------------------

    /// @dev calculateStakingIncentives is view: a standalone call on a zero-total-weight epoch mutates nothing
    ///      (it reports the epoch as returnable but neither sets mapZeroWeightEpochRefunded nor refunds), so it
    ///      can never strand the epoch's inflation. The refund happens exactly once via the claim path, and a
    ///      subsequent claim must not refund it again.
    function test_fix12_viewCalculate_zeroWeight_refundsOnceViaClaim() public {
        // Nominate the target; no votes are ever cast, so nomineeRelativeWeight returns (0, 0)
        vw.addNominee(STAKING_TARGET, CHAIN_ID);

        // Settle the fraction-activation epoch, then one full epoch with staking inflation
        _advanceEpoch();
        _advanceEpoch();

        // The settled epoch carries a non-zero staking incentive
        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        assertGt(epochIncentive, 0, "settled epoch must carry staking incentive");

        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        // Standalone view call by an arbitrary account (NOT via the claim path): reports the zero-weight epoch,
        // mutates nothing
        vm.prank(address(0xA77ACC));
        (, uint256 returnAmount, , , uint256[] memory zeroWeightEpochs) =
            dispenser.calculateStakingIncentives(10, CHAIN_ID, _targetBytes32(), 18);
        assertEq(returnAmount, epochIncentive, "zero-weight incentive reported as returnable");
        assertTrue(_arrayContains(zeroWeightEpochs, claimableEpoch), "zero-weight epoch reported");
        // The view call left state untouched: flag unset and the staking pot unchanged
        assertFalse(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "view call must not set the flag");
        assertEq(_stakingIncentiveOf(currentEpoch), potBefore, "view call must not refund");

        // The claim path refunds the zero-weight epoch exactly once and sets the flag
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        assertTrue(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "flag set on claim");
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, epochIncentive, "zero-weight incentive refunded once");
    }

    /// @dev Cross-transaction dedup: a second target claiming the SAME zero-weight epoch in a later tx must not
    ///      refund it again — the persisted mapZeroWeightEpochRefunded flag makes the (view) calculation skip it.
    function test_fix12_separateClaims_zeroWeight_noDoubleRefund() public {
        address target2 = address(0x57A7); // fresh nominee, no votes -> shares the zero-weight epoch
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        vw.addNominee(target2, CHAIN_ID);

        _advanceEpoch();
        _advanceEpoch();

        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        // First target claim (tx 1): refunds the zero-weight epoch once and sets the flag
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        uint256 potAfterFirst = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfterFirst - potBefore, epochIncentive, "first claim refunds the epoch once");
        assertTrue(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "flag set");

        // Second target claim (tx 2) for the same epoch: flag already set -> no additional refund
        dispenser.claimStakingIncentives(10, CHAIN_ID, bytes32(uint256(uint160(target2))), "");
        assertEq(_stakingIncentiveOf(currentEpoch), potAfterFirst, "no double refund across separate claims");
    }

    /// @dev Two targets share the same zero-total-weight epoch in a single batch claim. Zero-weight is a
    ///      property of the epoch, so both targets would each want to refund its full incentive. The dispenser
    ///      sets mapZeroWeightEpochRefunded for the first target before the second target's (view) calculation,
    ///      so the epoch's inflation is refunded exactly once for the batch, not once per target.
    function test_fix12_batchZeroWeight_dedupRefundsOnce() public {
        // Two nominees on the same chain, neither ever voted for -> shared zero-total-weight epochs
        address target2 = address(0x57A7); // strictly greater than STAKING_TARGET (0x57A6) for ascending order
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        vw.addNominee(target2, CHAIN_ID);

        _advanceEpoch();
        _advanceEpoch();

        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        assertGt(epochIncentive, 0, "settled epoch must carry staking incentive");

        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        // Single-chain batch claim over both targets (ascending order required)
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        bytes32[][] memory stakingTargets = new bytes32[][](1);
        stakingTargets[0] = new bytes32[](2);
        stakingTargets[0][0] = _targetBytes32();
        stakingTargets[0][1] = bytes32(uint256(uint160(target2)));
        bytes[] memory bridgePayloads = new bytes[](1);
        uint256[] memory valueAmounts = new uint256[](1);

        dispenser.claimStakingIncentivesBatch(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);

        // The shared zero-weight epoch is refunded once for the whole batch, not once per target
        assertTrue(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "flag set once");
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, epochIncentive, "zero-weight epoch refunded exactly once for the batch");
    }

    // -----------------------------------------------------------------------
    // #9 — withheld-covered incentives return their inflation allocation
    // -----------------------------------------------------------------------

    /// @dev Sets a 100% relative weight for the target so the claim allocates incentives.
    ///      MockVoteWeighting stores weight * 1e14 and sums raw weights into totalWeight, which the dispenser
    ///      treats as the OLAS cap of the epoch allocation — so incentives get capped to `weight` wei.
    function _nominateWithFullWeight() internal {
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        // 10_000 -> relative weight 1e18 (100%); totalWeight (OLAS cap) = 10_000 wei
        vw.setNomineeRelativeWeight(STAKING_TARGET, CHAIN_ID, 10_000);
    }

    function test_fix9_claim_withheldReuse_refundsInflation() public {
        _nominateWithFullWeight();

        // Seed a withheld amount smaller than the allocated incentive so both branches are exercised
        uint256 withheld = 6_000;
        dispenser.syncWithheldAmountMaintenance(CHAIN_ID, withheld, bytes32(uint256(1)));
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), withheld, "withheld seeded");

        _advanceEpoch();
        _advanceEpoch();

        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive =
            _stakingIncentiveOf(claimableEpoch);
        // Weight cap makes the allocated incentive exactly 10_000 wei; the rest is the standard return amount
        uint256 allocated = 10_000;
        uint256 standardReturn = epochIncentive - allocated;

        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");

        // Withheld is fully consumed; only the non-covered part is actually transferred
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "withheld consumed");
        assertEq(depositProcessor.lastStakingIncentive(), allocated, "full incentive communicated to L2");
        assertEq(depositProcessor.lastTransferAmount(), allocated - withheld, "transfer netted by withheld");
        assertEq(olas.balanceOf(address(depositProcessor)), allocated - withheld, "only the netted OLAS is minted");

        // The withheld-covered portion is returned to staking inflation on top of the standard return
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, standardReturn + withheld, "withheld-covered allocation refunded");
    }

    function test_fix9_claimBatch_withheldReuse_refundsInflation() public {
        _nominateWithFullWeight();

        uint256 withheld = 6_000;
        dispenser.syncWithheldAmountMaintenance(CHAIN_ID, withheld, bytes32(uint256(1)));

        _advanceEpoch();
        _advanceEpoch();

        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive =
            _stakingIncentiveOf(claimableEpoch);
        uint256 allocated = 10_000;
        uint256 standardReturn = epochIncentive - allocated;

        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        // Single-chain batch claim
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        bytes32[][] memory stakingTargets = new bytes32[][](1);
        stakingTargets[0] = new bytes32[](1);
        stakingTargets[0][0] = _targetBytes32();
        bytes[] memory bridgePayloads = new bytes[](1);
        uint256[] memory valueAmounts = new uint256[](1);

        dispenser.claimStakingIncentivesBatch(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);

        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "withheld consumed");
        assertEq(depositProcessor.lastTransferAmount(), allocated - withheld, "transfer netted by withheld");

        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, standardReturn + withheld, "withheld-covered allocation refunded (batch)");
    }

    // -----------------------------------------------------------------------
    // #25 — removed-then-re-added nominee is claimable again
    // -----------------------------------------------------------------------

    /// @dev addNominee must clear mapRemovedNomineeEpochs from the previous lifecycle. On the pre-fix code the
    ///      stale removal epoch bricks every subsequent claim with Overflow(firstClaimedEpoch, epochRemoved - 1).
    function test_fix25_removeThenReAdd_claimsAgain() public {
        vw.addNominee(STAKING_TARGET, CHAIN_ID);

        _advanceEpoch();

        // Remove right after a checkpoint (allowed: more than one week before the epoch end)
        vw.removeNominee(STAKING_TARGET, CHAIN_ID);
        assertGt(dispenser.mapRemovedNomineeEpochs(_nomineeHash()), 0, "removal epoch recorded");

        _advanceEpoch();

        // Second lifecycle: re-add the same nominee
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        assertEq(dispenser.mapRemovedNomineeEpochs(_nomineeHash()), 0, "removal epoch cleared on re-add");

        _advanceEpoch();

        // Claim must work in the second lifecycle (pre-fix: reverts Overflow from the stale removal epoch)
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
    }

    // -----------------------------------------------------------------------
    // #8 — voteWeighting swap requires staking incentives paused
    // -----------------------------------------------------------------------

    function test_fix8_changeManagers_voteWeightingSwap_requiresPause() public {
        address newVW = address(new MockVoteWeighting(address(dispenser)));

        // Unpaused: the swap must revert
        vm.expectRevert(Unpaused.selector);
        dispenser.changeManagers(address(0), newVW);

        // Treasury-only change stays allowed while unpaused
        dispenser.changeManagers(address(0xFEE5), address(0));
        assertEq(dispenser.treasury(), address(0xFEE5), "treasury change is not pause-gated");

        // Paused for staking incentives: the swap goes through
        dispenser.setPauseState(Dispenser.Pause.StakingIncentivesPaused);
        dispenser.changeManagers(address(0), newVW);
        assertEq(dispenser.voteWeighting(), newVW, "vote weighting swapped under pause");

        // AllPaused also satisfies the guard
        dispenser.setPauseState(Dispenser.Pause.AllPaused);
        dispenser.changeManagers(address(0), address(vw));
        assertEq(dispenser.voteWeighting(), address(vw), "vote weighting swapped under all-paused");

        // DevIncentivesPaused does not pause staking incentives, so the swap must still revert
        dispenser.setPauseState(Dispenser.Pause.DevIncentivesPaused);
        vm.expectRevert(Unpaused.selector);
        dispenser.changeManagers(address(0), newVW);
    }

    // A claim for a never-added nominee must revert ZeroValue from the Dispenser's own claimable-cursor guard,
    // BEFORE checkpointNominee (which reverts NomineeDoesNotExist on the real Vote Weighting). This locks in the
    // guard ordering: were the checkpoint to run first, this claim would surface NomineeDoesNotExist instead.
    function test_claim_neverAddedNominee_revertsZeroValueBeforeCheckpoint() public {
        bytes32 unregistered = bytes32(uint256(uint160(address(0x9999))));

        // The mock faithfully mirrors the real Vote Weighting: checkpointing an unregistered nominee reverts
        vm.expectRevert(abi.encodeWithSignature("NomineeDoesNotExist(bytes32,uint256)", unregistered, CHAIN_ID));
        vw.checkpointNominee(unregistered, CHAIN_ID);

        // Yet the claim path reverts ZeroValue (the guard fires first), not NomineeDoesNotExist
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        dispenser.claimStakingIncentives(10, CHAIN_ID, unregistered, "");
    }

    // -----------------------------------------------------------------------
    // #30 — zero staking fraction does not skip carried refunds
    // -----------------------------------------------------------------------

    /// @dev Reads the staking fraction of an epoch from the public tuple getter.
    function _stakingFractionOf(uint256 epoch) internal view returns (uint256 fraction) {
        (, , , fraction) = tokenomics.mapEpochStakingPoints(epoch);
    }

    /// @dev Refunds made during an epoch whose staking fraction is zero still form that epoch's staking incentive.
    ///      On the pre-fix code the claim skips the epoch on stakingFraction == 0 and advances the cursor past it,
    ///      so the carried incentive is neither distributed nor returned to staking inflation.
    function test_fix30_zeroStakingFraction_carriedRefundIsClaimed() public {
        _nominateWithFullWeight();

        // Settle the activation epoch, so the next epoch carries the staking fraction set in setUp
        _advanceEpoch();
        // Zero staking fraction from the next epoch on
        tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 0);
        // Settle the epoch funded by the staking fraction
        _advanceEpoch();

        // First claim: allocates the weight-capped 10_000 wei and refunds the rest into the current epoch,
        // whose staking fraction is zero
        uint256 refundEpoch = tokenomics.epochCounter();
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        assertEq(olas.balanceOf(address(depositProcessor)), 10_000, "first claim allocated");

        // Settle the zero-fraction epoch: its staking incentive is made only of the carried refund
        _advanceEpoch();
        assertEq(_stakingFractionOf(refundEpoch), 0, "zero staking fraction epoch");
        uint256 carriedIncentive = _stakingIncentiveOf(refundEpoch);
        assertGt(carriedIncentive, 10_000, "carried refund forms the epoch staking incentive");

        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        // Second claim covers the zero-fraction epoch: it is allocated and the remainder is returned
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        assertEq(olas.balanceOf(address(depositProcessor)), 20_000, "carried incentive allocated");
        assertEq(_stakingIncentiveOf(currentEpoch) - potBefore, carriedIncentive - 10_000, "carried remainder returned");
    }

    // -----------------------------------------------------------------------
    // #31 — no value is kept by a claim that sends no bridge message
    // -----------------------------------------------------------------------

    uint256 internal constant CHAIN_ID_2 = 137;
    address internal constant STAKING_TARGET_2 = address(0x57A8);

    /// @dev Adds a second chain with its own deposit processor and a nominee there with zero relative weight.
    function _addSecondChainNominee() internal returns (MockDepositProcessor depositProcessor2) {
        depositProcessor2 = new MockDepositProcessor();
        address[] memory processors = new address[](1);
        processors[0] = address(depositProcessor2);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID_2;
        dispenser.setDepositProcessorChainIds(processors, chainIds);
        vw.addNominee(STAKING_TARGET_2, CHAIN_ID_2);
    }

    /// @dev Builds a two-chain batch: STAKING_TARGET on CHAIN_ID and STAKING_TARGET_2 on CHAIN_ID_2.
    function _twoChainBatch() internal pure returns (uint256[] memory chainIds, bytes32[][] memory stakingTargets,
        bytes[] memory bridgePayloads)
    {
        chainIds = new uint256[](2);
        chainIds[0] = CHAIN_ID;
        chainIds[1] = CHAIN_ID_2;
        stakingTargets = new bytes32[][](2);
        stakingTargets[0] = new bytes32[](1);
        stakingTargets[0][0] = bytes32(uint256(uint160(STAKING_TARGET)));
        stakingTargets[1] = new bytes32[](1);
        stakingTargets[1][0] = bytes32(uint256(uint160(STAKING_TARGET_2)));
        bridgePayloads = new bytes[](2);
    }

    /// @dev A single claim with no staking incentive sends no message, so a provided value must be rejected rather
    ///      than kept by the Dispenser. The same claim without value goes through and keeps its side effects:
    ///      the cursor advances and the zero-weight epoch is refunded.
    function test_fix31_claim_zeroIncentiveWithValue_reverts() public {
        // No votes are ever cast: the claim only refunds the zero-weight epoch and sends nothing
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        _advanceEpoch();
        _advanceEpoch();

        uint256 claimableEpoch = tokenomics.epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        uint256 currentEpoch = tokenomics.epochCounter();
        uint256 cursorBefore = dispenser.mapLastClaimedStakingEpochs(_nomineeHash());
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("WrongAmount(uint256,uint256)", 1, 0));
        dispenser.claimStakingIncentives{value: 1}(10, CHAIN_ID, _targetBytes32(), "");

        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        assertEq(address(dispenser).balance, 0, "no value kept");
        assertGt(currentEpoch, cursorBefore, "claimable epochs existed");
        assertEq(dispenser.mapLastClaimedStakingEpochs(_nomineeHash()), currentEpoch, "cursor advanced");
        assertTrue(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "zero-weight epoch flagged");
        assertEq(_stakingIncentiveOf(currentEpoch) - potBefore, epochIncentive, "zero-weight epoch refunded");
    }

    /// @dev A third party claims the paying epochs first with a shorter claim, so a pending claim that was simulated
    ///      as paying settles a zero-paying tail. Its attached value must be rejected rather than kept.
    function test_fix31_claim_zeroTailAfterPartialClaim_withValue_reverts() public {
        _nominateWithFullWeight();
        // Settle the activation epoch (no staking incentive)
        _advanceEpoch();
        // Zero staking fraction from the next epoch on, so every later epoch pays nothing
        tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 0);
        // Settle the paying epoch, then a zero-paying one
        _advanceEpoch();
        _advanceEpoch();

        // Simulated before inclusion, the pending claim over all epochs pays
        (uint256 simulatedIncentive, , , , ) = dispenser.calculateStakingIncentives(10, CHAIN_ID, _targetBytes32(), 18);
        assertEq(simulatedIncentive, 10_000, "pending claim simulated as paying");

        // A third party claims only the first two epochs, which include the paying one
        vm.prank(address(0xA77ACC));
        dispenser.claimStakingIncentives(2, CHAIN_ID, _targetBytes32(), "");
        assertEq(olas.balanceOf(address(depositProcessor)), 10_000, "paying epoch delivered to the target");

        // The pending claim now settles only the zero-paying tail: its value is rejected, not kept
        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("WrongAmount(uint256,uint256)", 1, 0));
        dispenser.claimStakingIncentives{value: 1}(10, CHAIN_ID, _targetBytes32(), "");
        assertEq(address(dispenser).balance, 0, "no value kept");
    }

    /// @dev A paying claim forwards the attached value to the deposit processor and keeps none of it.
    function test_fix31_claim_payingWithValue_forwardsValue() public {
        _nominateWithFullWeight();
        _advanceEpoch();
        _advanceEpoch();

        vm.deal(address(this), 1 ether);
        dispenser.claimStakingIncentives{value: 1}(10, CHAIN_ID, _targetBytes32(), "");

        assertEq(depositProcessor.lastTransferAmount(), 10_000, "incentive transferred");
        assertEq(address(depositProcessor).balance, 1, "value forwarded");
        assertEq(address(dispenser).balance, 0, "no value kept");
    }

    /// @dev A batch chain with both a paying and a zero-paying target still sends a message for the paying one, so
    ///      its value is forwarded and the claim does not revert.
    function test_fix31_claimBatch_mixedTargetsChainWithValue_forwardsValue() public {
        _nominateWithFullWeight();
        // Second target on the same chain with zero relative weight: below the staking weight threshold
        address target2 = address(0x57A7); // strictly greater than STAKING_TARGET (0x57A6) for ascending order
        vw.addNominee(target2, CHAIN_ID);
        _advanceEpoch();
        _advanceEpoch();

        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        bytes32[][] memory stakingTargets = new bytes32[][](1);
        stakingTargets[0] = new bytes32[](2);
        stakingTargets[0][0] = _targetBytes32();
        stakingTargets[0][1] = bytes32(uint256(uint160(target2)));
        bytes[] memory bridgePayloads = new bytes[](1);
        uint256[] memory valueAmounts = new uint256[](1);
        valueAmounts[0] = 1;

        vm.deal(address(this), 1 ether);
        dispenser.claimStakingIncentivesBatch{value: 1}(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);

        // Only the paying target is in the message
        assertEq(depositProcessor.lastStakingIncentive(), 10_000, "message carries the paying target");
        assertEq(depositProcessor.lastTransferAmount(), 10_000, "incentive transferred");
        assertEq(address(depositProcessor).balance, 1, "value forwarded");
        assertEq(address(dispenser).balance, 0, "no value kept");
    }

    /// @dev A claim fully covered by the withheld amount transfers no OLAS but still sends the bridge message, so
    ///      its value is forwarded and must keep being accepted.
    function test_fix31_claim_withheldCoveredWithValue_forwardsValue() public {
        _nominateWithFullWeight();
        // Withheld amount covers the whole weight-capped allocation of 10_000 wei
        dispenser.syncWithheldAmountMaintenance(CHAIN_ID, 10_000, bytes32(uint256(1)));
        _advanceEpoch();
        _advanceEpoch();

        vm.deal(address(this), 1 ether);
        dispenser.claimStakingIncentives{value: 1}(10, CHAIN_ID, _targetBytes32(), "");

        assertEq(depositProcessor.lastStakingIncentive(), 10_000, "message sent");
        assertEq(depositProcessor.lastTransferAmount(), 0, "no OLAS transferred");
        assertEq(address(depositProcessor).balance, 1, "value forwarded");
        assertEq(address(dispenser).balance, 0, "no value kept");
    }

    /// @dev In a batch, a chain with no staking incentive sends no message, so its value amount must be zero.
    function test_fix31_claimBatch_zeroIncentiveChainWithValue_reverts() public {
        _nominateWithFullWeight();
        MockDepositProcessor depositProcessor2 = _addSecondChainNominee();
        _advanceEpoch();
        _advanceEpoch();

        (uint256[] memory chainIds, bytes32[][] memory stakingTargets, bytes[] memory bridgePayloads) =
            _twoChainBatch();
        uint256[] memory valueAmounts = new uint256[](2);
        valueAmounts[0] = 1;
        valueAmounts[1] = 1;

        vm.deal(address(this), 1 ether);
        // CHAIN_ID_2 nets zero: its value amount would be kept
        vm.expectRevert(abi.encodeWithSignature("WrongAmount(uint256,uint256)", 1, 0));
        dispenser.claimStakingIncentivesBatch{value: 2}(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);

        // Value only for the chain that receives a message
        valueAmounts[1] = 0;
        dispenser.claimStakingIncentivesBatch{value: 1}(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);
        assertEq(address(depositProcessor).balance, 1, "value forwarded to the messaged chain");
        assertEq(address(depositProcessor2).balance, 0, "no value for the unmessaged chain");
        assertEq(address(dispenser).balance, 0, "no value kept");
    }

    /// @dev A batch with no staking incentive at all sends no message, so any value must be rejected.
    function test_fix31_claimBatch_zeroIncentiveWithValue_reverts() public {
        // No votes are ever cast on either chain
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
        _addSecondChainNominee();
        _advanceEpoch();
        _advanceEpoch();

        (uint256[] memory chainIds, bytes32[][] memory stakingTargets, bytes[] memory bridgePayloads) =
            _twoChainBatch();
        uint256[] memory valueAmounts = new uint256[](2);
        valueAmounts[0] = 1;

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("WrongAmount(uint256,uint256)", 1, 0));
        dispenser.claimStakingIncentivesBatch{value: 1}(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);

        valueAmounts[0] = 0;
        dispenser.claimStakingIncentivesBatch(10, chainIds, stakingTargets, bridgePayloads, valueAmounts);
        assertEq(address(dispenser).balance, 0, "no value kept");
    }
}
