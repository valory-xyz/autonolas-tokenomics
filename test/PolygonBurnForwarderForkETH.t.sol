// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
///      - The forwarder is deployed through the live CREATE2 factory at its predicted address.
///      - OLAS released to it by an exit (the predicate's transfer to the burning address, modelled by
///        impersonating the predicate) reaches the live OLAS Burner via relay().
///      A real exit proof needs a burn that Polygon has checkpointed to Ethereum, which a fork cannot produce, so
///      the release is modelled here and the Polygon side is covered by PolygonBurnForwarderForkPolygon.
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

    function setUp() public {
        bytes memory initCode = abi.encodePacked(type(PolygonBurnForwarder).creationCode,
            abi.encode(POLYGON_OLAS, L1_OLAS, OLAS_BURNER, POLYGON_CHAIN_ID, L1_CHAIN_ID));
        address predicted = vm.computeCreate2Address(SALT, keccak256(initCode), CREATE2_FACTORY);

        (bool success, bytes memory ret) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
        assertTrue(success, "factory deployment");
        forwarder = PolygonBurnForwarder(address(bytes20(ret)));
        assertEq(address(forwarder), predicted, "deployed at the predicted address");
    }

    /// @dev The live bridge maps L1 OLAS to the Polygon OLAS the forwarder burns, and pays its exits from the
    ///      ERC20 predicate, which holds the escrowed OLAS.
    function test_bridgeMapping() public view {
        IRootChainManager rcm = IRootChainManager(ROOT_CHAIN_MANAGER);
        assertEq(rcm.rootToChildToken(L1_OLAS), POLYGON_OLAS, "L1 OLAS maps to Polygon OLAS");
        assertEq(rcm.typeToPredicate(rcm.tokenToType(L1_OLAS)), ERC20_PREDICATE, "exits paid by the ERC20 predicate");
        assertGe(IERC20Fork(L1_OLAS).balanceOf(ERC20_PREDICATE), AMOUNT, "predicate escrow covers the amount");
    }

    /// @dev OLAS released by an exit to the forwarder's address is burned by relay(), by anyone.
    function test_exitRelease_thenRelay_reachesBurner() public {
        uint256 burnerBefore = IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER);

        // The predicate releases the exit amount to the address that burned on Polygon: the forwarder
        vm.prank(ERC20_PREDICATE);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), AMOUNT);

        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();

        assertEq(amount, AMOUNT, "returned amount");
        assertEq(IERC20Fork(L1_OLAS).balanceOf(address(forwarder)), 0, "forwarder emptied");
        assertEq(IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER) - burnerBefore, AMOUNT, "burner received");
    }

    /// @dev Several exits can land before a relay; one relay burns them together.
    function test_severalExits_oneRelay() public {
        uint256 burnerBefore = IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER);

        vm.startPrank(ERC20_PREDICATE);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), AMOUNT);
        IERC20Fork(L1_OLAS).transfer(address(forwarder), 2 * AMOUNT);
        vm.stopPrank();

        forwarder.relay();
        assertEq(IERC20Fork(L1_OLAS).balanceOf(OLAS_BURNER) - burnerBefore, 3 * AMOUNT, "both exits burned");

        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();
    }
}
