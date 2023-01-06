pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "unifap-v2/UnifapV2Router.sol";
import "./utils/Utils.sol";
import "../contracts/Depository.sol";
//import "../contracts/test/ERC20Token.sol";

contract BaseSetup is Test {
    Utils internal utils;
//    ERC20Token internal olas;
//    ERC20Token internal dai;
    UnifapV2Router internal router;

    address payable[] internal users;
    address internal deployer;
    address internal dev;
    uint256 internal initialMint = 40_000e18;
    uint256 internal largeApproval = 1_000_000e18;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

//        olas = new ERC20Token();
//        olas.mint(deployer, initialMint);
//        dai = new ERC20Token();
//        dai.mint(deployer, initialMint);
    }
}

contract DepositoryTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testMint() public {
//        assertEq(dai.balanceOf(deployer), initialMint);
    }
}
