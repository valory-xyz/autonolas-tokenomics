// SPDX-License-Identifier: MIT
// Pinned to the compiler the deploy script derives the forwarder address with
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {PolygonBurnForwarder} from "../contracts/utils/PolygonBurnForwarder.sol";
import {Bridge2BurnerPolygon} from "../contracts/utils/Bridge2BurnerPolygon.sol";

interface IERC20PolygonFork {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev Polygon-mainnet fork test of the Polygon side of PolygonBurnForwarder (vulnerability-list #36).
///      - The forwarder is deployed through the live CREATE2 factory at its predicted address, or reused if it is
///        already deployed there (balances are then checked relative to what it already holds).
///      - relay() burns its real Polygon PoS OLAS balance through the live child token's withdraw(), emitting the
///        Transfer(forwarder, 0, amount) log that the Ethereum-side exit proves: the predicate releases the L1 OLAS
///        to the log's `from`, which is the forwarder's address there too.
///      Self-skips unless block.chainid == 137.
///      Run: forge test -f $FORK_POLYGON_NODE_URL --mc PolygonBurnForwarderForkPolygon -vvv
contract PolygonBurnForwarderForkPolygon is Test {
    address internal constant L1_OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant POLYGON_OLAS = 0xFEF5d947472e72Efbb2E388c730B7428406F2F95;
    address internal constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    uint256 internal constant POLYGON_CHAIN_ID = 137;
    uint256 internal constant L1_CHAIN_ID = 1;
    bytes32 internal constant SALT = keccak256("PolygonBurnForwarder");
    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    uint256 internal constant AMOUNT = 1_000 ether;

    PolygonBurnForwarder internal forwarder;

    /// @dev The constructor arguments, read from the same utils globals as deploy_00e_polygon_burn_forwarder.sh, so
    ///      that this test derives the same init code (this file pins solc 0.8.30, as the deploy script does).
    function _initCodeFromGlobals() internal view returns (bytes memory initCode, string memory polygonGlobals,
        string memory ethGlobals)
    {
        polygonGlobals = vm.readFile("scripts/deployment/utils/globals_polygon_mainnet.json");
        ethGlobals = vm.readFile("scripts/deployment/utils/globals_eth_mainnet.json");
        address polygonOlas = vm.parseJsonAddress(polygonGlobals, ".olasAddress");
        address l1Olas = vm.parseJsonAddress(ethGlobals, ".olasAddress");
        address olasBurner = vm.parseJsonAddress(ethGlobals, ".burnerAddress");
        uint256 polygonChainId = vm.parseUint(vm.parseJsonString(polygonGlobals, ".chainId"));
        uint256 l1ChainId = vm.parseUint(vm.parseJsonString(ethGlobals, ".chainId"));
        // The globals give the addresses this test checks against
        assertEq(polygonOlas, POLYGON_OLAS, "globals polygonOlas");
        assertEq(l1Olas, L1_OLAS, "globals l1Olas");
        assertEq(olasBurner, OLAS_BURNER, "globals olasBurner");
        assertEq(polygonChainId, POLYGON_CHAIN_ID, "globals polygonChainId");
        assertEq(l1ChainId, L1_CHAIN_ID, "globals l1ChainId");
        initCode = abi.encodePacked(type(PolygonBurnForwarder).creationCode,
            abi.encode(polygonOlas, l1Olas, olasBurner, polygonChainId, l1ChainId));
    }

    function setUp() public {
        // Off a Polygon fork, skip the harness setup (each test then skips itself)
        if (block.chainid != POLYGON_CHAIN_ID) {
            return;
        }

        (bytes memory initCode, string memory polygonGlobals, string memory ethGlobals) = _initCodeFromGlobals();
        address predicted = vm.computeCreate2Address(SALT, keccak256(initCode), CREATE2_FACTORY);

        // Once the deploy script has recorded the forwarder, this build must derive that same address; otherwise the
        // compiler or the arguments differ, and the test would deploy elsewhere and miss the existing deployment
        string memory recordedIn = block.chainid == POLYGON_CHAIN_ID ? polygonGlobals : ethGlobals;
        if (vm.keyExistsJson(recordedIn, ".polygonBurnForwarderAddress")) {
            assertEq(predicted, vm.parseJsonAddress(recordedIn, ".polygonBurnForwarderAddress"),
                "derived address equals the recorded deployment");
        }

        // Once the forwarder is live, the fork already holds it: reuse it, since a second CREATE2 deployment with the
        // same salt and init code fails. Otherwise deploy it through the live factory.
        if (predicted.code.length == 0) {
            (bool success, bytes memory ret) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
            assertTrue(success, "factory deployment");
            assertEq(address(bytes20(ret)), predicted, "deployed at the predicted address");
        }
        forwarder = PolygonBurnForwarder(predicted);
        assertEq(forwarder.polygonOlas(), POLYGON_OLAS, "polygonOlas");
        assertEq(forwarder.l1Olas(), L1_OLAS, "l1Olas");
        assertEq(forwarder.olasBurner(), OLAS_BURNER, "olasBurner");
        assertEq(forwarder.polygonChainId(), POLYGON_CHAIN_ID, "polygonChainId");
        assertEq(forwarder.l1ChainId(), L1_CHAIN_ID, "l1ChainId");
    }

    /// @dev relay() burns the whole balance through the live PoS child token, and the burn log is the one the
    ///      Ethereum-side exit proves: Transfer from the forwarder to the zero address, for the full amount.
    function test_relay_burnsViaLiveWithdraw_emittingTheExitLog() public {
        if (block.chainid != POLYGON_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        // relay() burns the whole balance: what a live forwarder already holds plus what is supplied here
        uint256 held = IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder));
        deal(POLYGON_OLAS, address(forwarder), held + AMOUNT, true);
        uint256 supplyBefore = IERC20PolygonFork(POLYGON_OLAS).totalSupply();

        vm.recordLogs();
        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(amount, held + AMOUNT, "returned amount");
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), 0, "balance burned");
        assertEq(supplyBefore - IERC20PolygonFork(POLYGON_OLAS).totalSupply(), held + AMOUNT, "supply reduced by the amount");

