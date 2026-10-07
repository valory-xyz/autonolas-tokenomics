// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {PolygonBurnForwarder} from "../contracts/utils/PolygonBurnForwarder.sol";
import {Bridge2BurnerPolygon} from "../contracts/utils/Bridge2BurnerPolygon.sol";

interface IERC20PolygonFork {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev Polygon-mainnet fork test of the Polygon side of PolygonBurnForwarder (vulnerability-list #36).
///      - The forwarder is deployed through the live CREATE2 factory at its predicted address.
///      - relay() burns its real Polygon PoS OLAS balance through the live child token's withdraw(), emitting the
///        Transfer(forwarder, 0, amount) log that the Ethereum-side exit proves: the predicate releases the L1 OLAS
///        to the log's `from`, which is the forwarder's address there too.
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

    function setUp() public {
        assertEq(block.chainid, POLYGON_CHAIN_ID, "run against a Polygon mainnet fork");

        bytes memory initCode = abi.encodePacked(type(PolygonBurnForwarder).creationCode,
            abi.encode(POLYGON_OLAS, L1_OLAS, OLAS_BURNER, POLYGON_CHAIN_ID, L1_CHAIN_ID));
        address predicted = vm.computeCreate2Address(SALT, keccak256(initCode), CREATE2_FACTORY);

        (bool success, bytes memory ret) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
        assertTrue(success, "factory deployment");
        forwarder = PolygonBurnForwarder(address(bytes20(ret)));
        assertEq(address(forwarder), predicted, "deployed at the predicted address");
    }

    /// @dev relay() burns the whole balance through the live PoS child token, and the burn log is the one the
    ///      Ethereum-side exit proves: Transfer from the forwarder to the zero address, for the full amount.
    function test_relay_burnsViaLiveWithdraw_emittingTheExitLog() public {
        deal(POLYGON_OLAS, address(forwarder), AMOUNT, true);
        uint256 supplyBefore = IERC20PolygonFork(POLYGON_OLAS).totalSupply();

        vm.recordLogs();
        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(amount, AMOUNT, "returned amount");
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), 0, "balance burned");
        assertEq(supplyBefore - IERC20PolygonFork(POLYGON_OLAS).totalSupply(), AMOUNT, "supply reduced by the amount");

        // Exactly one burn log from the child token, with the forwarder as `from`
        uint256 burnLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == POLYGON_OLAS && log.topics[0] == TRANSFER_TOPIC && log.topics[2] == bytes32(0)) {
                ++burnLogs;
                assertEq(address(uint160(uint256(log.topics[1]))), address(forwarder), "burn from the forwarder");
                assertEq(abi.decode(log.data, (uint256)), AMOUNT, "burn amount");
            }
        }
        assertEq(burnLogs, 1, "one burn log for the exit proof");
    }

    /// @dev Integration on live Polygon OLAS: Bridge2BurnerPolygon deployed with the forwarder as its recipient (as
    ///      deploy_00c_bridge2burner_polygon.sh now does) delivers OLAS to the forwarder, and relay() burns it with the
    ///      exit log.
    function test_bridge2BurnerPolygon_deliversToForwarder_thenBurnedWithExitLog() public {
        Bridge2BurnerPolygon bridge2Burner = new Bridge2BurnerPolygon(POLYGON_OLAS, address(forwarder));
        deal(POLYGON_OLAS, address(bridge2Burner), AMOUNT, true);

        vm.prank(address(0xCA11));
        bridge2Burner.relayToL1Burner();
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(bridge2Burner)), 0, "bridge2Burner emptied");
        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), AMOUNT, "OLAS reached the forwarder");

        vm.recordLogs();
        forwarder.relay();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(IERC20PolygonFork(POLYGON_OLAS).balanceOf(address(forwarder)), 0, "forwarder burned it");
        uint256 burnLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == POLYGON_OLAS && log.topics[0] == TRANSFER_TOPIC && log.topics[2] == bytes32(0)) {
                ++burnLogs;
                assertEq(address(uint160(uint256(log.topics[1]))), address(forwarder), "burn from the forwarder");
            }
        }
        assertEq(burnLogs, 1, "one burn log for the exit proof");
    }

    /// @dev On Polygon nothing goes to L1 directly, and nothing to relay reverts.
    function test_relay_zeroBalance_reverts() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();
    }
}
