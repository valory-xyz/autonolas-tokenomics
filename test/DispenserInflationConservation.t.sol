// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Dispenser} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";
import {Tokenomics} from "../contracts/Tokenomics.sol";
import {TokenomicsProxy} from "../contracts/proxies/TokenomicsProxy.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {MockRegistry} from "../contracts/test/MockRegistry.sol";
import {MockVE} from "../contracts/test/MockVE.sol";
import {GnosisDepositProcessorL1} from "../contracts/staking/GnosisDepositProcessorL1.sol";
import {GnosisTargetDispenserL2} from "../contracts/staking/GnosisTargetDispenserL2.sol";

/// @dev One nominee owns all weight; voting-power and per-target caps do not bind.
contract ConservationVoteWeighting {
    function nominate(Dispenser dispenser, bytes32 nomineeHash) external {
        dispenser.addNominee(nomineeHash);
    }

    function checkpointNominee(bytes32, uint256) external pure {}

    function nomineeRelativeWeight(bytes32, uint256, uint256) external pure returns (uint256, uint256) {
        return (1e18, type(uint96).max);
    }
}

/// @dev Transfers existing tokens (never mints a second cross-chain representation).
/// Messages are queued separately. Replays reach the real receiver's replay protection.
contract ConservationBridge {
    struct Message {
        address source;
        address target;
        bytes data;
    }

    Message[] internal messages;
    address public messageSender;

    function relayTokens(address token, address receiver, uint256 amount) external {
        require(ERC20Token(token).transferFrom(msg.sender, receiver, amount));
    }

    function requireToPassMessage(address target, bytes calldata data, uint256) external returns (bytes32) {
        messages.push(Message(msg.sender, target, data));
        return bytes32(messages.length);
    }

    function count() external view returns (uint256) {
        return messages.length;
    }

    function deliver(uint256 index) external {
        Message storage message = messages[index];
        messageSender = message.source;
        (bool success, bytes memory result) = message.target.call(message.data);
        if (!success) {
            assembly { revert(add(result, 32), mload(result)) }
        }
        messageSender = address(0);
    }
}

contract ConservationStakingFactory {
    uint256 public limit = type(uint96).max;

    function setLimit(uint256 amount) external {
        limit = amount;
    }

    function verifyInstanceAndGetEmissionsAmount(address) external view returns (uint256) {
        return limit;
    }
}

contract ConservationStakingTarget {
    ERC20Token internal immutable token;

    constructor(ERC20Token _token) {
        token = _token;
    }

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount));
    }
}

/// @dev Eight-decimal fixtures exercise the inherited precision boundary; production Gnosis uses 18.
contract ConservationPrecisionProcessor is GnosisDepositProcessorL1 {
    constructor(address token, address l1, address bridge, uint256 chain)
        GnosisDepositProcessorL1(token, l1, bridge, bridge, chain)
    {}

    function getBridgingDecimals() external pure override returns (uint256) {
        return 8;
    }
}

contract ConservationPrecisionReceiver is GnosisTargetDispenserL2 {
    constructor(address token, address factory, address bridge, address processor, uint256 source)
        GnosisTargetDispenserL2(token, factory, bridge, processor, source)
    {}

    function getBridgingDecimals() public pure override returns (uint256) {
        return 8;
    }
}

