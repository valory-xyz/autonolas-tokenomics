// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {Bridge2BurnerPolygon} from "../contracts/utils/Bridge2BurnerPolygon.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

/// @dev Fork tests for BuyBackBurnerBalancer on Polygon.
///      Run: forge test -f $FORK_POLYGON_NODE_URL --mc BuyBackBurnerBalancerPolygon -vvv
contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracleV2;
    Bridge2BurnerPolygon internal bridge2Burner;
    BuyBackBurnerBalancer internal buyBackBurner;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Polygon mainnet addresses
    address internal constant OLAS = 0xFEF5d947472e72Efbb2E388c730B7428406F2F95;
    address internal constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address internal constant TIMELOCK = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    bytes32 internal constant POOL_ID = 0x62309056c759c36879cde93693e7903bf415e4bc000200000000000000000d5f;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    // Oracle parameters
    uint256 internal constant maxOracleSlippageBps = 5000;
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 900;

    // BuyBackBurner max slippage (used as BPS in oracle validatePrice, and as percentage in post-swap bounds)
    uint256 internal constant maxBuyBackSlippage = 1000; // 10%

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy V2 oracle
        oracleV2 = new BalancerPriceOracle(
            BALANCER_VAULT, POOL_ID, OLAS,
            maxOracleSlippageBps, minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds
        );

        // Warm up oracle: two observations needed so both prevObservation and lastObservation are populated.
        // First observation fills lastObservation (prev stays {0,0}).
        oracleV2.updatePrice();
        // Warp past minUpdateInterval, second observation shifts last→prev and records new last.
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracleV2.updatePrice();

        // Deploy Bridge2Burner (l2TokenRelayer is OLAS itself for Polygon PoS withdrawTo)
        bridge2Burner = new Bridge2BurnerPolygon(OLAS, OLAS);

        // Deploy BuyBackBurnerBalancer implementation
        BuyBackBurnerBalancer buyBackBurnerImpl = new BuyBackBurnerBalancer(address(bridge2Burner), TIMELOCK);

        // Construct proxy init payload: (accounts, balancerPoolId, maxSlippage)
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = WMATIC;
        accounts[2] = address(oracleV2);
        accounts[3] = BALANCER_VAULT;

        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts, POOL_ID, maxBuyBackSlippage));

        // Deploy proxy and wrap
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(buyBackBurnerImpl), initPayload);
        buyBackBurner = BuyBackBurnerBalancer(payable(address(proxy)));

        // Set V2 oracle mapping for WMATIC
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WMATIC;
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracleV2);
        buyBackBurner.setV2Oracles(secondTokens, oracles);
    }
}

