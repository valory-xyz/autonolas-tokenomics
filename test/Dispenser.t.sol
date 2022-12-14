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
    uint256[] internal serviceIds;
    uint256[] internal serviceAmounts;
    address payable[] internal users;
    address internal deployer;
    address internal dev;
    uint256 internal initialMint = 10_000_000_000e18;
    uint256 internal largeApproval = 1_000_000_000_000e18;
    uint32 epochLen = 100;

    function setUp() public virtual {
        emptyArray = new uint256[](0);
        serviceIds = new uint256[](2);
        (serviceIds[0], serviceIds[1]) = (1, 2);
        serviceAmounts = new uint256[](2);
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
        // Depository contract is irrelevant here, so we are using a deployer's address
        bytes memory proxyData = abi.encodeWithSelector(tokenomicsMaster.initializeTokenomics.selector,
            address(olas), address(treasury), deployer, address(dispenser), address(ve), epochLen,
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

        // Change the first service owner to the deployer (same for components and agents)
        serviceRegistry.changeUnitOwner(1, deployer);
        componentRegistry.changeUnitOwner(1, deployer);
        agentRegistry.changeUnitOwner(1, deployer);

        // Send donations to services from the deployer
        (serviceAmounts[0], serviceAmounts[1]) = (1 ether, 1 ether);
        vm.prank(deployer);
        treasury.depositServiceDonationsETH{value: 2 ether}(serviceIds, serviceAmounts);

        // Move at least epochLen seconds in time
        vm.warp(block.timestamp + epochLen + 10);

        // Start new epoch and calculate tokenomics parameters and rewards
        tokenomics.checkpoint();

        // Get the last settled epoch counter
        uint256 lastPoint = tokenomics.epochCounter() - 1;
        assertEq(lastPoint, 1);
        // Get the epoch point of the last epoch
        EpochPoint memory ep = tokenomics.getEpochPoint(lastPoint);
        // Get the unit points of the last epoch
        UnitPoint memory up0 = tokenomics.getUnitPoint(lastPoint, 0);
        UnitPoint memory up1 = tokenomics.getUnitPoint(lastPoint, 1);

        // Calculate rewards based on the points information
        uint256 rewards0 = (ep.totalDonationsETH * up0.rewardUnitFraction) / 100;
        uint256 rewards1 = (ep.totalDonationsETH * up1.rewardUnitFraction) / 100;
        uint256 accountRewards = rewards0 + rewards1;
        // Calculate top-ups based on the points information
        uint256 topUps0 = (ep.totalTopUpsOLAS * up0.topUpUnitFraction) / 100;
        uint256 topUps1 = (ep.totalTopUpsOLAS * up1.topUpUnitFraction) / 100;
        uint256 accountTopUps = topUps0 + topUps1;

        assertGe(accountRewards, 0);
        assertGe(accountTopUps, 0);

        // Check for the incentive balances of component and agent such that their pending relative incentives are non-zero
        IncentiveBalances memory incentiveBalances = tokenomics.getIncentiveBalances(0, 1);
        assertGe(incentiveBalances.pendingRelativeReward, 0);
        assertGe(incentiveBalances.pendingRelativeTopUp, 0);
        incentiveBalances = tokenomics.getIncentiveBalances(1, 1);
        assertGe(incentiveBalances.pendingRelativeReward, 0);
        assertGe(incentiveBalances.pendingRelativeTopUp, 0);

        // Define the types of units to claim rewards and top-ups for
        (serviceIds[0], serviceIds[1]) = (0, 1);
        // Define unit Ids to claim rewards and top-ups for
        (serviceAmounts[0], serviceAmounts[1]) = (1, 1);
        // Claim rewards and top-ups
        uint256 balanceOLAS = olas.balanceOf(deployer);
        vm.prank(deployer);
        (rewards0, topUps0, ) = dispenser.claimOwnerIncentives(serviceIds, serviceAmounts);
        // Check the OLAS balance after receiving incentives
        balanceOLAS = olas.balanceOf(deployer) - balanceOLAS;
        assertEq(balanceOLAS, accountTopUps);
    }
}
