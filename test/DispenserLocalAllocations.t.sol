// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Dispenser, WrongAmount} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";
import {Tokenomics} from "../contracts/Tokenomics.sol";
import {TokenomicsProxy} from "../contracts/proxies/TokenomicsProxy.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {MockRegistry} from "../contracts/test/MockRegistry.sol";
import {MockVE} from "../contracts/test/MockVE.sol";
import {EthereumDepositProcessor, TargetEmissionsZero} from "../contracts/staking/EthereumDepositProcessor.sol";
import {MockVoteWeightingHistory, MockDepositProcessor} from "./DispenserFixes.t.sol";
import {StakingFactory} from "./fixtures/registries/StakingFactory.sol";
import {StakingVerifier} from "./fixtures/registries/StakingVerifier.sol";

/// @dev Parameterized staking implementation behind the real factory's StakingProxy.
contract LocalStakingFixture {
    ERC20Token public immutable stakingToken;
    address public immutable serviceRegistry;
    uint256 public constant minStakingDeposit = 1 ether;
    uint256 public constant rewardsPerSecond = 1 gwei;
    uint256 public constant timeForEmissions = 30 days;
    uint256 public constant maxNumServices = 1;
    uint256 internal emissions;
    uint256 public deposited;
    bool public failEmissions;
    bool public failDeposit;

    constructor(ERC20Token token, address registry) {
        stakingToken = token;
        serviceRegistry = registry;
    }

    function initialize(uint256 amount) external {
        emissions = amount;
    }

    function setEmissions(uint256 amount) external {
        emissions = amount;
    }

    function setFailures(bool readFailure, bool depositFailure) external {
        failEmissions = readFailure;
        failDeposit = depositFailure;
    }

    function emissionsAmount() external view returns (uint256) {
        require(!failEmissions, "emissions unavailable");
        return emissions;
    }

    function deposit(uint256 amount) external {
        require(!failDeposit, "deposit unavailable");
        stakingToken.transferFrom(msg.sender, address(this), amount);
        deposited += amount;
    }
}

/// @dev Arbitrary registration responses, including revert and out-of-gas cases.
contract RegistrationResponseFixture {
    bytes internal response;
    uint256 internal mode;

    function configure(bytes memory data, uint256 failureMode) external {
        response = data;
        mode = failureMode;
    }

    fallback() external {
        require(mode != 1, "registration unavailable");
        if (mode == 2) {
            assembly { for {} 1 {} {} }
        }
        bytes memory data = response;
        assembly { return(add(data, 32), mload(data)) }
    }
}

