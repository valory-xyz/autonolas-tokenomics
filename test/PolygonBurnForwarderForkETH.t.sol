// SPDX-License-Identifier: MIT
// Pinned to the compiler the deploy script derives the forwarder address with
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PolygonBurnForwarder} from "../contracts/utils/PolygonBurnForwarder.sol";

interface IERC20Fork {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IRootChainManager {
    function rootToChildToken(address rootToken) external view returns (address);
    function tokenToType(address rootToken) external view returns (bytes32);
    function typeToPredicate(bytes32 tokenType) external view returns (address);
}

/// @dev Ethereum-mainnet fork test of the L1 side of PolygonBurnForwarder (vulnerability-list #36).
///      - The Polygon PoS bridge maps L1 OLAS to the Polygon OLAS the forwarder burns, and pays exits from
///        ERC20PredicateProxy, read on live state.
///      - The forwarder is deployed through the live CREATE2 factory at its predicted address, or reused if it is
///        already deployed there (balances are then checked relative to what it already holds).
///      - OLAS released to it by an exit (the predicate's transfer to the burning address, modelled by
///        impersonating the predicate) reaches the live OLAS Burner via relay().
///      A real exit proof needs a burn that Polygon has checkpointed to Ethereum, which a fork cannot produce, so
///      the release is modelled here and the Polygon side is covered by PolygonBurnForwarderForkPolygon.
///      Self-skips unless block.chainid == 1, like the other *ForkETH tests.
///      Run: forge test -f $FORK_ETH_NODE_URL --mc PolygonBurnForwarderForkETH -vvv
contract PolygonBurnForwarderForkETH is Test {
    address internal constant L1_OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant POLYGON_OLAS = 0xFEF5d947472e72Efbb2E388c730B7428406F2F95;
    address internal constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    address internal constant ROOT_CHAIN_MANAGER = 0xA0c68C638235ee32657e8f720a23ceC1bFc77C77;
    address internal constant ERC20_PREDICATE = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
    uint256 internal constant POLYGON_CHAIN_ID = 137;
    uint256 internal constant L1_CHAIN_ID = 1;
    bytes32 internal constant SALT = keccak256("PolygonBurnForwarder");
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
        // Off a mainnet fork, skip the harness setup (each test then skips itself)
        if (block.chainid != L1_CHAIN_ID) {
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

    /// @dev The live bridge maps L1 OLAS to the Polygon OLAS the forwarder burns, and pays its exits from the
    ///      ERC20 predicate, which holds the escrowed OLAS.
    function test_bridgeMapping() public {
        if (block.chainid != L1_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        IRootChainManager rcm = IRootChainManager(ROOT_CHAIN_MANAGER);
        assertEq(rcm.rootToChildToken(L1_OLAS), POLYGON_OLAS, "L1 OLAS maps to Polygon OLAS");
        assertEq(rcm.typeToPredicate(rcm.tokenToType(L1_OLAS)), ERC20_PREDICATE, "exits paid by the ERC20 predicate");
        assertGe(IERC20Fork(L1_OLAS).balanceOf(ERC20_PREDICATE), AMOUNT, "predicate escrow covers the amount");
    }

    /// @dev OLAS released by an exit to the forwarder's address is burned by relay(), by anyone.
    function test_exitRelease_thenRelay_reachesBurner() public {
        if (block.chainid != L1_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        uint256 burnerBefore = IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER);
        uint256 held = IERC20Fork(L1_OLAS).balanceOf(address(forwarder));

        // The predicate releases the exit amount to the address that burned on Polygon: the forwarder
        vm.prank(ERC20_PREDICATE);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), AMOUNT);

        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();

        assertEq(amount, held + AMOUNT, "returned amount");
        assertEq(IERC20Fork(L1_OLAS).balanceOf(address(forwarder)), 0, "forwarder emptied");
        assertEq(IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER) - burnerBefore, held + AMOUNT, "burner received");
    }

    /// @dev Several exits can land before a relay; one relay burns them together.
    function test_severalExits_oneRelay() public {
        if (block.chainid != L1_CHAIN_ID) {
            vm.skip(true);
            return;
        }
        uint256 burnerBefore = IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER);
        uint256 held = IERC20Fork(L1_OLAS).balanceOf(address(forwarder));

        vm.startPrank(ERC20_PREDICATE);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), AMOUNT);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), 2 * AMOUNT);
        vm.stopPrank();

        forwarder.relay();
        assertEq(IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER) - burnerBefore, held + 3 * AMOUNT, "both exits burned");

        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();
    }
}