        // Exactly one burn log from the child token, with the forwarder as `from`
        uint256 burnLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == POLYGON_OLAS && log.topics[0] == TRANSFER_TOPIC && log.topics[2] == bytes32(0)) {
                ++burnLogs;
                assertEq(address(uint160(uint256(log.topics[1]))), address(forwarder), "burn from the forwarder");
                assertEq(abi.decode(log.data, (uint256)), held + AMOUNT, "burn amount");
            }
        }
        assertEq(burnLogs, 1, "one burn log for the exit proof");
    }

    /// @dev Integration on live Polygon OLAS: Bridge2BurnerPolygon deployed with the forwarder as its recipient (as
    ///      deploy_00c_bridge2burner_polygon.sh now does) delivers OLAS to the forwarder, and relay() burns it with the
    ///      exit log.
    function test_bridge2BurnerPolygon_deliversToForwarder_thenBurnedWithExitLog() public {
        if (block.chainid != POLYGON_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        Bridge2BurnerPolygon bridge2Burner = new Bridge2BurnerPolygon(POLYGON_OLAS, address(forwarder));
        deal(POLYGON_OLAS, address(bridge2Burner), AMOUNT, true);
        uint256 held = IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder));

        vm.prank(address(0xCA11));
        bridge2Burner.relayToL1Burner();
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(bridge2Burner)), 0, "bridge2Burner emptied");
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), held + AMOUNT, "OLAS reached the forwarder");

        vm.recordLogs();
        uint256 relayed = forwarder.relay();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(relayed, held + AMOUNT, "relay burns what it held plus the delivered OLAS");
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), 0, "forwarder burned it");
        uint256 burnLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == POLYGON_OLAS && log.topics[0] == TRANSFER_TOPIC && log.topics[2] == bytes32(0)) {
                ++burnLogs;
                assertEq(address(uint160(uint256(log.topics[1]))), address(forwarder), "burn from the forwarder");
                assertEq(abi.decode(log.data, (uint256)), held + AMOUNT, "burn amount");
            }
        }
        assertEq(burnLogs, 1, "one burn log for the exit proof");
    }

    /// @dev On Polygon nothing goes to L1 directly, and nothing to relay reverts.
    function test_relay_zeroBalance_reverts() public {
        if (block.chainid != POLYGON_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        // A live forwarder may hold OLAS awaiting a relay: empty it first
        if (IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)) > 0) {
            forwarder.relay();
        }
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();
    }
}
