pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LiquidityManagerETH} from "../contracts/pol/LiquidityManagerETH.sol";
import {NeighborhoodScanner} from "../contracts/pol/NeighborhoodScanner.sol";
import {UniswapPriceOracle} from "../contracts/oracles/UniswapPriceOracle.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IUniswapV2Pair} from "../contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../contracts/interfaces/IUniswapV3.sol";

interface ITreasury {
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success);
}


contract BaseSetup is Test {
    Utils internal utils;
    UniswapPriceOracle internal oracleV2;
    NeighborhoodScanner internal neighborhoodScanner;
    LiquidityManagerETH internal liquidityManager;

    address payable[] internal users;
    address internal deployer;
    address internal dev;

    // Contract addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address[] internal TOKENS = [0x0001A500A6B18995B03f44bb040A5fFc28E45CB0, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2];
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant PAIR_V2 = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    bytes32 internal constant PAIR_V2_BYTES32 = 0x00000000000000000000000009D1d767eDF8Fa23A64C51fa559E0688E526812F;
    address internal constant ROUTER_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant POSITION_MANAGER_V3 = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint16 internal constant observationCardinality = 60;
    uint16 internal constant maxSlippage = 5000;
    int24 internal constant FEE_TIER = 3000;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        oracleV2 = new UniswapPriceOracle(WETH, uint256(maxSlippage / 100), PAIR_V2);
        neighborhoodScanner = new NeighborhoodScanner();
        liquidityManager = new LiquidityManagerETH(OLAS, TIMELOCK, POSITION_MANAGER_V3, address(neighborhoodScanner),
            observationCardinality, maxSlippage, address(oracleV2), ROUTER_V2);

        // Get V2 pool balance
        uint256 v2Liquidity = IToken(PAIR_V2).balanceOf(TREASURY);

        // Transfer V2 pool liquidity to LiquidityManager
        vm.prank(TIMELOCK);
        ITreasury(TREASURY).withdraw(address(liquidityManager), v2Liquidity, PAIR_V2);

        (uint256 amount0, uint256 amount1, ) = IUniswapV2Pair(PAIR_V2).getReserves();
        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
        uint256 price = FixedPointMathLib.divWadDown(amount1, amount0);

        // Calculate the square root of the price ratio in X96 format
        uint160 sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);

        // Create V3 pool
        IUniswapV3(POSITION_MANAGER_V3).createAndInitializePoolIfNecessary(OLAS, WETH, uint24(FEE_TIER), sqrtPriceX96);
    }
}

contract LiquidityManagerETHTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testConvertToV3FullScan() public {
        int24[] memory tickShifts = new int24[](2);
        tickShifts[0] = -27000;
        tickShifts[1] = 17000;
        uint16 decreaseRate = 10000;
        bool scan = true;
        liquidityManager.convertToV3(TOKENS, PAIR_V2_BYTES32, FEE_TIER, tickShifts, decreaseRate, scan);
    }
}
