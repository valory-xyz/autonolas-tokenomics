pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./utils/Utils.sol";
import "../contracts/Dispenser.sol";
import "../contracts/Tokenomics.sol";
import "../contracts/TokenomicsProxy.sol";
import "../contracts/Treasury.sol";
import "../contracts/test/ERC20Token.sol";
import "../contracts/test/MockRegistry.sol";
import "../contracts/test/MockVE.sol";

contract BaseSetup is Test {
    Utils internal utils;
    Dispenser internal dispenser;
    ERC20Token internal olas;
    MockRegistry internal componentRegistry;
    MockRegistry internal agentRegistry;
    MockRegistry internal serviceRegistry;
    MockVE internal ve;
    Treasury internal treasury;
    Tokenomics internal tokenomics;

    uint256[] internal emptyArray;
    address payable[] internal users;
    address internal deployer;
    address internal dev;
    uint256 internal initialMint = 10_000_000_000e18;
    uint256 internal largeApproval = 1_000_000_000_000e18;
    uint32 epochLen = 100;

    function setUp() public virtual {
        emptyArray = new uint256[](0);
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");

        // Deploy contracts
        olas = new ERC20Token();
        ve = new MockVE();
        componentRegistry = new MockRegistry();
        agentRegistry = new MockRegistry();
        serviceRegistry = new MockRegistry();
        dispenser = new Dispenser(deployer, deployer);

        // Depository contract is irrelevant here, so we are using a deployer's address
        // Correct tokenomics address will be added below
        treasury = new Treasury(address(olas), deployer, deployer, address(dispenser));

        Tokenomics tokenomicsMaster = new Tokenomics();
        bytes memory proxyData = abi.encodeWithSelector(tokenomicsMaster.initializeTokenomics.selector,
            address(olas), deployer, deployer, address(dispenser), address(ve), epochLen,
            address(componentRegistry), address(agentRegistry), address(serviceRegistry), address(0));
        TokenomicsProxy tokenomicsProxy = new TokenomicsProxy(address(tokenomicsMaster), proxyData);
        tokenomics = Tokenomics(address(tokenomicsProxy));

        // Change tokenomics address
        treasury.changeManagers(address(tokenomics), address(0), address(0), address(0));
        // Change the tokenomics and treasury addresses in the dispenser to correct ones
        dispenser.changeManagers(address(tokenomics), address(treasury), address(0), address(0));

        olas.changeMinter(address(treasury));
    }
}

contract TreasuryTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    function testIncentives() public {
        // Claim empty incentives
        vm.prank(deployer);
        (uint256 reward, uint256 topUp, ) = dispenser.claimOwnerIncentives(emptyArray, emptyArray);
        assertEq(reward, 0);
        assertEq(topUp, 0);
    }
}
