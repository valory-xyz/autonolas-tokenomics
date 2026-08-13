// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Dispenser, AlreadyInitialized, OwnerOnly, ZeroAddress, ZeroValue} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";

/// @dev Proxy-lifecycle tests for the Dispenser behind DispenserProxy: initialization via the proxy
///      constructor delegatecall, re-initialization protection, implementation upgrade via
///      changeImplementation (owner-gated, state-preserving), and proxy constructor guards.
///      Run: forge test --mc DispenserProxyTest -vvv
contract DispenserProxyTest is Test {
    event ImplementationUpdated(address indexed implementation);

    bytes32 public constant PROXY_DISPENSER = 0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83;

    address internal constant OLAS = address(0x01A5);
    address internal constant TOKENOMICS = address(0x70e0);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant VOTE_WEIGHTING = address(0x0e7e);
    bytes32 internal constant RETAINER = bytes32(uint256(uint160(0xe7a1)));

    Dispenser internal dispenserMaster;
    Dispenser internal dispenser;

    function setUp() public {
        dispenserMaster = new Dispenser(OLAS, TOKENOMICS, RETAINER);
        bytes memory initData = abi.encodeWithSelector(Dispenser.initialize.selector,
            TREASURY, VOTE_WEIGHTING, 10, 20);
        DispenserProxy proxy = new DispenserProxy(address(dispenserMaster), initData);
        dispenser = Dispenser(address(proxy));
    }

    // -----------------------------------------------------------------------
    // Proxy constructor guards
    // -----------------------------------------------------------------------

    function test_proxyConstructor_zeroImplementation_reverts() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new DispenserProxy(address(0), abi.encode(uint256(1)));
    }

    function test_proxyConstructor_zeroData_reverts() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        new DispenserProxy(address(dispenserMaster), "");
    }

    function test_proxyConstructor_failedInit_reverts() public {
        // Zero treasury address makes initialize revert -> proxy constructor reverts InitializationFailed
        bytes memory badInit = abi.encodeWithSelector(Dispenser.initialize.selector,
            address(0), VOTE_WEIGHTING, 10, 20);
        vm.expectRevert(abi.encodeWithSignature("InitializationFailed()"));
        new DispenserProxy(address(dispenserMaster), badInit);
    }

    // -----------------------------------------------------------------------
    // Initialization through the proxy
    // -----------------------------------------------------------------------

    function test_initialize_setsStateAndImmutables() public {
        // Proxy storage set by initialize; owner is the proxy deployer (this contract)
        assertEq(dispenser.owner(), address(this), "owner");
        assertEq(dispenser.treasury(), TREASURY, "treasury");
        assertEq(dispenser.voteWeighting(), VOTE_WEIGHTING, "voteWeighting");
        assertEq(dispenser.maxNumClaimingEpochs(), 10, "maxNumClaimingEpochs");
        assertEq(dispenser.maxNumStakingTargets(), 20, "maxNumStakingTargets");
        // Staking incentives are paused at deployment
        assertEq(uint256(dispenser.paused()), uint256(Dispenser.Pause.StakingIncentivesPaused), "paused");

        // Implementation immutables read through the proxy delegatecall
        assertEq(dispenser.olas(), OLAS, "olas");
        assertEq(dispenser.tokenomics(), TOKENOMICS, "tokenomics");
        assertEq(dispenser.retainer(), RETAINER, "retainer");

        // The implementation address sits in the dedicated proxy slot
        bytes32 rawImplementation = vm.load(address(dispenser), PROXY_DISPENSER);
        assertEq(address(uint160(uint256(rawImplementation))), address(dispenserMaster), "implementation slot");
    }

    function test_initialize_zeroVoteWeighting_allowed() public {
        // A fresh proxy is deployed with a zero Vote Weighting on purpose: VoteWeighting binds this proxy's
        // address as an immutable, so it does not exist yet at init. It is wired later via changeManagers.
        Dispenser master = new Dispenser(OLAS, TOKENOMICS, RETAINER);
        bytes memory initData = abi.encodeWithSelector(Dispenser.initialize.selector,
            TREASURY, address(0), 10, 20);
        Dispenser proxied = Dispenser(address(new DispenserProxy(address(master), initData)));

        assertEq(proxied.voteWeighting(), address(0), "voteWeighting zero at init");
        assertEq(proxied.treasury(), TREASURY, "treasury set");
        // Still paused, so no claim path can run against the zero Vote Weighting
        assertEq(uint256(proxied.paused()), uint256(Dispenser.Pause.StakingIncentivesPaused), "paused");

        // changeManagers wires the real Vote Weighting while paused
        proxied.changeManagers(address(0), VOTE_WEIGHTING);
        assertEq(proxied.voteWeighting(), VOTE_WEIGHTING, "voteWeighting wired");
    }

    /// @dev Merged-state interaction of the zero-VW initialize (allow zero) and the go-live guard: a fresh proxy
    ///      with voteWeighting == 0 cannot be brought live until Vote Weighting is wired. This is barrier 1 (the
    ///      setPauseState guard); barrier 2 is _requireClaimableNominee returning a clean ZeroValue on a claim
    ///      (covered in DispenserFixes.test_claim_neverAddedNominee_revertsZeroValueBeforeCheckpoint).
    function test_setPauseState_requiresVoteWeighting_beforeGoLive() public {
        Dispenser master = new Dispenser(OLAS, TOKENOMICS, RETAINER);
        bytes memory initData = abi.encodeWithSelector(Dispenser.initialize.selector,
            TREASURY, address(0), 10, 20);
        Dispenser proxied = Dispenser(address(new DispenserProxy(address(master), initData)));

        // Cannot let staking incentives go live while voteWeighting is unset (both staking-active states)
        vm.expectRevert(ZeroAddress.selector);
        proxied.setPauseState(Dispenser.Pause.Unpaused);
        vm.expectRevert(ZeroAddress.selector);
        proxied.setPauseState(Dispenser.Pause.DevIncentivesPaused);

        // Re-pausing transitions stay allowed with a zero Vote Weighting
        proxied.setPauseState(Dispenser.Pause.AllPaused);
        proxied.setPauseState(Dispenser.Pause.StakingIncentivesPaused);

        // Once Vote Weighting is wired (while paused), going live is permitted
        proxied.changeManagers(address(0), VOTE_WEIGHTING);
        proxied.setPauseState(Dispenser.Pause.Unpaused);
        assertEq(uint256(proxied.paused()), uint256(Dispenser.Pause.Unpaused), "live after wiring");
    }

    function test_initialize_proxyReinit_reverts() public {
        vm.expectRevert(AlreadyInitialized.selector);
        dispenser.initialize(TREASURY, VOTE_WEIGHTING, 10, 20);
    }

    function test_initialize_implDirectReinit_reverts() public {
        // Direct initialization of the implementation's own storage is possible once (harmless), not twice
        dispenserMaster.initialize(TREASURY, VOTE_WEIGHTING, 10, 20);
        vm.expectRevert(AlreadyInitialized.selector);
        dispenserMaster.initialize(TREASURY, VOTE_WEIGHTING, 10, 20);
    }

    // -----------------------------------------------------------------------
    // changeImplementation
    // -----------------------------------------------------------------------

    function test_changeImplementation_notOwner_reverts() public {
        address nonOwner = address(0xBAD);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerOnly.selector, nonOwner, address(this)));
        dispenser.changeImplementation(address(dispenserMaster));
    }

    function test_changeImplementation_zeroAddress_reverts() public {
        vm.expectRevert(ZeroAddress.selector);
        dispenser.changeImplementation(address(0));
    }

    function test_changeImplementation_swapsLogicAndPreservesState() public {
        // Mutate proxy storage after init so preservation is observable
        address newTreasury = address(0x7EA52);
        dispenser.changeManagers(newTreasury, address(0));

        // New implementation build
        Dispenser newMaster = new Dispenser(OLAS, TOKENOMICS, RETAINER);

        vm.expectEmit(true, false, false, false, address(dispenser));
        emit ImplementationUpdated(address(newMaster));
        dispenser.changeImplementation(address(newMaster));

        // Slot updated
        bytes32 rawImplementation = vm.load(address(dispenser), PROXY_DISPENSER);
        assertEq(address(uint160(uint256(rawImplementation))), address(newMaster), "implementation slot");

        // Proxy storage preserved across the upgrade
        assertEq(dispenser.owner(), address(this), "owner preserved");
        assertEq(dispenser.treasury(), newTreasury, "treasury preserved");
        assertEq(dispenser.voteWeighting(), VOTE_WEIGHTING, "voteWeighting preserved");
        assertEq(dispenser.maxNumClaimingEpochs(), 10, "maxNumClaimingEpochs preserved");
        assertEq(dispenser.maxNumStakingTargets(), 20, "maxNumStakingTargets preserved");
        assertEq(uint256(dispenser.paused()), uint256(Dispenser.Pause.StakingIncentivesPaused), "paused preserved");

        // Immutable reads now come from the new implementation bytecode
        assertEq(dispenser.olas(), OLAS, "olas");
        assertEq(dispenser.tokenomics(), TOKENOMICS, "tokenomics");
        assertEq(dispenser.retainer(), RETAINER, "retainer");
    }
}