contract BuyBackBurnerBalancerPolygon is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Proxy is correctly initialized.
    function testDeployment() public view {
        assertEq(buyBackBurner.olas(), OLAS);
        assertEq(buyBackBurner.nativeToken(), WMATIC);
        assertEq(buyBackBurner.maxSlippage(), maxBuyBackSlippage);
        assertEq(buyBackBurner.bridge2Burner(), address(bridge2Burner));
        assertEq(buyBackBurner.treasury(), TIMELOCK);
        assertEq(buyBackBurner.mapV2Oracles(WMATIC), address(oracleV2));
    }

    /// @dev V2 buyBack swaps WMATIC for OLAS and sends to bridge2Burner.
    function testBuyBack() public {
        deal(WMATIC, address(buyBackBurner), 100 ether);

        buyBackBurner.buyBack(WMATIC, 100 ether);

        uint256 olasBal = IToken(OLAS).balanceOf(address(bridge2Burner));
        assertGt(olasBal, 0);
        console.log("OLAS at bridge2Burner:", olasBal);
    }

    /// @dev buyBack with zero balance reverts.
    function testBuyBackZeroBalance() public {
        vm.expectRevert();
        buyBackBurner.buyBack(WMATIC, 1 ether);
    }

    /// @dev buyBack adjusts amount to full balance when requested amount exceeds it.
    function testBuyBackAdjustsToBalance() public {
        deal(WMATIC, address(buyBackBurner), 100 ether);

        buyBackBurner.buyBack(WMATIC, 1000 ether);

        assertGt(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
        assertEq(IToken(WMATIC).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev buyBack with zero amount uses full balance.
    function testBuyBackZeroAmountUsesBalance() public {
        deal(WMATIC, address(buyBackBurner), 100 ether);

        buyBackBurner.buyBack(WMATIC, 0);

        assertGt(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
        assertEq(IToken(WMATIC).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev updateOraclePrice works through BuyBackBurner.
    function testUpdateOraclePrice() public {
        vm.warp(block.timestamp + minUpdateIntervalSeconds);

        buyBackBurner.updateOraclePrice(WMATIC);

        assertEq(buyBackBurner.mapAccountActivities(address(this)), 1);
    }

    /// @dev updateOraclePrice reverts when rate-limited.
    function testUpdateOraclePriceRateLimited() public {
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        buyBackBurner.updateOraclePrice(WMATIC);

        vm.expectRevert();
        buyBackBurner.updateOraclePrice(WMATIC);
    }

    /// @dev setV2Oracles reverts for non-owner.
    function testSetV2OraclesNotOwner() public {
        address[] memory tokens = new address[](1);
        tokens[0] = WMATIC;
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracleV2);

        vm.prank(dev);
        vm.expectRevert();
        buyBackBurner.setV2Oracles(tokens, oracles);
    }

    /// @dev transfer sends non-whitelisted token to treasury.
    function testTransferToTreasury() public {
        uint256 timelockBefore = IToken(USDC).balanceOf(TIMELOCK);
        deal(USDC, address(buyBackBurner), 1000e6);

        buyBackBurner.transfer(USDC);

        assertEq(IToken(USDC).balanceOf(TIMELOCK) - timelockBefore, 1000e6);
        assertEq(IToken(USDC).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev transfer reverts for whitelisted swap token (WMATIC has oracle mapped).
    function testTransferWhitelistedTokenReverts() public {
        deal(WMATIC, address(buyBackBurner), 1 ether);

        vm.expectRevert();
        buyBackBurner.transfer(WMATIC);
    }

    /// @dev Proxy can receive native funds.
    function testReceiveNativeFunds() public {
        deal(address(this), 1 ether);
        (bool success,) = address(buyBackBurner).call{value: 1 ether}("");
        assertTrue(success);
    }

    /// @dev setV2Oracles reverts when secondToken is OLAS.
    function testSetV2OraclesOLASReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = OLAS;
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracleV2);

        vm.expectRevert();
        buyBackBurner.setV2Oracles(tokens, oracles);
    }

    /// @dev transfer sends OLAS to bridge2Burner.
    function testTransferOLASToBridge() public {
        deal(OLAS, address(buyBackBurner), 1000 ether);

        buyBackBurner.transfer(OLAS);

        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)), 1000 ether);
        assertEq(IToken(OLAS).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev transfer reverts on zero balance.
    function testTransferZeroBalanceReverts() public {
        vm.expectRevert();
        buyBackBurner.transfer(USDC);
    }

    /// @dev changeOwner works for current owner.
    function testChangeOwner() public {
        buyBackBurner.changeOwner(dev);
        assertEq(buyBackBurner.owner(), dev);
    }

    /// @dev changeOwner reverts for non-owner.
    function testChangeOwnerNotOwner() public {
        vm.prank(dev);
        vm.expectRevert();
        buyBackBurner.changeOwner(dev);
    }

    /// @dev Full flow: buyBack WMATIC then relay OLAS to L1 via Polygon PoS bridge.
    function testBuyBackAndRelay() public {
        deal(WMATIC, address(buyBackBurner), 100 ether);

        buyBackBurner.buyBack(WMATIC, 100 ether);

        uint256 olasBal = IToken(OLAS).balanceOf(address(bridge2Burner));
        assertGt(olasBal, 0);

        bridge2Burner.relayToL1Burner();

        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
    }

    /// @dev buyBack increments activity counter.
    function testBuyBackActivityCounter() public {
        deal(WMATIC, address(buyBackBurner), 100 ether);

        buyBackBurner.buyBack(WMATIC, 100 ether);

        assertEq(buyBackBurner.mapAccountActivities(address(this)), 1);
    }

    /// @dev buyBack reverts when oracle observation is stale.
    function testBuyBackStaleOracle() public {
        vm.warp(block.timestamp + maxStalenessSeconds + 1);

        deal(WMATIC, address(buyBackBurner), 100 ether);

        vm.expectRevert();
        buyBackBurner.buyBack(WMATIC, 100 ether);
    }
}
