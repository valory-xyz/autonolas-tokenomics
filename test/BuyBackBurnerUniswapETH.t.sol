// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {BuyBackBurnerUniswap} from "../contracts/utils/BuyBackBurnerUniswap.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

/// @dev Fork tests for BuyBackBurnerUniswap on Ethereum mainnet.
///      Run: forge test -f $FORK_ETH_NODE_URL --match-contract BuyBackBurnerUniswapETH -vvv
contract BaseSetup is Test {
    Utils internal utils;
    UniswapPriceOracle internal oracleV2;
    BuyBackBurnerUniswap internal buyBackBurner;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Ethereum mainnet addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    address internal constant PAIR_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Oracle parameters
    uint256 internal constant maxOracleSlippageBps = 5000;
    uint256 internal constant minTwapWindowSeconds = 900;
    uint256 internal constant minUpdateIntervalSeconds = 900;

    // BuyBackBurner max slippage (used as BPS in oracle validatePrice, and as percentage in post-swap bounds)
    uint256 internal constant maxBuyBackSlippage = 1000; // 10%

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy V2 oracle (WETH as reference token, matching production)
        oracleV2 = new UniswapPriceOracle(PAIR_V2, WETH, maxOracleSlippageBps, minTwapWindowSeconds, minUpdateIntervalSeconds);

        // Warm up oracle: record observation, then warp past TWAP window
        oracleV2.updatePrice();
        vm.warp(block.timestamp + minTwapWindowSeconds + 1);

        // Deploy BuyBackBurnerUniswap implementation
        BuyBackBurnerUniswap buyBackBurnerImpl = new BuyBackBurnerUniswap(BURNER, TIMELOCK);

        // Construct proxy init payload: (accounts, maxSlippage)
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = WETH;
        accounts[2] = address(oracleV2);
        accounts[3] = ROUTER_V2;

        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts, maxBuyBackSlippage));

        // Deploy proxy and wrap
        BuyBackBurnerProxy proxy = new BuyBackBurnerProxy(address(buyBackBurnerImpl), initPayload);
        buyBackBurner = BuyBackBurnerUniswap(payable(address(proxy)));

        // Set V2 oracle mapping for WETH
        address[] memory secondTokens = new address[](1);
        secondTokens[0] = WETH;
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracleV2);
        buyBackBurner.setV2Oracles(secondTokens, oracles);
    }
}

contract BuyBackBurnerUniswapETH is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Proxy is correctly initialized.
    function testDeployment() public view {
        assertEq(buyBackBurner.olas(), OLAS);
        assertEq(buyBackBurner.nativeToken(), WETH);
        assertEq(buyBackBurner.router(), ROUTER_V2);
        assertEq(buyBackBurner.maxSlippage(), maxBuyBackSlippage);
        assertEq(buyBackBurner.bridge2Burner(), BURNER);
        assertEq(buyBackBurner.treasury(), TIMELOCK);
        assertEq(buyBackBurner.mapV2Oracles(WETH), address(oracleV2));
    }

    /// @dev V2 buyBack swaps WETH for OLAS and sends to OLAS burner.
    function testBuyBack() public {
        uint256 burnerBefore = IToken(OLAS).balanceOf(BURNER);
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0.1 ether);

        uint256 olasReceived = IToken(OLAS).balanceOf(BURNER) - burnerBefore;
        assertGt(olasReceived, 0);
        console.log("OLAS received by BURNER:", olasReceived);
    }

    /// @dev buyBack with zero balance reverts.
    function testBuyBackZeroBalance() public {
        vm.expectRevert();
        buyBackBurner.buyBack(WETH, 1 ether);
    }

    /// @dev buyBack adjusts amount to full balance when requested amount exceeds it.
    function testBuyBackAdjustsToBalance() public {
        uint256 burnerBefore = IToken(OLAS).balanceOf(BURNER);
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 1 ether);

        assertGt(IToken(OLAS).balanceOf(BURNER) - burnerBefore, 0);
        assertEq(IToken(WETH).balanceOf(address(buyBackBurner)), 0);
    }

    /// @dev buyBack with zero amount uses full balance.
    function testBuyBackZeroAmountUsesBalance() public {
        uint256 burnerBefore = IToken(OLAS).balanceOf(BURNER);
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0);

        assertGt(IToken(OLAS).balanceOf(BURNER) - burnerBefore, 0);
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

    /// @dev transfer sends non-whitelisted token to treasury (TIMELOCK).
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

    /// @dev transfer sends OLAS to BURNER.
    function testTransferOLASToBurner() public {
        uint256 burnerBefore = IToken(OLAS).balanceOf(BURNER);
        deal(OLAS, address(buyBackBurner), 1000 ether);

        buyBackBurner.transfer(OLAS);

        assertEq(IToken(OLAS).balanceOf(BURNER) - burnerBefore, 1000 ether);
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

    /// @dev buyBack increments activity counter.
    function testBuyBackActivityCounter() public {
        deal(WETH, address(buyBackBurner), 0.1 ether);

        buyBackBurner.buyBack(WETH, 0.1 ether);

        assertEq(buyBackBurner.mapAccountActivities(address(this)), 1);
    }
}
