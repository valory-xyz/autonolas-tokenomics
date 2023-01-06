pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "unifap-v2/UnifapV2Factory.sol";
import "unifap-v2/UnifapV2Router.sol";
import "unifap-v2/UnifapV2Pair.sol";
import "./utils/Utils.sol";
import "../contracts/Depository.sol";
import "../contracts/test/ERC20Token.sol";
import "unifap-v2/libraries/UnifapV2Library.sol";
//import "solmate/test/utils/mocks/MockERC20.sol";

contract BaseSetup is Test {
    Utils internal utils;
    ERC20Token internal olas;
    ERC20Token internal dai;
    UnifapV2Factory internal factory;
    UnifapV2Router internal router;

    address payable[] internal users;
    address internal deployer;
    address internal dev;
    address internal pair;
    uint256 internal initialMint = 40_000 ether;
    uint256 internal largeApproval = 1_000_000 ether;
    uint256 internal initialLiquidity;
    uint256 internal amountOLAS = 5_000 ether;
    uint256 internal amountDAI = 5_000 ether;
    uint256 internal minAmountOLAS = 5_00 ether;
    uint256 internal minAmountDAI = 5_00 ether;

//    MockERC20 public token0;
//    MockERC20 public token1;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy factory and router
        factory = new UnifapV2Factory();
        router = new UnifapV2Router(address(factory));

        // Get tokens and their initial mint
        olas = new ERC20Token();
        olas.mint(address(this), initialMint);
        dai = new ERC20Token();
        dai.mint(address(this), initialMint);

        // Create LP token
        factory.createPair(address(olas), address(dai));
        // Get the LP token address
        pair = factory.pairs(address(olas), address(dai));

        // Add liquidity
        olas.approve(address(router), largeApproval);
        dai.approve(address(router), largeApproval);

//        (, , initialLiquidity) = router.addLiquidity(
//            address(dai),
//            address(olas),
//            amountDAI,
//            amountOLAS,
//            amountDAI,
//            amountOLAS,
//            address(this),
//            block.timestamp + 1
//        );

//        token0 = new MockERC20("UnifapToken0", "UT0", 18);
//        token1 = new MockERC20("UnifapToken1", "UT1", 18);
//
//        token0.mint(address(this), 10 ether);
//        token1.mint(address(this), 10 ether);
    }
}

contract DepositoryTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testMint() public {
        assertEq(dai.balanceOf(deployer), initialMint);
    }

//    function testDefault() public {
//        token0.approve(address(router), 1 ether);
//        token1.approve(address(router), 1 ether);
//
//        (address _token0, address _token1) = UnifapV2Library.sortPairs(
//            address(token0),
//            address(token1)
//        );
//        address pair = UnifapV2Library.pairFor(
//            address(factory),
//            _token0,
//            _token1
//        );
//
////        factory.createPair(address(token0), address(token1));
//        (, , uint256 liquidity) = router.addLiquidity(
//            address(token0),
//            address(token1),
//            1 ether,
//            1 ether,
//            1 ether,
//            1 ether,
//            address(this),
//            block.timestamp + 1
//        );
//
//        assertEq(liquidity, 1 ether - UnifapV2Pair(pair).MINIMUM_LIQUIDITY());
//        assertEq(factory.pairs(address(token0), address(token1)), pair);
//    }
}
