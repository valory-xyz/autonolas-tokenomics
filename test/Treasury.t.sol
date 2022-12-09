pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./utils/Utils.sol";
import "../contracts/Tokenomics.sol";
import "../contracts/Treasury.sol";
import "../contracts/test/ERC20Token.sol";

contract BaseSetup is Test {
    Utils internal utils;
    ERC20Token internal olas;
    ERC20Token internal dai;
    Treasury internal treasury;
    Tokenomics internal tokenomics;

    address payable[] internal users;
    address internal deployer;
    address internal dev;
    uint256 internal initialMint = 10_000_000_000e18;
    uint256 internal largeApproval = 1_000_000_000_000e18;
    uint32 epochLen = 100;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        olas = new ERC20Token();
        dai = new ERC20Token();

        // Correct treasury address is missing here, it will be defined just one line below
        tokenomics = new Tokenomics();
        tokenomics.initializeTokenomics(address(olas), address(deployer), address(deployer), address(deployer),
            address(deployer), epochLen, address(0), address(0), address(0), address(0));
        // Depository contract is irrelevant here, so we are using a deployer's address
        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        treasury = new Treasury(address(olas), deployer, address(tokenomics), address(0));

        // Change to the correct treasury address
        tokenomics.changeManagers(address(0), address(treasury), address(0), address(0));

        dai.mint(deployer, initialMint);
        vm.prank(deployer);
        dai.approve(address(treasury), largeApproval);
        olas.changeMinter(address(treasury));
    }
}

contract TreasuryTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testDeposit() public {
        // toggle DAI as reserve token (as example)
        treasury.enableToken(address(dai));

        // Deposit 10,000 DAI to treasury, 1,000 OLAS gets minted to deployer with 9000 as excess reserves (ready to be minted)
        uint256 daiAmount = 10_000e18;
        uint256 olasAmount = 1000e18;
        vm.prank(deployer);
        treasury.depositTokenForOLAS(deployer, daiAmount, address(dai), olasAmount);

        // Check that the requested minted amount of OLAS corresponds to its total supply
        assertEq(olas.totalSupply(), olasAmount);
    }
}