/// @notice Conservation of freshly scheduled staking inflation across real Gnosis accounting paths.
/// @dev Deliberately uses a permissive ERC20: a global token cap must not mask an accounting regression.
/// No burns, other minters, pre-existing entitlements, or storage overrides. Migration restoration uses
/// only balances transferred from the retired receiver; no synthetic L1 credit is injected.
/// One full-weight nominee makes outstanding entitlement observable without weight-rounding ambiguity.
contract DispenserInflationConservationTest is Test {
    uint256 internal constant CHAIN_ID = 100;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant EPOCH = 30 days;
    bytes32 internal constant TRANSFER = keccak256("Transfer(address,address,uint256)");

    ERC20Token internal olas;
    Tokenomics internal tokenomics;
    Treasury internal treasury;
    Dispenser internal dispenser;
    GnosisDepositProcessorL1 internal processor;
    GnosisTargetDispenserL2 internal receiver;
    ConservationBridge internal bridge;
    ConservationStakingFactory internal factory;
    ConservationStakingTarget internal target;
    bytes32 internal targetId;
    bytes32 internal nomineeHash;
    uint256 internal launch;
    uint256 internal scheduled;
    uint256 internal minted;

    function setUp() public {
        vm.warp(1_800_000_000);
        olas = new ERC20Token();
        launch = block.timestamp;
        MockRegistry registry = new MockRegistry();
        MockVE ve = new MockVE();
        treasury = new Treasury(address(olas), address(this), address(this), address(this));
        Tokenomics implementation = new Tokenomics();
        tokenomics = Tokenomics(
            address(
                new TokenomicsProxy(
                    address(implementation),
                    abi.encodeCall(
                        implementation.initializeTokenomics,
                        (
                            address(olas),
                            address(treasury),
                            address(this),
                            address(this),
                            address(ve),
                            EPOCH,
                            address(registry),
                            address(registry),
                            address(registry),
                            address(0)
                        )
                    )
                )
            )
        );
        Dispenser dispenserImplementation = new Dispenser(address(olas), address(tokenomics), bytes32(uint256(1)));
        dispenser = Dispenser(
            address(
                new DispenserProxy(
                    address(dispenserImplementation),
                    abi.encodeCall(dispenserImplementation.initialize, (address(treasury), address(this), 100, 100))
                )
            )
        );
        ConservationVoteWeighting voting = new ConservationVoteWeighting();
        dispenser.changeManagers(address(0), address(voting));
        treasury.changeManagers(address(tokenomics), address(0), address(dispenser));
        tokenomics.changeManagers(address(0), address(0), address(dispenser));
        olas.changeMinter(address(treasury));

        bridge = new ConservationBridge();
        factory = new ConservationStakingFactory();
        target = new ConservationStakingTarget(olas);
        targetId = bytes32(uint256(uint160(address(target))));
        nomineeHash = keccak256(abi.encode(targetId, CHAIN_ID));
        processor =
            new GnosisDepositProcessorL1(address(olas), address(dispenser), address(bridge), address(bridge), CHAIN_ID);
        receiver = new GnosisTargetDispenserL2(
            address(olas), address(factory), address(bridge), address(processor), block.chainid
        );
        processor.setL2TargetDispenser(address(receiver));
        address[] memory processors = new address[](1);
        processors[0] = address(processor);
        uint256[] memory chains = new uint256[](1);
        chains[0] = CHAIN_ID;
        dispenser.setDepositProcessorChainIds(processors, chains);
        tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 100);
        tokenomics.changeStakingParams(type(uint96).max, 1);
        dispenser.setPauseState(Dispenser.Pause.Unpaused);

        // Epoch 1 has no staking allocation; nominate only once the requested parameters activate.
        vm.warp(block.timestamp + EPOCH);
        vm.roll(block.number + 1);
        assertTrue(tokenomics.checkpoint());
        assertEq(_pot(1), 0);
        voting.nominate(dispenser, nomineeHash);
        _assertConservation();
    }

    /// @dev Independent schedule oracle, pinned to the first four years used by these tests.
    /// Rates are floored BEFORE multiplying by seconds, matching the specified integer schedule.
    /// Does not read refunded staking pots, inflationPerSecond, or getInflationForYear.
    function _freshBudget(uint256 start, uint256 end) internal view returns (uint256 budget) {
        uint256[4] memory annual = [uint256(3_159_000 ether), 40_254_084 ether, 40_400_000 ether, 25_260_023 ether];
        while (start < end) {
            uint256 year = (start - launch) / YEAR;
            require(year < annual.length, "extend independent schedule oracle");
            uint256 boundary = launch + (year + 1) * YEAR;
            uint256 until = end < boundary ? end : boundary;
            budget += (until - start) * (annual[year] / YEAR);
            start = until;
        }
    }

    function _pot(uint256 epoch) internal view returns (uint256 amount) {
        (amount,,,) = tokenomics.mapEpochStakingPoints(epoch);
    }

    /// @dev Current pot is refunds only. Historical pots remain stored after a claim, so include
    /// only epochs at/after the ACTUAL claim cursor, not every historical stakingIncentive value.
    function _remainingAllowance() internal view returns (uint256 amount) {
        uint256 current = tokenomics.epochCounter();
        amount = _pot(current);
        for (uint256 epoch = dispenser.mapLastClaimedStakingEpochs(nomineeHash); epoch < current; ++epoch) {
            amount += _pot(epoch);
        }
    }

    function _assertConservation() internal view {
        assertLe(minted, scheduled, "fresh minting exceeds independently scheduled staking inflation");
        assertEq(minted + _remainingAllowance(), scheduled, "minted + outstanding allowance != fresh budgets");
        assertEq(olas.totalSupply(), minted, "mint log accounting must cover all issuance");
        assertEq(
            olas.balanceOf(address(target)) + olas.balanceOf(address(receiver)) + olas.balanceOf(address(processor))
                + olas.balanceOf(address(dispenser)),
            minted,
            "all minted tokens accounted for"
        );
    }

    function _settle(uint256 duration) internal returns (uint256 fresh) {
        uint256 epoch = tokenomics.epochCounter();
        uint256 start = tokenomics.getEpochEndTime(epoch - 1);
        uint256 carry = _pot(epoch);
        vm.warp(start + duration);
        vm.roll(block.number + 1);
        fresh = _freshBudget(start, start + duration);
        assertTrue(tokenomics.checkpoint());
        scheduled += fresh;
        assertEq(_pot(epoch), fresh + carry, "checkpoint adds only fresh inflation to existing refund");
        _assertConservation();
    }

    function _claim(bool batch) internal returns (uint256 messageIndex, uint256 newlyMinted) {
        messageIndex = bridge.count();
        vm.recordLogs();
        if (batch) {
            uint256[] memory chains = new uint256[](1);
            chains[0] = CHAIN_ID;
            bytes32[][] memory targets = new bytes32[][](1);
            targets[0] = new bytes32[](1);
            targets[0][0] = targetId;
            bytes[] memory payloads = new bytes[](1);
            uint256[] memory values = new uint256[](1);
            dispenser.claimStakingIncentivesBatch(100, chains, targets, payloads, values);
        } else {
            dispenser.claimStakingIncentives(100, CHAIN_ID, targetId, "");
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(olas) && logs[i].topics.length == 3 && logs[i].topics[0] == TRANSFER
                    && logs[i].topics[1] == bytes32(0)
            ) {
                newlyMinted += abi.decode(logs[i].data, (uint256));
            }
        }
        minted += newlyMinted;
        assertEq(bridge.count(), messageIndex + 1, "claim posts one message even when fresh mint is zero");
        _assertConservation();
    }

    function _deliver(uint256 index) internal {
        bridge.deliver(index);
        _assertConservation();
    }

    function _sync() internal returns (uint256 index) {
        uint256 amount = receiver.withheldAmount();
        assertGt(amount, 0);
        uint256 oldCredit = dispenser.mapChainIdWithheldAmounts(CHAIN_ID);
        index = bridge.count();
        receiver.requestWithheldAmountSync("");
        _assertConservation();
        receiver.relayWithheldAmountSync();
        _assertConservation();
        assertEq(receiver.withheldAmount(), 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), oldCredit, "credit waits for message delivery");
        _deliver(index);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), oldCredit + amount);
        assertLe(oldCredit + amount, olas.balanceOf(address(receiver)), "synced credit is backed by tokens");
    }

    function _recycleThenSpend(bool batch) internal {
        uint256 b1 = _settle(EPOCH);
        uint256 withheld = b1 / 2;
        factory.setLimit(b1 - withheld);
        (uint256 messageIndex, uint256 freshMint) = _claim(batch);
        assertEq(freshMint, b1);
        _deliver(messageIndex);
        assertEq(receiver.withheldAmount(), withheld);
        assertEq(olas.balanceOf(address(receiver)), withheld);
        _sync();

        uint256 b2 = _settle(EPOCH);
        factory.setLimit(type(uint96).max);
        (messageIndex, freshMint) = _claim(batch);
        assertEq(freshMint, b2 - withheld);
        assertEq(_pot(tokenomics.epochCounter()), withheld, "reused portion restored exactly once");
        _deliver(messageIndex);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        assertEq(olas.balanceOf(address(receiver)), 0);

        uint256 b3 = _settle(EPOCH);
        (messageIndex, freshMint) = _claim(batch);
        assertEq(freshMint, b3 + withheld, "spend the restored allowance, not just inspect it");
        _deliver(messageIndex);
        assertEq(_remainingAllowance(), 0);
        assertEq(minted, b1 + b2 + b3);
        assertEq(olas.balanceOf(address(target)), minted);
    }

    function test_recycleThenSpend_single() public {
        _recycleThenSpend(false);
    }

    function test_recycleThenSpend_batch() public {
        _recycleThenSpend(true);
    }

    function _claimSeveralEpochsWithRefund(bool batch) internal {
        uint256 b1 = _settle(EPOCH);
        factory.setLimit(0);
        (uint256 index,) = _claim(batch);
        _deliver(index);
        assertEq(receiver.withheldAmount(), b1);
        _sync();

        uint256 b2 = _settle(EPOCH);
        factory.setLimit(type(uint96).max);
        uint256 freshMint;
        (index, freshMint) = _claim(batch);
        assertEq(freshMint, 0, "credit covers the entire second epoch");
        _deliver(index);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        uint256 firstUnclaimed = dispenser.mapLastClaimedStakingEpochs(nomineeHash);
        assertEq(_pot(firstUnclaimed), b2, "refund waits in the current epoch");

        // Do not claim between checkpoints: the first pot includes the refund, the next two are fresh.
        uint256 b3 = _settle(EPOCH);
        assertEq(_pot(firstUnclaimed), b3 + b2);
        uint256 b4 = _settle(EPOCH);
        uint256 b5 = _settle(EPOCH);
        assertEq(dispenser.mapLastClaimedStakingEpochs(nomineeHash), firstUnclaimed, "cursor waits for claim");
        assertEq(tokenomics.epochCounter(), firstUnclaimed + 3);
        assertEq(_remainingAllowance(), b2 + b3 + b4 + b5);

        (index, freshMint) = _claim(batch);
        assertEq(freshMint, b2 + b3 + b4 + b5, "one claim spends the refund and all three fresh pots");
        assertEq(dispenser.mapLastClaimedStakingEpochs(nomineeHash), firstUnclaimed + 3);
        _deliver(index);
        assertEq(_remainingAllowance(), 0);
        assertEq(receiver.withheldAmount(), 0);
        assertEq(olas.balanceOf(address(receiver)), 0);
        assertEq(minted, b1 + b2 + b3 + b4 + b5);
        assertEq(olas.balanceOf(address(target)), minted);
    }

    function test_claimSeveralEpochsWithRefund_single() public {
        _claimSeveralEpochsWithRefund(false);
    }

    function test_claimSeveralEpochsWithRefund_batch() public {
        _claimSeveralEpochsWithRefund(true);
    }

    function test_creditLargerThanNextClaim_zeroFreshMint() public {
        uint256 b1 = _settle(3 * EPOCH);
        factory.setLimit(0);
        (uint256 messageIndex,) = _claim(false);
        _deliver(messageIndex);
        _sync();
        uint256 b2 = _settle(EPOCH);
        factory.setLimit(type(uint96).max);
        uint256 freshMint;
        (messageIndex, freshMint) = _claim(true);
        assertEq(freshMint, 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), b1 - b2);
        assertEq(_pot(tokenomics.epochCounter()), b2);
        _deliver(messageIndex);
        assertEq(olas.balanceOf(address(receiver)), b1 - b2);
        _drain();
    }

    function test_delayedSync_andMessageReplays() public {
        _settle(EPOCH);
        factory.setLimit(0);
        (uint256 firstMessage,) = _claim(false);
        _deliver(firstMessage);
        uint256 firstWithheld = receiver.withheldAmount();
        uint256 syncMessage = bridge.count();
        receiver.requestWithheldAmountSync("");
        receiver.relayWithheldAmountSync();
        _assertConservation();
        // L1 cannot net an in-flight sync. A second legitimate claim mints its full budget.
        uint256 b2 = _settle(EPOCH);
        (uint256 secondMessage, uint256 freshMint) = _claim(true);
        assertEq(freshMint, b2);
        // L2 reads the acceptance limit at message delivery, so changing it after the L1 claim is intentional.
        factory.setLimit(type(uint96).max);
        _deliver(secondMessage);
        _deliver(syncMessage);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), firstWithheld);

        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        bridge.deliver(syncMessage);
        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        bridge.deliver(firstMessage);
        vm.expectPartialRevert(bytes4(keccak256("Overflow(uint256,uint256)")));
        dispenser.claimStakingIncentives(100, CHAIN_ID, targetId, "");
        _assertConservation();
        _drain();
    }

    function test_recyclingAcrossDecreasingInflationYear() public {
        // Reach the end of year index 2 using real checkpoints, not storage overrides.
        // Use the cheatcode getter: the compiler may cache block.timestamp across vm.warp calls.
        while (vm.getBlockTimestamp() + 2 * EPOCH < launch + 3 * YEAR) {
            _settle(EPOCH);
            (uint256 messageIndex,) = _claim(false);
            _deliver(messageIndex);
        }
        assertEq(tokenomics.currentYear(), 2);
        // Create actual withheld credit before the boundary, then reuse it across the rate decrease.
        factory.setLimit(0);
        _settle(EPOCH);
        assertEq(tokenomics.currentYear(), 2);
        (uint256 index,) = _claim(true);
        _deliver(index);
        _sync();
        _settle(EPOCH);
        assertEq(tokenomics.currentYear(), 3);
        factory.setLimit(type(uint96).max);
        (index,) = _claim(false);
        _deliver(index);
        _drain();
    }

    function test_fullCredit_reusedTokensWithheldAgain() public {
        uint256 b1 = _settle(EPOCH);
        factory.setLimit(0);
        (uint256 index,) = _claim(false);
        _deliver(index);
        _sync();
        _settle(EPOCH);
        uint256 freshMint;
        (index, freshMint) = _claim(true);
        assertEq(freshMint, 0, "equal credit covers the entire second claim");
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        _deliver(index);
        assertEq(receiver.withheldAmount(), b1, "same funded tokens withheld a second time");
        assertEq(olas.balanceOf(address(receiver)), b1);
        _sync();
        _drain();
    }

    /// @dev Bounded stateful sequences: each step settles, claims, delivers, and optionally syncs.
    /// Varies full/partial/no acceptance, checkpoint delay, and claim entry point. No discarded runs.
    function testFuzz_repeatedRecycling(uint256 seed) public {
        for (uint256 i; i < 12; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            _settle(EPOCH + seed % (7 days));
            uint256 entitlement = _remainingAllowance();
            uint256 mode = (seed >> 32) % 3;
            factory.setLimit(mode == 0 ? 0 : mode == 1 ? entitlement / 2 : type(uint96).max);
            (uint256 index,) = _claim(seed & 1 == 1);
            _deliver(index);
            if (receiver.withheldAmount() > 0 && (seed >> 64) & 1 == 1) {
                _sync();
            }
        }
        _drain();
    }

    /// @dev Swap all three accounting endpoints; the new L1 remains paused until reconciliation.
    function _replaceStakingPair(bool reducedPrecision) internal {
        dispenser.setPauseState(Dispenser.Pause.StakingIncentivesPaused);
        address voting = dispenser.voteWeighting();
        Dispenser implementation = new Dispenser(address(olas), address(tokenomics), bytes32(uint256(1)));
        Dispenser replacement = Dispenser(
            address(
                new DispenserProxy(
                    address(implementation),
                    abi.encodeCall(implementation.initialize, (address(treasury), voting, 100, 100))
                )
            )
        );
        GnosisDepositProcessorL1 nextProcessor;
        GnosisTargetDispenserL2 nextReceiver;
        if (reducedPrecision) {
            nextProcessor =
                new ConservationPrecisionProcessor(address(olas), address(replacement), address(bridge), CHAIN_ID);
            nextReceiver = new ConservationPrecisionReceiver(
                address(olas), address(factory), address(bridge), address(nextProcessor), block.chainid
            );
        } else {
            nextProcessor = new GnosisDepositProcessorL1(
                address(olas), address(replacement), address(bridge), address(bridge), CHAIN_ID
            );
            nextReceiver = new GnosisTargetDispenserL2(
                address(olas), address(factory), address(bridge), address(nextProcessor), block.chainid
            );
        }
        nextProcessor.setL2TargetDispenser(address(nextReceiver));
        address[] memory routes = new address[](1);
        routes[0] = address(nextProcessor);
        uint256[] memory chains = new uint256[](1);
        chains[0] = CHAIN_ID;
        replacement.setDepositProcessorChainIds(routes, chains);
        if (receiver.paused() == 1) receiver.pause();
        uint256 carried = olas.balanceOf(address(receiver));
        receiver.migrate(address(nextReceiver));
        assertEq(olas.balanceOf(address(receiver)), 0);
        assertEq(olas.balanceOf(address(nextReceiver)), carried);
        assertEq(receiver.owner(), address(0));
        assertEq(nextReceiver.withheldAmount(), 0);
        dispenser = replacement;
        processor = nextProcessor;
        receiver = nextReceiver;
        treasury.changeManagers(address(0), address(0), address(dispenser));
        tokenomics.changeManagers(address(0), address(0), address(dispenser));
        assertEq(uint256(dispenser.paused()), uint256(Dispenser.Pause.StakingIncentivesPaused));
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
    }

    function _assertRestartPaused() internal {
        vm.expectPartialRevert(bytes4(keccak256("Paused()")));
        dispenser.claimStakingIncentives(100, CHAIN_ID, targetId, "");
        // Nomination, like claims, is pause-gated: it belongs after the accounting restart gate.
        ConservationVoteWeighting voting = ConservationVoteWeighting(dispenser.voteWeighting());
        vm.expectPartialRevert(bytes4(keccak256("Paused()")));
        voting.nominate(dispenser, nomineeHash);
    }

    function _resumeAndNominate() internal {
        dispenser.setPauseState(Dispenser.Pause.Unpaused);
        ConservationVoteWeighting(dispenser.voteWeighting()).nominate(dispenser, nomineeHash);
        _assertConservation();
    }

    function _requestData(uint256 amount, bytes32 batchHash) internal view returns (bytes memory) {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return abi.encode(targets, amounts, batchHash);
    }

    function _lateOldSyncMigration(bool oldCallbackFirst, bool reducedPrecision) internal {
        uint256 b1 = _settle(EPOCH);
        uint256 reserve = b1 / 2 + 1;
        // Keep a nonzero remainder in the explicit eight-decimal boundary fixture.
        if (reducedPrecision && reserve % 1e10 == 0) ++reserve;
        factory.setLimit(b1 - reserve);
        (uint256 distribution,) = _claim(false);
        _deliver(distribution);
        assertEq(olas.balanceOf(address(receiver)), reserve);
        uint256 oldSync = bridge.count();
        receiver.requestWithheldAmountSync("");
        receiver.relayWithheldAmountSync();
        assertEq(receiver.withheldAmount(), 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        Dispenser retired = dispenser;
        _replaceStakingPair(reducedPrecision);
        _assertRestartPaused();
        if (oldCallbackFirst) bridge.deliver(oldSync);
        assertEq(retired.mapChainIdWithheldAmounts(CHAIN_ID), oldCallbackFirst ? reserve : 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "retired callback is not active credit");

        receiver.updateWithheldAmountMaintenance(olas.balanceOf(address(receiver)));
        assertEq(receiver.withheldAmount(), reserve);
        uint256 quantum = reducedPrecision ? 1e10 : 1;
        uint256 normalized = reserve / quantum * quantum;
        uint256 remainder = reserve - normalized;
        uint256 nextNonce = receiver.stakingBatchNonce();
        bytes32 syncHash = keccak256(abi.encode(nextNonce, block.chainid, address(receiver)));
        uint256 newSync = bridge.count();
        receiver.requestWithheldAmountSync("");
        receiver.relayWithheldAmountSync();
        assertEq(receiver.withheldAmount(), remainder);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "source send is not receipt");
        _assertRestartPaused();
        bridge.deliver(newSync);
        assertTrue(processor.processedHashes(syncHash));
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), normalized);
        if (!oldCallbackFirst) bridge.deliver(oldSync);
        assertEq(retired.mapChainIdWithheldAmounts(CHAIN_ID), reserve);
        assertEq(
            dispenser.mapChainIdWithheldAmounts(CHAIN_ID), normalized, "late old receipt cannot duplicate active credit"
        );
        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        bridge.deliver(newSync);
        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        bridge.deliver(oldSync);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), normalized);
        assertEq(olas.balanceOf(address(receiver)), normalized + remainder, "each reserve component backed once");
        _assertRestartPaused();
        _resumeAndNominate();
        _settle(EPOCH);
        (uint256 payableAmount, uint256 ordinaryReturn,,,) =
            dispenser.calculateStakingIncentives(100, CHAIN_ID, targetId, 18);
        // The receiver/processor precision fixture exercises the shared normalization rule, not a Gnosis setting.
        if (reducedPrecision) {
            (payableAmount, ordinaryReturn,,,) = dispenser.calculateStakingIncentives(100, CHAIN_ID, targetId, 8);
        }
        assertGt(payableAmount, normalized);
        factory.setLimit(type(uint96).max);
        uint256 potBefore = _pot(tokenomics.epochCounter());
        uint256 freshMint;
        (distribution, freshMint) = _claim(oldCallbackFirst);
        assertEq(freshMint, payableAmount - normalized);
        assertEq(_pot(tokenomics.epochCounter()) - potBefore, ordinaryReturn + normalized);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        _deliver(distribution);
        assertEq(olas.balanceOf(address(receiver)), remainder);
        assertEq(receiver.withheldAmount(), remainder);
        if (reducedPrecision) {
            assertGt(remainder, 0);
            receiver.requestWithheldAmountSync("");
            vm.expectPartialRevert(bytes4(keccak256("ZeroValue()")));
            receiver.relayWithheldAmountSync();
            assertEq(receiver.withheldAmount(), remainder, "sub-quantum remainder stays on L2");
        }
    }

    function test_migration_oldCallbackBeforeReplacementSync() public {
        _lateOldSyncMigration(true, false);
    }

    function test_migration_oldCallbackAfterReplacementSync() public {
        _lateOldSyncMigration(false, false);
    }

    function test_migration_normalizedSyncRetainsRemainder() public {
        _lateOldSyncMigration(true, true);
    }

    function test_migration_replayUnpaidBeforeSyncThenConsumeCredit() public {
        uint256 b1 = _settle(EPOCH);
        uint256 reserve = b1 / 2;
        factory.setLimit(b1 - reserve);
        (uint256 firstDistribution,) = _claim(false);
        _deliver(firstDistribution);
        uint256 oldSync = bridge.count();
        receiver.requestWithheldAmountSync("");
        receiver.relayWithheldAmountSync();
        uint256 b2 = _settle(EPOCH);
        factory.setLimit(type(uint96).max);
        receiver.pause();
        bytes32 batchHash = keccak256(abi.encode(processor.stakingBatchNonce(), block.chainid, address(processor)));
        (uint256 queuedDistribution,) = _claim(true);
        _deliver(queuedDistribution);
        bytes32 oldQueue = keccak256(abi.encode(address(target), b2, batchHash, block.chainid, address(receiver)));
        assertTrue(receiver.queuedHashes(oldQueue));
        assertTrue(receiver.processedHashes(batchHash));
        GnosisTargetDispenserL2 retiredReceiver = receiver;
        Dispenser retired = dispenser;
        uint256 paidBefore = olas.balanceOf(address(target));
        _replaceStakingPair(false);
        _assertRestartPaused();
        receiver.updateWithheldAmountMaintenance(olas.balanceOf(address(receiver)));
        assertEq(receiver.withheldAmount(), reserve + b2);
        bytes memory data = _requestData(b2, batchHash);
        receiver.processDataMaintenance(data, true);
        assertEq(olas.balanceOf(address(target)) - paidBefore, b2);
        assertEq(olas.balanceOf(address(receiver)), reserve);
        assertEq(receiver.withheldAmount(), reserve);
        assertTrue(receiver.processedHashes(batchHash));
        assertTrue(
            retiredReceiver.queuedHashes(oldQueue), "retired flags stay historical; ledger records replacement payment"
        );
        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        receiver.processDataMaintenance(data, true);
        assertEq(receiver.withheldAmount(), reserve);
        uint256 newSync = bridge.count();
        receiver.requestWithheldAmountSync("");
        receiver.relayWithheldAmountSync();
        bridge.deliver(newSync);
        bridge.deliver(oldSync);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), reserve);
        assertEq(retired.mapChainIdWithheldAmounts(CHAIN_ID), reserve);
        _resumeAndNominate();
        uint256 b3 = _settle(EPOCH);
        (uint256 distribution, uint256 freshMint) = _claim(false);
        assertEq(freshMint, b3 - reserve);
        _deliver(distribution);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        assertEq(receiver.withheldAmount(), 0);
        assertEq(olas.balanceOf(address(receiver)), 0);
        assertEq(olas.balanceOf(address(target)), minted);
    }

    function test_migration_replayIneligibleUnpaidRequestConsumesHashWithoutPayment() public {
        uint256 budget = _settle(EPOCH);
        receiver.pause();
        bytes32 batchHash = keccak256(abi.encode(processor.stakingBatchNonce(), block.chainid, address(processor)));
        (uint256 distribution,) = _claim(false);
        _deliver(distribution);
        bytes32 oldQueue = keccak256(abi.encode(address(target), budget, batchHash, block.chainid, address(receiver)));
        assertTrue(receiver.queuedHashes(oldQueue));
        GnosisTargetDispenserL2 retiredReceiver = receiver;

        _replaceStakingPair(false);
        _assertRestartPaused();
        receiver.updateWithheldAmountMaintenance(olas.balanceOf(address(receiver)));
        assertEq(receiver.withheldAmount(), budget);
        uint256 paidBefore = olas.balanceOf(address(target));

        // Model the zero factory result produced by an instance disabled after its request was queued.
        factory.setLimit(0);
        bytes memory data = _requestData(budget, batchHash);
        receiver.processDataMaintenance(data, true);
        assertEq(olas.balanceOf(address(target)), paidBefore, "processed batch does not establish payment");
        assertEq(olas.balanceOf(address(receiver)), budget);
        assertEq(receiver.withheldAmount(), budget, "unpaid backing remains in the raw withheld counter");
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        assertTrue(receiver.processedHashes(batchHash));
        bytes32 newQueue = keccak256(abi.encode(address(target), budget, batchHash, block.chainid, address(receiver)));
        assertFalse(receiver.queuedHashes(newQueue), "rejected replay creates no redeemable replacement queue");
        assertTrue(retiredReceiver.queuedHashes(oldQueue), "retired flags remain historical evidence");

        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        receiver.processDataMaintenance(data, true);
        factory.setLimit(type(uint96).max);
        vm.expectPartialRevert(bytes4(keccak256("AlreadyDelivered(bytes32)")));
        receiver.processDataMaintenance(data, true);
        assertEq(olas.balanceOf(address(target)), paidBefore);
        assertEq(receiver.withheldAmount(), budget);
        _assertRestartPaused();
    }

    function test_migration_zeroReserveNeedsNoSync() public {
        _settle(EPOCH);
        (uint256 distribution,) = _claim(false);
        _deliver(distribution);
        assertEq(olas.balanceOf(address(receiver)), 0);
        _replaceStakingPair(false);
        _assertRestartPaused();
        receiver.updateWithheldAmountMaintenance(olas.balanceOf(address(receiver)));
        assertEq(receiver.withheldAmount(), 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0);
        uint256 messagesBefore = bridge.count();
        // The zero-reserve path sends no sync and leaves no armed request.
        assertFalse(receiver.syncPending());
        _resumeAndNominate();
        assertEq(bridge.count(), messagesBefore);
        uint256 freshBudget = _settle(EPOCH);
        uint256 freshMint;
        (distribution, freshMint) = _claim(true);
        assertEq(freshMint, freshBudget);
        _deliver(distribution);
    }

    /// @dev End every sequence by spending refunds until all issued tokens reach the recipient.
    /// New epochs still create fresh budgets; they are added independently, never mistaken for refunds.
    function _drain() internal {
        if (receiver.withheldAmount() > 0) _sync();
        factory.setLimit(type(uint96).max);
        for (uint256 i; i < 16; ++i) {
            if (dispenser.mapChainIdWithheldAmounts(CHAIN_ID) == 0 && _remainingAllowance() == 0) break;
            _settle(EPOCH);
            (uint256 index,) = _claim(i % 2 == 0);
            _deliver(index);
        }
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "all credit consumed");
        assertEq(receiver.withheldAmount(), 0);
        assertEq(_remainingAllowance(), 0, "all restored allowance spent");
        assertEq(olas.balanceOf(address(receiver)), 0);
        assertEq(olas.balanceOf(address(target)), scheduled);
        _assertConservation();
    }
}
