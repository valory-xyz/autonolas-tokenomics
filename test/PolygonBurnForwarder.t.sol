// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PolygonBurnForwarder} from "../contracts/utils/PolygonBurnForwarder.sol";
import {Bridge2BurnerPolygon} from "../contracts/utils/Bridge2BurnerPolygon.sol";

/// @dev Minimal token: a Polygon PoS child token (withdraw burns the caller's balance, emitting the Transfer to
///      zero that the PoS exit proves) and an L1 ERC20, in one mock.
contract MockToken {
    event Transfer(address indexed from, address indexed to, uint256 value);

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }
}

/// @dev Unit tests for PolygonBurnForwarder (vulnerability-list #36): one CREATE2 address on both chains, relay()
///      burns on Polygon, forwards to the burner on L1, and reverts on any other chain.
///      Run: forge test --mc PolygonBurnForwarderTest -vvv
contract PolygonBurnForwarderTest is Test {
    // Runtime code of the deterministic CREATE2 deployer at forge-std's CREATE2_FACTORY (0x4e59...956C), identical
    // on Ethereum and Polygon
    bytes internal constant CREATE2_FACTORY_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
    uint256 internal constant POLYGON_CHAIN_ID = 137;
    uint256 internal constant L1_CHAIN_ID = 1;
    address internal constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    bytes32 internal constant SALT = keccak256("PolygonBurnForwarder");
    uint256 internal constant AMOUNT = 1_000 ether;

    event Withdrawn(address indexed sender, uint256 amount);
    event Burned(address indexed sender, address indexed olasBurner, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    MockToken internal polygonOlas;
    MockToken internal l1Olas;

    function setUp() public {
        vm.etch(CREATE2_FACTORY, CREATE2_FACTORY_CODE);
        polygonOlas = new MockToken();
        l1Olas = new MockToken();
    }

    function _initCode(address _polygonOlas, address _l1Olas, address _olasBurner) internal pure returns (bytes memory) {
        return abi.encodePacked(type(PolygonBurnForwarder).creationCode,
            abi.encode(_polygonOlas, _l1Olas, _olasBurner, POLYGON_CHAIN_ID, L1_CHAIN_ID));
    }

    /// @dev Deploys through the CREATE2 factory, as on mainnet, and returns the deployed address.
    function _deployViaFactory(bytes memory initCode) internal returns (address forwarder) {
        (bool success, bytes memory ret) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initCode));
        assertTrue(success, "factory deployment");
        forwarder = address(bytes20(ret));
    }

    function _deploy() internal returns (PolygonBurnForwarder) {
        return PolygonBurnForwarder(_deployViaFactory(_initCode(address(polygonOlas), address(l1Olas), OLAS_BURNER)));
    }

    /// @dev Same salt and constructor arguments give the same address whatever the chain, and that address is the
    ///      one predicted from the init code alone.
    function test_sameAddressOnBothChains() public {
        bytes memory initCode = _initCode(address(polygonOlas), address(l1Olas), OLAS_BURNER);
        address predicted = vm.computeCreate2Address(SALT, keccak256(initCode), CREATE2_FACTORY);

        uint256 snapshot = vm.snapshotState();
        vm.chainId(POLYGON_CHAIN_ID);
        address onPolygon = _deployViaFactory(initCode);
        vm.revertToState(snapshot);
        vm.chainId(L1_CHAIN_ID);
        address onL1 = _deployViaFactory(initCode);

        assertEq(onPolygon, predicted, "Polygon address predicted");
        assertEq(onL1, predicted, "L1 address predicted");
        assertGt(onL1.code.length, 0, "deployed");
    }

    /// @dev Any difference in the constructor arguments moves the address: both chains must use identical ones.
    function test_differentArgumentsGiveDifferentAddress() public view {
        address a = vm.computeCreate2Address(SALT,
            keccak256(_initCode(address(polygonOlas), address(l1Olas), OLAS_BURNER)), CREATE2_FACTORY);
        address b = vm.computeCreate2Address(SALT,
            keccak256(_initCode(address(polygonOlas), address(l1Olas), address(0xB0B))), CREATE2_FACTORY);
        assertTrue(a != b, "arguments are part of the address");
    }

    /// @dev On Polygon, relay() burns the whole balance via withdraw(): the Transfer to zero is what the exit proves.
    function test_relay_polygon_burnsViaWithdraw() public {
        vm.chainId(POLYGON_CHAIN_ID);
        PolygonBurnForwarder forwarder = _deploy();
        polygonOlas.mint(address(forwarder), AMOUNT);

        vm.expectEmit(true, true, false, true, address(polygonOlas));
        emit Transfer(address(forwarder), address(0), AMOUNT);
        vm.expectEmit(true, false, false, true, address(forwarder));
        emit Withdrawn(address(0xCA11), AMOUNT);
        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();

        assertEq(amount, AMOUNT, "returned amount");
        assertEq(polygonOlas.balanceOf(address(forwarder)), 0, "balance burned");
        assertEq(polygonOlas.totalSupply(), 0, "supply reduced");
        assertEq(l1Olas.balanceOf(OLAS_BURNER), 0, "nothing sent on L1 from Polygon");
    }

    /// @dev On L1, relay() transfers the OLAS released by completed exits to the burner.
    function test_relay_l1_forwardsToBurner() public {
        vm.chainId(L1_CHAIN_ID);
        PolygonBurnForwarder forwarder = _deploy();
        // Released by the PoS exit to this address
        l1Olas.mint(address(forwarder), AMOUNT);

        vm.expectEmit(true, true, false, true, address(forwarder));
        emit Burned(address(0xCA11), OLAS_BURNER, AMOUNT);
        vm.prank(address(0xCA11));
        uint256 amount = forwarder.relay();

        assertEq(amount, AMOUNT, "returned amount");
        assertEq(l1Olas.balanceOf(address(forwarder)), 0, "forwarder emptied");
        assertEq(l1Olas.balanceOf(OLAS_BURNER), AMOUNT, "burner received");
    }

    /// @dev Any other chain reverts, even with a balance of either token.
    function test_relay_otherChain_reverts() public {
        vm.chainId(10);
        PolygonBurnForwarder forwarder = _deploy();
        polygonOlas.mint(address(forwarder), AMOUNT);
        l1Olas.mint(address(forwarder), AMOUNT);

        vm.expectRevert(abi.encodeWithSignature("WrongChainId(uint256)", 10));
        forwarder.relay();
    }

    /// @dev Nothing to relay reverts on both chains.
    function test_relay_zeroBalance_reverts() public {
        PolygonBurnForwarder forwarder = _deploy();

        vm.chainId(POLYGON_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();

        vm.chainId(L1_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        forwarder.relay();
    }

    /// @dev On each chain only that chain's token moves: a stray balance of the other token stays put.
    function test_relay_onlyMovesTheChainsToken() public {
        PolygonBurnForwarder forwarder = _deploy();
        polygonOlas.mint(address(forwarder), AMOUNT);
        l1Olas.mint(address(forwarder), AMOUNT);

        vm.chainId(L1_CHAIN_ID);
        forwarder.relay();
        assertEq(polygonOlas.balanceOf(address(forwarder)), AMOUNT, "Polygon token untouched on L1");
        assertEq(l1Olas.balanceOf(OLAS_BURNER), AMOUNT, "L1 token burned");
    }

    /// @dev Integration: Bridge2BurnerPolygon deployed with the forwarder as its recipient delivers OLAS to it, and
    ///      relay() then burns it on Polygon.
    function test_bridge2BurnerPolygon_deliversToForwarder_thenBurned() public {
        vm.chainId(POLYGON_CHAIN_ID);
        PolygonBurnForwarder forwarder = _deploy();
        Bridge2BurnerPolygon bridge2Burner = new Bridge2BurnerPolygon(address(polygonOlas), address(forwarder));
        assertEq(bridge2Burner.l2TokenRelayer(), address(forwarder), "recipient is the forwarder");

        // Bought-back OLAS, above the Bridge2Burner minimum
        polygonOlas.mint(address(bridge2Burner), AMOUNT);
        vm.prank(address(0xCA11));
        bridge2Burner.relayToL1Burner();
        assertEq(polygonOlas.balanceOf(address(bridge2Burner)), 0, "bridge2Burner emptied");
        assertEq(polygonOlas.balanceOf(address(forwarder)), AMOUNT, "OLAS reached the forwarder");

        forwarder.relay();
        assertEq(polygonOlas.balanceOf(address(forwarder)), 0, "forwarder burned it");
        assertEq(polygonOlas.totalSupply(), 0, "burned on Polygon");
    }

    function test_constructor_guards() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new PolygonBurnForwarder(address(0), address(l1Olas), OLAS_BURNER, POLYGON_CHAIN_ID, L1_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new PolygonBurnForwarder(address(polygonOlas), address(0), OLAS_BURNER, POLYGON_CHAIN_ID, L1_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new PolygonBurnForwarder(address(polygonOlas), address(l1Olas), address(0), POLYGON_CHAIN_ID, L1_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        new PolygonBurnForwarder(address(polygonOlas), address(l1Olas), OLAS_BURNER, 0, L1_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        new PolygonBurnForwarder(address(polygonOlas), address(l1Olas), OLAS_BURNER, POLYGON_CHAIN_ID, 0);
        vm.expectRevert(abi.encodeWithSignature("WrongChainId(uint256)", L1_CHAIN_ID));
        new PolygonBurnForwarder(address(polygonOlas), address(l1Olas), OLAS_BURNER, L1_CHAIN_ID, L1_CHAIN_ID);
    }
}
