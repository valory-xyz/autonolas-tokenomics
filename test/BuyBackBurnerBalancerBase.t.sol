pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {BalancerPriceOracle} from "../contracts/oracles/BalancerPriceOracle.sol";
import {Bridge2BurnerOptimism} from "../contracts/utils/Bridge2BurnerOptimism.sol";
import {BuyBackBurnerBalancer} from "../contracts/utils/BuyBackBurnerBalancer.sol";
import {BuyBackBurnerProxy} from "../contracts/utils/BuyBackBurnerProxy.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";

// Balancer interface
interface IBalancer {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /// @dev Swaps tokens on Balancer.
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
    external payable returns (uint256);

    function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );
}

contract BaseSetup is Test {
    Utils internal utils;
    BalancerPriceOracle internal oracleV2;
    Bridge2BurnerOptimism internal bridge2Burner;
    BuyBackBurnerBalancer internal buyBackBurnerBalancer;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    uint256[2] internal initialAmounts;
    uint160 internal sqrtPriceX96;
    address internal constant OLAS = 0x54330d28ca3357F294334BDC454a032e7f353416;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address[] internal TOKENS = [WETH, OLAS];
    address internal constant TIMELOCK = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant L2_TOKEN_RELAYER = 0x4200000000000000000000000000000000000010;
    address internal constant POOL_V2 = 0x2da6e67C45aF2aaA539294D9FA27ea50CE4e2C5f;
    bytes32 internal constant POOL_V2_BYTES32 = 0x2da6e67c45af2aaa539294d9fa27ea50ce4e2c5f0002000000000000000001a3;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant maxSlippage = 50;
    uint256 internal constant minUpdateTimePeriod = 900;
    // Allowed rounding delta in 1e18 = 1%
    uint256 internal constant DELTA = 1e16;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy V2 oracle
        oracleV2 = new BalancerPriceOracle(OLAS, WETH, maxSlippage, minUpdateTimePeriod, BALANCER_VAULT, POOL_V2_BYTES32);

        // Advance some time such that oracle has a time difference between last updated price
        vm.warp(block.timestamp + 100);

        // Deploy Bridge2Burner
        bridge2Burner = new Bridge2BurnerOptimism(OLAS, L2_TOKEN_RELAYER);

        // Deploy BuyBackBurnerBalancer implementation
        // Note that LiquidityManager address is irrelevant in this set of tests
        BuyBackBurnerBalancer buyBackBurnerBalancerImplementation =
            new BuyBackBurnerBalancer(address(bridge2Burner), address(bridge2Burner));

        // Construct proxy data
        address[] memory accounts = new address[](4);
        accounts[0] = OLAS;
        accounts[1] = WETH;
        accounts[2] = address(oracleV2);
        accounts[3] = BALANCER_VAULT;

        // abi.decode(address[], bytes32, uint256)) of (accounts, balancerPoolId, maxSlippage)
        bytes memory initPayload =
            abi.encodeWithSignature("initialize(bytes)", abi.encode(accounts, POOL_V2_BYTES32, maxSlippage));
        // Deploy BuyBackBurnerProxy
        BuyBackBurnerProxy buyBackBurnerProxy =
            new BuyBackBurnerProxy(address(buyBackBurnerBalancerImplementation), initPayload);

        // Wrap proxy into implementation
        buyBackBurnerBalancer = BuyBackBurnerBalancer(address(buyBackBurnerProxy));
    }
}

contract BuyBackBurnerBalancerBase is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Buys back OLAS and sends to bridge2Burner
    function testBuyBackBurner() public {
        // Get WETH
        deal(WETH, address(buyBackBurnerBalancer), 1 ether);

        // Swap for OLAS
        buyBackBurnerBalancer.buyBack(1 ether);

        // Bridge OLAS to burn
        bridge2Burner.relayToL1Burner();
    }
}
