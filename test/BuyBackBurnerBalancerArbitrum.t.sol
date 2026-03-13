// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {Bridge2BurnerArbitrum} from "../contracts/utils/Bridge2BurnerArbitrum.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

/// @dev Fork tests for BuyBackBurnerBalancer on Arbitrum.
///      Run: forge test -f $FORK_ARBITRUM_NODE_URL --mc BuyBackBurnerBalancerArbitrum -vvv
contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracleV2;
    Bridge2BurnerArbitrum internal bridge2Burner;
    BuyBackBurnerBalancer internal buyBackBurner;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Arbitrum mainnet addresses
    address internal constant OLAS = 0x064F8B858C2A603e1b106a2039f5446D32dc81c1;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant TIMELOCK = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F;
    address internal constant L2_GATEWAY_ROUTER = 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;
    address internal constant L1_OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    bytes32 internal constant POOL_ID = 0xaf8912a3c4f55a8584b67df30ee0ddf0e60e01f80002000000000000000004fc;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Oracle parameters
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;
    uint256 internal constant maxStalenessSeconds = 900;

    // BuyBackBurner max slippage (used as percentage in post-swap bounds)
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
            minTwapWindowSeconds, minUpdateIntervalSeconds, maxStalenessSeconds
        );

        // Warm up oracle: two observations needed so both prevObservation and lastObservation are populated.
        // First observation fills lastObservation (prev stays {0,0}).
        oracleV2.updatePrice();
        // Warp past minUpdateInterval, second observation shifts last→prev and records new last.
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        oracleV2.updatePrice();

        // Deploy Bridge2Burner with L2GatewayRouter and L1 OLAS address
        bridge2Burner = new Bridge2BurnerArbitrum(OLAS, L2_GATEWAY_ROUTER, L1_OLAS);

        // Deploy BuyBackBurnerBalancer implementation
        BuyBackBurnerBalancer buyBackBurnerImpl = new BuyBackBurnerBalancer(address(bridge2Burner), TIMELOCK);

        // Construct proxy init payload: (accounts, balancerPoolId, maxSlippage)
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = WETH;
        accounts[2] = address(oracleV2);
        accounts[3] = BALANCER_VAULT;

        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts, POOL_ID, maxBuyBackSlippage));

        // Deploy proxy and wrap
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(buyBackBurnerImpl), initPayload);
        buyBackBurner = BuyBackBurnerBalancer(payable(address(proxy)));

        // Set V2 oracle mapping for WETH
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracleV2);
        buyBackBurner.setV2Oracles(secondTokens, oracles);
    }
}

contract BuyBackBurnerBalancerArbitrum is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Proxy is correctly initialized.
    function testDeployment() public view {
        assertEq(buyBackBurner.olas(), OLAS);
        assertEq(buyBackBurner.nativeToken(), WETH);
        assertEq(buyBackBurner.maxSlippage(), maxBuyBackSlippage);
        assertEq(buyBackBurner.bridge2Burner(), address(bridge2Burner));
        assertEq(buyBackBurner.treasury(), TIMELOCK);
        assertEq(buyBackBurner.mapV2Oracles(WETH), address(oracleV2));
    }

    /// @dev V2 buyBack swaps WETH for OLAS and sends to bridge2Burner.
    function testBuyBack() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0.1 ether);

        uint256 olasBal = IToken(OLAS).balanceOf(address(bridge2Burner));
        assertGt(olasBal, 0);
        console.log("OLAS at bridge2Burner:", olasBal);
    }

    /// @dev buyBack with zero balance reverts.
    function testBuyBackZeroBalance() public {
        vm.expectRevert();
        buyBackBurner.buyBack(WETH, 1 ether);
    }

    /// @dev buyBack adjusts amount to full balance when requested amount exceeds it.
    function testBuyBackAdjustsToBalance() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 1 ether);

        assertGt(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
        assertEq(IToken(WETH).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev buyBack with zero amount uses full balance.
    function testBuyBackZeroAmountUsesBalance() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0);

        assertGt(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
        assertEq(IToken(WETH).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev updateOraclePrice works through BuyBackBurner.
    function testUpdateOraclePrice() public {
        vm.warp(block.timestamp + minUpdateIntervalSeconds);

        buyBackBurner.updateOraclePrice(WETH);

        assertEq(buyBackBurner.mapAccountActivities(address(this)), 1);
    }

    /// @dev updateOraclePrice reverts when rate-limited.
    function testUpdateOraclePriceRateLimited() public {
        vm.warp(block.timestamp + minUpdateIntervalSeconds);
        buyBackBurner.updateOraclePrice(WETH);

        vm.expectRevert();
        buyBackBurner.updateOraclePrice(WETH);
    }

    /// @dev setV2Oracles reverts for non-owner.
    function testSetV2OraclesNotOwner() public {
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
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

    /// @dev transfer reverts for whitelisted swap token (WETH has oracle mapped).
    function testTransferWhitelistedTokenReverts() public {
        deal(WETH, address(buyBackBurner), 1 ether);

        vm.expectRevert();
        buyBackBurner.transfer(WETH);
    }

    /// @dev Proxy can receive native ETH funds.
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

    /// @dev Full flow: buyBack WETH then relay OLAS to L1 via Arbitrum L2 Gateway Router.
    function testBuyBackAndRelay() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0.1 ether);

        uint256 olasBal = IToken(OLAS).balanceOf(address(bridge2Burner));
        assertGt(olasBal, 0);

        // Mock ArbSys precompile at 0x64 (not available in fork environment)
        // ArbSys.sendTxToL1(address,bytes) is called by the Arbitrum gateway to relay L2→L1 messages
        vm.mockCall(
            address(0x0000000000000000000000000000000000000064),
            abi.encodeWithSignature("sendTxToL1(address,bytes)"),
            abi.encode(uint256(1))
        );

        bridge2Burner.relayToL1Burner();

        assertEq(IToken(OLAS).balanceOf(address(bridge2Burner)), 0);
    }

    /// @dev buyBack increments activity counter.
    function testBuyBackActivityCounter() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0.1 ether);

        assertEq(buyBackBurner.mapAccountActivities(address(this)), 1);
    }

    /// @dev buyBack reverts when oracle observation is stale.
    function testBuyBackStaleOracle() public {
        vm.warp(block.timestamp + maxStalenessSeconds + 1);

        deal(WETH, address(buyBackBurner), 0.1 ether);

        vm.expectRevert();
        buyBackBurner.buyBack(WETH, 0.1 ether);
    }
}