contract DispenserLocalAllocationsTest is Test {
    event LocalAllocationReturned(bytes32 indexed nomineeHash, uint256 firstEpoch, uint256 endEpoch, uint256 amount);

    ERC20Token internal olas;
    Tokenomics internal tokenomics;
    Treasury internal treasury;
    Dispenser internal dispenser;
    MockVoteWeightingHistory internal vw;
    StakingFactory internal factory;
    StakingVerifier internal verifier;
    EthereumDepositProcessor internal processor;
    LocalStakingFixture internal implementation;
    address internal constant TIMELOCK = address(0xDA0);
    address internal constant UNKNOWN = address(0xBEEF);
    uint256 internal constant REMOTE = 100;
    uint256 internal constant EPOCH = 30 days;
    address[] internal nominees;
    uint256[] internal nomineeChains;
    uint256[] internal weights;

    function setUp() public {
        olas = new ERC20Token();
        address registry = address(new MockRegistry());
        treasury = new Treasury(address(olas), address(this), address(this), address(this));
        Tokenomics master = new Tokenomics();
        tokenomics = Tokenomics(
            address(
                new TokenomicsProxy(
                    address(master),
                    abi.encodeCall(
                        master.initializeTokenomics,
                        (
                            address(olas),
                            address(treasury),
                            address(this),
                            address(this),
                            address(new MockVE()),
                            EPOCH,
                            registry,
                            registry,
                            registry,
                            address(0)
                        )
                    )
                )
            )
        );
        Dispenser dispenserMaster = new Dispenser(address(olas), address(tokenomics), bytes32(uint256(0xDEAD)));
        dispenser = Dispenser(
            address(
                new DispenserProxy(
                    address(dispenserMaster),
                    abi.encodeCall(dispenserMaster.initialize, (address(treasury), address(this), 100, 100))
                )
            )
        );
        vw = new MockVoteWeightingHistory(address(dispenser));
        dispenser.changeManagers(address(0), address(vw));
        treasury.changeManagers(address(tokenomics), address(0), address(dispenser));
        tokenomics.changeManagers(address(0), address(0), address(dispenser));
        olas.changeMinter(address(treasury));
        verifier = new StakingVerifier(address(olas), registry, address(0), 100 ether, 365 days, 100, 100 ether);
        factory = new StakingFactory(address(verifier));
        implementation = new LocalStakingFixture(olas, registry);
        processor = new EthereumDepositProcessor(address(olas), address(dispenser), address(factory), TIMELOCK);
        _route(block.chainid, address(processor));
        tokenomics.changeIncentiveFractions(0, 0, 0, 0, 0, 50);
        tokenomics.changeStakingParams(1 ether, 100);
        dispenser.setPauseState(Dispenser.Pause.Unpaused);
    }

    function _route(uint256 chain, address route) internal {
        uint256[] memory chains = new uint256[](1);
        chains[0] = chain;
        address[] memory routes = new address[](1);
        routes[0] = route;
        dispenser.setDepositProcessorChainIds(routes, chains);
    }

    function _bytes(address target) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(target)));
    }

    function _hash(address target) internal view returns (bytes32) {
        return keccak256(abi.encode(_bytes(target), block.chainid));
    }

    function _newInstance() internal returns (LocalStakingFixture) {
        return LocalStakingFixture(
            factory.createStakingInstance(
                address(implementation), abi.encodeCall(implementation.initialize, (100 ether))
            )
        );
    }

    function _nominate(address target, uint256 chain, uint256 weight) internal {
        vw.addNominee(target, chain);
        nominees.push(target);
        nomineeChains.push(chain);
        weights.push(weight);
    }

    function _settle(uint256 count) internal {
        for (uint256 n; n < count; ++n) {
            vm.warp(vm.getBlockTimestamp() + EPOCH + 10);
            vm.roll(vm.getBlockNumber() + 1);
            assertTrue(tokenomics.checkpoint(), "epoch must settle");
            uint256 time = tokenomics.getEpochEndTime(tokenomics.epochCounter() - 1);
            for (uint256 i; i < nominees.length; ++i) {
                vw.setWeightAt(nominees[i], nomineeChains[i], time, weights[i], 1e30);
            }
        }
    }

    function _ready(address target) internal {
        _nominate(target, block.chainid, 1e18);
        _settle(2);
    }

    function _pot() internal view returns (uint256 amount) {
        (amount,,,) = tokenomics.mapEpochStakingPoints(tokenomics.epochCounter());
    }

    function _quote(address target, uint256 epochs)
        internal
        view
        returns (uint256 stake, uint256 returned, uint256 end)
    {
        (stake, returned, end,,) = dispenser.calculateStakingIncentives(epochs, block.chainid, _bytes(target), 18);
    }

    function _claim(address target, uint256 epochs) internal {
        dispenser.claimStakingIncentives(epochs, block.chainid, _bytes(target), "");
    }

    function _batch(address a, address b, uint256 value) internal {
        uint256[] memory chains = new uint256[](1);
        chains[0] = block.chainid;
        bytes32[][] memory targets = new bytes32[][](1);
        targets[0] = new bytes32[](2);
        (targets[0][0], targets[0][1]) = uint160(a) < uint160(b) ? (_bytes(a), _bytes(b)) : (_bytes(b), _bytes(a));
        bytes[] memory payloads = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        dispenser.claimStakingIncentivesBatch{value: value}(100, chains, targets, payloads, values);
    }

    function _assertReturned(address target) internal {
        (uint256 stake, uint256 ordinary, uint256 end) = _quote(target, 100);
        assertGt(stake, 0);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        vm.expectEmit(true, false, false, true, address(dispenser));
        emit LocalAllocationReturned(_hash(target), dispenser.mapLastClaimedStakingEpochs(_hash(target)), end, stake);
        _claim(target, 100);
        assertEq(_pot() - beforePot, stake + ordinary);
        assertEq(olas.totalSupply(), supply);
        assertEq(olas.balanceOf(address(processor)), 0);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(target)), end);
    }

    function test_unknownAddressReturnsAllocation() public {
        _ready(UNKNOWN);
        _assertReturned(UNKNOWN);
    }

    function test_unregisteredContractReturnsAllocation() public {
        _ready(address(implementation));
        _assertReturned(address(implementation));
    }

    function test_removedInstanceReturnsAllocation() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        factory.removeInstance(address(target));
        _assertReturned(address(target));
        assertEq(target.deposited(), 0);
    }

    function test_enabledInstancePaysThroughRealVerifier() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        (uint256 stake, uint256 ordinary, uint256 end) = _quote(address(target), 100);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _claim(address(target), 100);
        assertEq(target.deposited(), stake);
        assertEq(olas.balanceOf(address(target)), stake);
        assertEq(olas.totalSupply() - supply, stake);
        assertEq(_pot() - beforePot, ordinary);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(address(target))), end);
    }

    function test_disabledInstanceRemainsRetryable() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        factory.setInstanceStatus(address(target), false);
        (uint256 stake,,) = _quote(address(target), 100);
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(address(target)));
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        vm.expectRevert(abi.encodeWithSelector(TargetEmissionsZero.selector, address(target)));
        _claim(address(target), 100);
        assertEq(_pot(), beforePot);
        assertEq(olas.totalSupply(), supply);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(address(target))), cursor);
        factory.setInstanceStatus(address(target), true);
        _claim(address(target), 100);
        assertEq(target.deposited(), stake);
    }

    function test_disableClaimReenableWithinTransactionDoesNotCancel() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        (, address instanceDeployer,) = factory.mapInstanceParams(address(target));
        assertEq(instanceDeployer, address(this));
        uint256 beforePot = _pot();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(address(target)));
        // This test contract is the instance deployer. These external calls all run within
        // this single invocation, with no broadcast or transaction boundary between toggles.
        factory.setInstanceStatus(address(target), false);
        (bool success,) = address(dispenser)
            .call(
                abi.encodeCall(
                    dispenser.claimStakingIncentives, (100, block.chainid, _bytes(address(target)), bytes(""))
                )
            );
        factory.setInstanceStatus(address(target), true);
        assertFalse(success);
        assertEq(_pot(), beforePot);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(address(target))), cursor);
        _claim(address(target), 100);
        assertGt(target.deposited(), 0);
    }

    function test_registeredZeroEmissionsIsNotRecycled() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        target.setEmissions(0);
        uint256 beforePot = _pot();
        vm.expectRevert(abi.encodeWithSelector(TargetEmissionsZero.selector, address(target)));
        _claim(address(target), 100);
        assertEq(_pot(), beforePot);
        target.setEmissions(100 ether);
        _claim(address(target), 100);
        assertGt(target.deposited(), 0);
    }

    function test_verifierReadFailureIsRetryable() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        target.setFailures(true, false);
        uint256 beforePot = _pot();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(address(target)));
        vm.expectRevert(bytes("emissions unavailable"));
        _claim(address(target), 100);
        assertEq(_pot(), beforePot);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(address(target))), cursor);
        target.setFailures(false, false);
        _claim(address(target), 100);
        assertGt(target.deposited(), 0);
    }

    function test_depositFailureRollsBackRefundAndCursor() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        target.setFailures(false, true);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(address(target)));
        vm.expectRevert(bytes("deposit unavailable"));
        _claim(address(target), 100);
        assertEq(_pot(), beforePot);
        assertEq(olas.totalSupply(), supply);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(address(target))), cursor);
    }

    function test_mixedBatchMatchesSeparateClaims() public {
        LocalStakingFixture target = _newInstance();
        _nominate(address(target), block.chainid, 5e17);
        _nominate(UNKNOWN, block.chainid, 5e17);
        _settle(2);
        uint256 snapshot = vm.snapshotState();
        uint256 beforePot = _pot();
        uint256 beforeSupply = olas.totalSupply();
        _claim(address(target), 100);
        _claim(UNKNOWN, 100);
        uint256 refund = _pot() - beforePot;
        uint256 minted = olas.totalSupply() - beforeSupply;
        uint256 paid = target.deposited();
        assertTrue(vm.revertToState(snapshot));
        _batch(address(target), UNKNOWN, 0);
        assertEq(_pot() - beforePot, refund);
        assertEq(olas.totalSupply() - beforeSupply, minted);
        assertEq(target.deposited(), paid);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), tokenomics.epochCounter());
    }

    function test_allUnknownBatchDoesNotCallProcessor() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), block.chainid, 5e17);
        _settle(2);
        (uint256 a, uint256 ar,) = _quote(UNKNOWN, 100);
        (uint256 b, uint256 br,) = _quote(address(implementation), 100);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        // The real processor would revert TargetEmissionsZero if it were called for either target.
        _batch(UNKNOWN, address(implementation), 0);
        assertEq(_pot() - beforePot, a + ar + b + br);
        assertEq(olas.totalSupply(), supply);
    }

    function test_disabledMemberRollsBackWholeBatch() public {
        LocalStakingFixture target = _newInstance();
        _nominate(address(target), block.chainid, 5e17);
        _nominate(UNKNOWN, block.chainid, 5e17);
        _settle(2);
        factory.setInstanceStatus(address(target), false);
        uint256 beforePot = _pot();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN));
        vm.expectRevert(abi.encodeWithSelector(TargetEmissionsZero.selector, address(target)));
        _batch(address(target), UNKNOWN, 0);
        assertEq(_pot(), beforePot);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), cursor);
    }

    function test_overlappingClaimsReturnEachEpochOnce() public {
        _ready(UNKNOWN);
        _settle(2);
        uint256 beforePot = _pot();
        uint256 refunded;
        for (uint256 i; i < 2; ++i) {
            (uint256 stake, uint256 ordinary,) = _quote(UNKNOWN, 2);
            refunded += stake + ordinary;
            _claim(UNKNOWN, 2);
        }
        assertEq(_pot() - beforePot, refunded);
        uint256 afterPot = _pot();
        (bool success,) = address(dispenser)
            .call(abi.encodeCall(dispenser.claimStakingIncentives, (100, block.chainid, _bytes(UNKNOWN), bytes(""))));
        assertFalse(success);
        assertEq(_pot(), afterPot);
    }

    function test_futureCreate2RegistrationDoesNotReviveReturnedEpochs() public {
        uint256 initialTime = vm.getBlockTimestamp();
        uint256 initialBlock = vm.getBlockNumber();
        vm.warp(initialTime + 2 * (EPOCH + 10));
        vm.roll(initialBlock + 2);
        vm.setBlockhash(initialBlock + 1, bytes32(uint256(123)));
        address predicted = factory.getProxyAddress(address(implementation));
        vm.warp(initialTime);
        vm.roll(initialBlock);
        _ready(predicted);
        _assertReturned(predicted);
        assertEq(factory.getProxyAddress(address(implementation)), predicted);
        LocalStakingFixture target = _newInstance();
        assertEq(address(target), predicted);
        uint256 beforePot = _pot();
        (bool success,) = address(dispenser)
            .call(abi.encodeCall(dispenser.claimStakingIncentives, (100, block.chainid, _bytes(predicted), bytes(""))));
        assertFalse(success);
        assertEq(_pot(), beforePot);
        assertEq(target.deposited(), 0);
        _settle(1);
        (uint256 stake,,) = _quote(predicted, 100);
        _claim(predicted, 100);
        assertEq(target.deposited(), stake);
        assertGt(stake, 0);
    }

    function test_removeAfterPaidEpochReturnsOnlyLaterAllocation() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        _claim(address(target), 100);
        uint256 paid = target.deposited();
        _settle(1);
        factory.removeInstance(address(target));
        _assertReturned(address(target));
        assertEq(target.deposited(), paid);
    }

    function test_withheldCreditIsUntouchedByReturnedAllocation() public {
        _ready(UNKNOWN);
        vm.prank(address(processor));
        dispenser.syncWithheldAmount(block.chainid, 3 ether, bytes32(uint256(1)));
        _assertReturned(UNKNOWN);
        assertEq(dispenser.mapChainIdWithheldAmounts(block.chainid), 3 ether);
    }

    function test_singleRejectsValueAndRollsBack() public {
        _ready(UNKNOWN);
        uint256 beforePot = _pot();
        vm.deal(address(this), 1);
        vm.expectRevert(abi.encodeWithSelector(WrongAmount.selector, 1, 0));
        dispenser.claimStakingIncentives{value: 1}(100, block.chainid, _bytes(UNKNOWN), "");
        assertEq(_pot(), beforePot);
    }

    function test_allReturnedBatchRejectsValueAndRollsBack() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), block.chainid, 5e17);
        _settle(2);
        uint256 beforePot = _pot();
        vm.deal(address(this), 1);
        vm.expectRevert(abi.encodeWithSelector(WrongAmount.selector, 1, 0));
        _batch(UNKNOWN, address(implementation), 1);
        assertEq(_pot(), beforePot);
    }

    function test_processorCapStillSendsExcessToTimelock() public {
        LocalStakingFixture target = _newInstance();
        _ready(address(target));
        target.setEmissions(0.25 ether);
        (uint256 stake, uint256 ordinary,) = _quote(address(target), 100);
        uint256 beforePot = _pot();
        _claim(address(target), 100);
        assertEq(target.deposited(), 0.25 ether);
        assertEq(olas.balanceOf(TIMELOCK), stake - 0.25 ether);
        assertEq(_pot() - beforePot, ordinary);
    }

    function test_remoteRouteNeedsNoFactoryGetter() public {
        MockDepositProcessor remote = new MockDepositProcessor();
        _route(REMOTE, address(remote));
        _nominate(UNKNOWN, REMOTE, 1e18);
        _settle(2);
        (uint256 stake,,,,) = dispenser.calculateStakingIncentives(100, REMOTE, _bytes(UNKNOWN), 18);
        dispenser.claimStakingIncentives(100, REMOTE, _bytes(UNKNOWN), "");
        assertEq(remote.lastStakingIncentive(), stake);
        assertGt(stake, 0);
    }

    function test_publicQuoteAndVotingWeightsStayUnchanged() public {
        _ready(UNKNOWN);
        (uint256 stake, uint256 ordinary, uint256 end) = _quote(UNKNOWN, 100);
        assertGt(stake, 0);
        assertGt(ordinary, 0);
        uint256 time = tokenomics.getEpochEndTime(end - 1);
        (uint256 weight, uint256 sum) = vw.nomineeRelativeWeight(_bytes(UNKNOWN), block.chainid, time);
        _claim(UNKNOWN, 100);
        (uint256 afterWeight, uint256 afterSum) = vw.nomineeRelativeWeight(_bytes(UNKNOWN), block.chainid, time);
        assertEq(afterWeight, weight);
        assertEq(afterSum, sum);
        assertTrue(vw.mapNominees(_hash(UNKNOWN)));
    }

    function test_batchConservesIndependentEpochAllocation() public {
        LocalStakingFixture target = _newInstance();
        _nominate(address(target), block.chainid, 5e17);
        _nominate(UNKNOWN, block.chainid, 5e17);
        _settle(2);
        (uint256 budget,,,) = tokenomics.mapEpochStakingPoints(tokenomics.epochCounter() - 1);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _batch(address(target), UNKNOWN, 0);
        uint256 minted = olas.totalSupply() - supply;
        uint256 returned = _pot() - beforePot;
        assertEq(minted + returned, 2 * (budget / 2));
        assertEq(target.deposited(), minted);
        assertEq(olas.balanceOf(address(target)), minted);
        assertEq(olas.balanceOf(address(dispenser)), 0);
        assertEq(olas.balanceOf(address(processor)), 0);
    }

    function test_allReturnedBatchPreservesWithheldCredit() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), block.chainid, 5e17);
        _settle(2);
        vm.prank(address(processor));
        dispenser.syncWithheldAmount(block.chainid, 3 ether, bytes32(uint256(1)));
        _batch(UNKNOWN, address(implementation), 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(block.chainid), 3 ether);
    }

    function test_zeroWeightAndPayableEpochsRefundWithoutOverlap() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), block.chainid, 5e17);
        _settle(3);
        uint256 zeroEpoch = tokenomics.epochCounter() - 1;
        uint256 time = tokenomics.getEpochEndTime(zeroEpoch);
        vw.setWeightAt(UNKNOWN, block.chainid, time, 0, 0);
        vw.setWeightAt(address(implementation), block.chainid, time, 0, 0);
        (uint256 priorBudget,,,) = tokenomics.mapEpochStakingPoints(zeroEpoch - 1);
        (uint256 zeroBudget,,,) = tokenomics.mapEpochStakingPoints(zeroEpoch);
        uint256 beforePot = _pot();
        _batch(UNKNOWN, address(implementation), 0);
        assertEq(_pot() - beforePot, 2 * (priorBudget / 2) + zeroBudget);
        assertTrue(dispenser.mapZeroWeightEpochRefunded(zeroEpoch));
    }

    function test_nomineeRemovalBoundsReturnedEpochs() public {
        _ready(UNKNOWN);
        uint256 removedEpoch = tokenomics.epochCounter();
        vm.prank(address(vw));
        dispenser.removeNominee(_hash(UNKNOWN));
        _settle(1);
        _assertReturned(UNKNOWN);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), removedEpoch);
        uint256 afterPot = _pot();
        (bool success,) = address(dispenser)
            .call(abi.encodeCall(dispenser.claimStakingIncentives, (100, block.chainid, _bytes(UNKNOWN), bytes(""))));
        assertFalse(success);
        assertEq(_pot(), afterPot);
    }

    function test_belowMinimumWeightDoesNotRequireRegistrationRead() public {
        _nominate(UNKNOWN, block.chainid, 99e14);
        _settle(2);
        _faultRoute("", 1);
        (uint256 stake, uint256 returned,) = _quote(UNKNOWN, 100);
        assertEq(stake, 0);
        assertGt(returned, 0);
        uint256 beforePot = _pot();
        _claim(UNKNOWN, 100);
        assertEq(_pot() - beforePot, returned);
    }

    function test_minimumWeightBoundaryUsesRegistrationRead() public {
        _nominate(UNKNOWN, block.chainid, 100e14);
        _settle(2);
        _faultRoute("", 1);
        (uint256 stake,,) = _quote(UNKNOWN, 100);
        assertGt(stake, 0);
        _assertReadReverts();
    }

    function test_registrationFailureRollsBackEarlierBatchEntries() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), block.chainid, 5e17);
        _settle(2);
        vm.mockCallRevert(
            address(factory),
            abi.encodeWithSignature("mapInstanceParams(address)", address(implementation)),
            bytes("read unavailable")
        );
        uint256 beforePot = _pot();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN));
        vm.expectRevert(bytes("read unavailable"));
        _batch(UNKNOWN, address(implementation), 0);
        assertEq(_pot(), beforePot);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), cursor);
    }

    function test_mixedLocalRemoteBatchKeepsRemoteWithheldAccounting() public {
        MockDepositProcessor remote = new MockDepositProcessor();
        _route(REMOTE, address(remote));
        _nominate(UNKNOWN, block.chainid, 5e17);
        _nominate(address(implementation), REMOTE, 5e17);
        _settle(2);
        (uint256 remoteStake, uint256 remoteReturn,,,) =
            dispenser.calculateStakingIncentives(100, REMOTE, _bytes(address(implementation)), 18);
        (uint256 localStake, uint256 localReturn,) = _quote(UNKNOWN, 100);
        uint256 credit = remoteStake / 2;
        vm.prank(address(remote));
        dispenser.syncWithheldAmount(REMOTE, credit, bytes32(uint256(1)));
        uint256[] memory chains = new uint256[](2);
        chains[0] = REMOTE;
        chains[1] = block.chainid;
        bytes32[][] memory targets = new bytes32[][](2);
        targets[0] = new bytes32[](1);
        targets[0][0] = _bytes(address(implementation));
        targets[1] = new bytes32[](1);
        targets[1][0] = _bytes(UNKNOWN);
        bytes[] memory payloads = new bytes[](2);
        uint256[] memory values = new uint256[](2);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        dispenser.claimStakingIncentivesBatch(100, chains, targets, payloads, values);
        assertEq(olas.totalSupply() - supply, remoteStake - credit);
        assertEq(_pot() - beforePot, localStake + localReturn + remoteReturn + credit);
        assertEq(dispenser.mapChainIdWithheldAmounts(REMOTE), 0);
        assertEq(remote.lastStakingIncentive(), remoteStake);
        assertEq(remote.lastTransferAmount(), remoteStake - credit);
        assertEq(olas.balanceOf(address(remote)), remoteStake - credit);
    }

    function test_recyclePreservesTwoTermRoundingResidual() public {
        _nominate(UNKNOWN, block.chainid, 5e17);
        _settle(2);
        uint256 epoch = tokenomics.epochCounter() - 1;
        (uint256 budget,,,) = tokenomics.mapEpochStakingPoints(epoch);
        // An even budget split into two odd amounts gives two half-weight floors,
        // one wei below floor(budget / 2). Keep that pre-existing residual explicit.
        assertEq(budget % 2, 0);
        uint256 votingPower = 3;
        vw.setWeightAt(UNKNOWN, block.chainid, tokenomics.getEpochEndTime(epoch), 5e17, votingPower);
        (uint256 stake, uint256 ordinary, uint256 end) = _quote(UNKNOWN, 100);
        assertEq(stake, 1);
        assertEq(ordinary, (budget - votingPower) / 2);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _claim(UNKNOWN, 100);
        uint256 returned = _pot() - beforePot;
        assertEq(returned, stake + ordinary);
        assertEq(returned + 1, budget / 2);
        assertEq(olas.totalSupply(), supply);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), end);
    }

    function testFuzz_recycleWithLowVotingPowerPreservesRounding(uint256 power, uint256 weight) public {
        weight = bound(weight, 100e14, 1e18);
        _nominate(UNKNOWN, block.chainid, weight);
        _settle(2);
        uint256 epoch = tokenomics.epochCounter() - 1;
        (uint256 budget,,,) = tokenomics.mapEpochStakingPoints(epoch);
        power = bound(power, 100, budget - 1);
        vw.setWeightAt(UNKNOWN, block.chainid, tokenomics.getEpochEndTime(epoch), weight, power);
        (uint256 stake, uint256 ordinary,) = _quote(UNKNOWN, 100);
        assertGt(stake, 0);
        uint256 unsplitShare = budget * weight / 1e18;
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _claim(UNKNOWN, 100);
        uint256 returned = _pot() - beforePot;
        assertEq(returned, stake + ordinary);
        assertLe(returned, unsplitShare);
        assertLe(unsplitShare - returned, 1, "two floored terms leave at most one wei of residual");
        assertEq(olas.totalSupply(), supply);
    }

    function test_mixedLocalBatchUsesCreditOnlyForEligiblePayout() public {
        LocalStakingFixture target = _newInstance();
        _nominate(address(target), block.chainid, 5e17);
        _nominate(UNKNOWN, block.chainid, 5e17);
        _settle(2);
        (uint256 stake, uint256 ordinary,) = _quote(address(target), 100);
        (uint256 recycledStake, uint256 recycledReturn,) = _quote(UNKNOWN, 100);
        uint256 credit = stake / 2;
        // Synthetic boundary state: seed both credit and previously issued token backing.
        // EthereumDepositProcessor itself has no outbound reserve-sync entry point.
        vm.prank(address(treasury));
        olas.mint(address(processor), credit);
        vm.prank(address(processor));
        dispenser.syncWithheldAmount(block.chainid, credit, bytes32(uint256(2)));
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _batch(address(target), UNKNOWN, 0);
        assertEq(olas.totalSupply() - supply, stake - credit);
        assertEq(_pot() - beforePot, ordinary + recycledStake + recycledReturn + credit);
        assertEq(target.deposited(), stake);
        assertEq(olas.balanceOf(address(target)), stake);
        assertEq(olas.balanceOf(address(processor)), 0);
        assertEq(dispenser.mapChainIdWithheldAmounts(block.chainid), 0);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), tokenomics.epochCounter());
        (uint256 budget,,,) = tokenomics.mapEpochStakingPoints(tokenomics.epochCounter() - 1);
        assertEq(olas.totalSupply() - supply + _pot() - beforePot, 2 * (budget / 2));
    }

    function _faultRoute(bytes memory data, uint256 mode) internal returns (RegistrationResponseFixture fault) {
        fault = new RegistrationResponseFixture();
        fault.configure(data, mode);
        _route(
            block.chainid,
            address(new EthereumDepositProcessor(address(olas), address(dispenser), address(fault), TIMELOCK))
        );
    }

    function _assertReadReverts() internal {
        uint256 beforePot = _pot();
        uint256 cursor = dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN));
        uint256 supply = olas.totalSupply();
        (bool success,) = address(dispenser).call{gas: 500000}(
            abi.encodeCall(dispenser.claimStakingIncentives, (100, block.chainid, _bytes(UNKNOWN), bytes("")))
        );
        assertFalse(success);
        assertEq(_pot(), beforePot);
        assertEq(olas.totalSupply(), supply);
        assertEq(dispenser.mapLastClaimedStakingEpochs(_hash(UNKNOWN)), cursor);
    }

    function test_registrationRevertIsNotAnEmptyRecord() public {
        _ready(UNKNOWN);
        _faultRoute("", 1);
        _assertReadReverts();
    }

    function test_outOfGasRegistrationReadIsNotAnEmptyRecord() public {
        _ready(UNKNOWN);
        _faultRoute("", 2);
        _assertReadReverts();
    }

    function test_missingProcessorGetterReverts() public {
        _ready(UNKNOWN);
        _route(block.chainid, address(new MockDepositProcessor()));
        _assertReadReverts();
    }

    function test_factoryWithoutCodeReverts() public {
        _ready(UNKNOWN);
        _route(
            block.chainid, address(new EthereumDepositProcessor(address(olas), address(dispenser), UNKNOWN, TIMELOCK))
        );
        _assertReadReverts();
    }

    function testFuzz_wrongResponseLengthReverts(uint8 length) public {
        vm.assume(length != 96);
        _ready(UNKNOWN);
        _faultRoute(new bytes(length), 0);
        _assertReadReverts();
    }

    function test_nonCanonicalDeployerReverts() public {
        _ready(UNKNOWN);
        _faultRoute(abi.encode(uint256(0), uint256(1) << 160, uint256(0)), 0);
        _assertReadReverts();
    }

    function test_nonCanonicalImplementationReverts() public {
        _ready(UNKNOWN);
        _faultRoute(abi.encode(uint256(1) << 160, uint256(0), uint256(0)), 0);
        _assertReadReverts();
    }

    function test_nonCanonicalEnabledFlagReverts() public {
        _ready(UNKNOWN);
        _faultRoute(abi.encode(uint256(0), uint256(0), uint256(2)), 0);
        _assertReadReverts();
    }

    function test_readFailureThenRepairRemainsClaimable() public {
        _ready(UNKNOWN);
        RegistrationResponseFixture fault = _faultRoute("", 1);
        _assertReadReverts();
        fault.configure(abi.encode(address(0), address(0), false), 0);
        _assertReturned(UNKNOWN);
    }

    // With total voting power above the budget, the calculation does not split its budget into two floors.
    // The low-voting-power tests separately cover that split and its possible one-wei residual.
    function testFuzz_returnConservationAcrossWeightsWithUnscaledBudget(uint256 weight) public {
        weight = bound(weight, 1, 1e18);
        _nominate(UNKNOWN, block.chainid, weight);
        _settle(2);
        (uint256 stake, uint256 ordinary, uint256 end) = _quote(UNKNOWN, 100);
        (uint256 budget,,,) = tokenomics.mapEpochStakingPoints(end - 1);
        uint256 beforePot = _pot();
        uint256 supply = olas.totalSupply();
        _claim(UNKNOWN, 100);
        assertEq(_pot() - beforePot, stake + ordinary);
        assertEq(stake + ordinary, budget * weight / 1e18);
        assertEq(olas.totalSupply(), supply);
    }
}
