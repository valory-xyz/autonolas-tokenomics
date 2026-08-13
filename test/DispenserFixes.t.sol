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
///      #12 zero-weight epoch refund is atomic with its one-way flag (public calculateStakingIncentives
///          can no longer permanently strand the refund);
///      #9  the withheld-covered portion of claimed incentives is returned to staking inflation
///          (single and batch claim paths);
///      #25 addNominee clears mapRemovedNomineeEpochs so a removed-then-re-added nominee is claimable;
///      #8  changeManagers only swaps voteWeighting while staking incentives are paused.
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
        Dispenser dispenserMaster = new Dispenser(address(olas), address(tokenomics), retainer, 100, 1 ether);
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

    // -----------------------------------------------------------------------
    // #12 — zero-weight epoch refund is atomic with the one-way flag
    // -----------------------------------------------------------------------

    /// @dev A standalone external call to the public calculateStakingIncentives on a zero-total-weight epoch
    ///      must execute the refund in the same transaction it sets mapZeroWeightEpochRefunded. On the pre-fix
    ///      code the flag was set but the refund was left to the caller, permanently stranding the epoch's
    ///      staking inflation.
    function test_fix12_standaloneCalculate_zeroWeight_refundsAtomically() public {
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

        // Standalone state-mutating call by an arbitrary account (NOT via the claim path)
        vm.prank(address(0xA77ACC));
        dispenser.calculateStakingIncentives(10, CHAIN_ID, _targetBytes32(), 18);

        // The one-way flag is set...
        assertTrue(dispenser.mapZeroWeightEpochRefunded(claimableEpoch), "zero-weight flag must be set");

        // ...and the refund happened in the same tx: the epoch's incentive is back in the staking pot
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, epochIncentive, "flagged epoch incentive must be refunded atomically");

        // A subsequent claim skips the refunded epoch and must not refund it again
        dispenser.claimStakingIncentives(10, CHAIN_ID, _targetBytes32(), "");
        uint256 potFinal = _stakingIncentiveOf(currentEpoch);
        assertEq(potFinal, potAfter, "no double refund on the claim path");
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
}
