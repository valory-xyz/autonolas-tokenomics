pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {Dispenser} from "../contracts/Dispenser.sol";
import "../contracts/Tokenomics.sol";
import {TokenomicsProxy} from "../contracts/TokenomicsProxy.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {MockRegistry} from "../contracts/test/MockRegistry.sol";
import {MockVE} from "../contracts/test/MockVE.sol";

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
    uint256[] internal unitTypes;
    uint256[] internal unitIds;
    address payable[] internal users;
    address internal deployer;
    bytes32 internal retainer;
    address internal dev;
    uint256 internal initialMint = 10_000_000_000e18;
    uint256 internal largeApproval = 1_000_000_000_000e18;
    uint256 epochLen = 30 days;

    function setUp() public virtual {
        emptyArray = new uint256[](0);
        serviceIds = new uint256[](2);
        (serviceIds[0], serviceIds[1]) = (1, 2);
        serviceAmounts = new uint256[](2);
        unitTypes = new uint256[](2);
        unitIds = new uint256[](2);
        utils = new Utils();
        users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        dev = users[1];
        vm.label(dev, "Developer");
        retainer = bytes32(uint256(uint160(deployer)));

        // Deploy contracts
        olas = new ERC20Token();
        ve = new MockVE();
        componentRegistry = new MockRegistry();
        agentRegistry = new MockRegistry();
        serviceRegistry = new MockRegistry();
        dispenser = new Dispenser(address(olas), deployer, deployer, deployer, retainer, 100, 100);

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
        treasury.changeManagers(address(tokenomics), address(0), address(0));
        // Change the tokenomics and treasury addresses in the dispenser to correct ones
        dispenser.changeManagers(address(tokenomics), address(treasury), address(0));

        // Set treasury contract as a minter for OLAS
        olas.changeMinter(address(treasury));
    }
}

contract DispenserTest is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Pseudo-random number generator in a range of 0 to 1000.
    function random(uint256 seed) private pure returns (uint256) {
        uint256 randomHash = uint256(keccak256(abi.encodePacked(seed)));
        return randomHash % 1000;
    }

    /// @dev Deposit incentives for 2 services.
    /// @notice Assume that no single donation is bigger than 2^64 - 1.
    /// @param amount0 Amount to donate to the first service.
    /// @param amount1 Amount to donate to the second service.
    function testIncentives(uint64 amount0, uint64 amount1) public {
        // Amounts must be meaningful
        vm.assume(amount0 > treasury.minAcceptedETH());
        vm.assume(amount1 > treasury.minAcceptedETH());

        // Try to claim empty incentives
        vm.prank(deployer);
        vm.expectRevert();
        (uint256 reward, uint256 topUp) = dispenser.claimOwnerIncentives(emptyArray, emptyArray);
        assertEq(reward, 0);
        assertEq(topUp, 0);

        // Lock OLAS balances with Voting Escrow
        ve.setWeightedBalance(tokenomics.veOLASThreshold());
        ve.createLock(deployer);

        // Change the first service owner to the deployer (same for components and agents)
        serviceRegistry.changeUnitOwner(1, deployer);
        componentRegistry.changeUnitOwner(1, deployer);
        agentRegistry.changeUnitOwner(1, deployer);

        // Send donations to services from the deployer
        (serviceAmounts[0], serviceAmounts[1]) = (amount0, amount1);
        vm.prank(deployer);
        treasury.depositServiceDonationsETH{value: serviceAmounts[0] + serviceAmounts[1]}(serviceIds, serviceAmounts);

        // Move at least epochLen seconds in time
        vm.warp(block.timestamp + epochLen + 10);
        // Mine a next block to avoid a flash loan attack condition
        vm.roll(block.number + 1);

        // Start new epoch and calculate tokenomics parameters and rewards
        tokenomics.checkpoint();

        // Get the last settled epoch counter
        uint256 lastPoint = tokenomics.epochCounter() - 1;
        assertEq(lastPoint, 1);
        // Get the epoch point of the last epoch
        EpochPoint memory ep = tokenomics.mapEpochTokenomics(lastPoint);
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

        // Rewards and top-ups must not be zero
        assertGt(accountRewards, 0);
        assertGt(accountTopUps, 0);

        // Check for the incentive balances of component and agent such that their pending relative incentives are non-zero
        (, uint256 pendingRelativeReward, , uint256 pendingRelativeTopUp, ) = tokenomics.mapUnitIncentives(0, 1);
        assertGt(pendingRelativeReward, 0);
        assertGt(pendingRelativeTopUp, 0);
        (, pendingRelativeReward, , pendingRelativeTopUp, ) = tokenomics.mapUnitIncentives(1, 1);
        assertGt(pendingRelativeReward, 0);
        assertGt(pendingRelativeTopUp, 0);

        // Define the types of units to claim rewards and top-ups for
        (unitTypes[0], unitTypes[1]) = (0, 1);
        // Define unit Ids to claim rewards and top-ups for
        (unitIds[0], unitIds[1]) = (1, 1);

        // Claim rewards and top-ups
        uint256 balanceETH = address(deployer).balance;
        uint256 balanceOLAS = olas.balanceOf(deployer);
        vm.prank(deployer);
        (rewards0, topUps0) = dispenser.claimOwnerIncentives(unitTypes, unitIds);

        // Check the ETH and OLAS balance after receiving incentives
        balanceETH = address(deployer).balance - balanceETH;
        balanceOLAS = olas.balanceOf(deployer) - balanceOLAS;
        assertEq(balanceETH, accountRewards);
        assertEq(balanceOLAS, accountTopUps);
    }

    /// @dev Deposit incentives for 2 services in a loop to go through a specified amount of time.
    /// @notice Assume that no single donation is bigger than 2^64 - 1.
    /// @param amount0 Amount to donate to the first service.
    /// @param amount1 Amount to donate to the second service.
    function testIncentivesLoopDirect(uint64 amount0, uint64 amount1) public {
        // Amounts must be meaningful
        vm.assume(amount0 > treasury.minAcceptedETH());
        vm.assume(amount1 > treasury.minAcceptedETH());

        // Lock OLAS balances with Voting Escrow
        ve.setWeightedBalance(tokenomics.veOLASThreshold());
        ve.createLock(deployer);

        // Change the first service owner to the deployer (same for components and agents)
        serviceRegistry.changeUnitOwner(1, deployer);
        componentRegistry.changeUnitOwner(1, deployer);
        agentRegistry.changeUnitOwner(1, deployer);

        // Define the types of units to claim rewards and top-ups for
        (unitTypes[0], unitTypes[1]) = (0, 1);
        // Define unit Ids to claim rewards and top-ups for
        (unitIds[0], unitIds[1]) = (1, 1);

        // Run for more than 2 years (more than 52 weeks in a year)
        uint256 endTime = 250 weeks;
        uint256 lastPoint = tokenomics.epochCounter() - 1;
        uint256 effectiveBond = tokenomics.effectiveBond();
        for (uint256 i = 0; i < endTime; i += epochLen) {
            // Send donations to services from the deployer
            (serviceAmounts[0], serviceAmounts[1]) = (amount0, amount1);
            vm.prank(deployer);
            treasury.depositServiceDonationsETH{value: serviceAmounts[0] + serviceAmounts[1]}(serviceIds, serviceAmounts);

            // Get the current year number
            uint256 curYear = tokenomics.currentYear();
            // Move at least epochLen seconds in time
            vm.warp(block.timestamp + epochLen);
            // Mine a next block to avoid a flash loan attack condition
            vm.roll(block.number + 1);

            // Check that the epoch counter is changed from the last time
            assertEq(lastPoint, tokenomics.epochCounter() - 1);
            // Start new epoch and calculate tokenomics parameters and rewards
            tokenomics.checkpoint();

            // Get the last settled epoch counter
            lastPoint = tokenomics.epochCounter() - 1;

            // Get the epoch point of the last epoch
            EpochPoint memory ep = tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            UnitPoint[] memory up = new UnitPoint[](2);
            (up[0], up[1]) = (tokenomics.getUnitPoint(lastPoint, 0), tokenomics.getUnitPoint(lastPoint, 1));

            // Calculate rewards based on the points information
            uint256 rewards0 = (ep.totalDonationsETH * up[0].rewardUnitFraction) / 100;
            uint256 rewards1 = (ep.totalDonationsETH * up[1].rewardUnitFraction) / 100;
            uint256 accountRewards = rewards0 + rewards1;
            // Calculate top-ups based on the points information
            uint256 topUps0 = (ep.totalTopUpsOLAS * up[0].topUpUnitFraction) / 100;
            uint256 topUps1 = (ep.totalTopUpsOLAS * up[1].topUpUnitFraction) / 100;
            uint256 accountTopUps = topUps0 + topUps1;
            // Calculate maxBond
            uint256 calculatedMaxBond = (ep.totalTopUpsOLAS * ep.maxBondFraction) / 100;
            // Compare it with the max bond calculated from the fraction and the total OLAS inflation for the epoch
            // Do not compare directly if the next epoch is the epoch where the year changes
            uint256 numYearsNextEpoch = (block.timestamp + tokenomics.epochLen() - tokenomics.timeLaunch()) / tokenomics.ONE_YEAR();
            if (numYearsNextEpoch == curYear) {
                assertEq(tokenomics.maxBond(), calculatedMaxBond);
            }
            // Effective bond must be the previous effective bond plus the actual maxBond
            assertEq(effectiveBond + tokenomics.maxBond(), tokenomics.effectiveBond());
            effectiveBond += tokenomics.maxBond();

            // Rewards and top-ups must not be zero
            assertGt(accountRewards, 0);
            assertGt(accountTopUps, 0);

            // Claim rewards and top-ups
            uint256 balanceETH = address(deployer).balance;
            uint256 balanceOLAS = olas.balanceOf(deployer);
            vm.prank(deployer);
            (rewards0, topUps0) = dispenser.claimOwnerIncentives(unitTypes, unitIds);

            // Check the ETH and OLAS balance after receiving incentives
            balanceETH = address(deployer).balance - balanceETH;
            balanceOLAS = olas.balanceOf(deployer) - balanceOLAS;
            assertEq(balanceETH, accountRewards);
            assertEq(balanceOLAS, accountTopUps);
        }
    }

    /// @dev Deposit incentives in a loop as the previous one and claim incentives ones in two epochs.
    /// @notice Assume that no single donation is bigger than 2^64 - 1.
    /// @param amount0 Amount to donate to the first service.
    /// @param amount1 Amount to donate to the second service.
    function testIncentivesLoopEvenOdd(uint64 amount0, uint64 amount1) public {
        // Amounts must be meaningful
        vm.assume(amount0 > treasury.minAcceptedETH());
        vm.assume(amount1 > treasury.minAcceptedETH());

        // Lock OLAS balances with Voting Escrow
        ve.setWeightedBalance(tokenomics.veOLASThreshold());
        ve.createLock(deployer);

        // Change the first service owner to the deployer (same for components and agents)
        serviceRegistry.changeUnitOwner(1, deployer);
        componentRegistry.changeUnitOwner(1, deployer);
        agentRegistry.changeUnitOwner(1, deployer);

        // Define the types of units to claim rewards and top-ups for
        (unitTypes[0], unitTypes[1]) = (0, 1);
        // Define unit Ids to claim rewards and top-ups for
        (unitIds[0], unitIds[1]) = (1, 1);

        uint256[] memory rewards = new uint256[](2);
        uint256[] memory topUps = new uint256[](2);

        // Run for more than 2 years (more than 52 weeks in a year)
        uint256 endTime = 110 weeks;
        for (uint256 i = 0; i < endTime; i += epochLen) {
            // Send donations to services from the deployer
            (serviceAmounts[0], serviceAmounts[1]) = (amount0, amount1);
            vm.prank(deployer);
            treasury.depositServiceDonationsETH{value: serviceAmounts[0] + serviceAmounts[1]}(serviceIds, serviceAmounts);

            // Move at least epochLen seconds in time with the random addition of seconds
            vm.warp(block.timestamp + epochLen + random(tokenomics.epochCounter()));
            // Mine a next block to avoid a flash loan attack condition
            vm.roll(block.number + 1);

            // Start new epoch and calculate tokenomics parameters and rewards
            tokenomics.checkpoint();

            // Get the last settled epoch counter
            uint256 lastPoint = tokenomics.epochCounter() - 1;

            // Get the epoch point of the last epoch
            EpochPoint memory ep = tokenomics.mapEpochTokenomics(lastPoint);
            // Get the unit points of the last epoch
            UnitPoint[] memory up = new UnitPoint[](2);
            (up[0], up[1]) = (tokenomics.getUnitPoint(lastPoint, 0), tokenomics.getUnitPoint(lastPoint, 1));

            // Calculate rewards based on the points information
            rewards[0] += (ep.totalDonationsETH * up[0].rewardUnitFraction) / 100;
            rewards[1] += (ep.totalDonationsETH * up[1].rewardUnitFraction) / 100;
            // Calculate top-ups based on the points information
            topUps[0] += (ep.totalTopUpsOLAS * up[0].topUpUnitFraction) / 100;
            topUps[1] += (ep.totalTopUpsOLAS * up[1].topUpUnitFraction) / 100;

            // Claim rewards and top-ups during even epoch numbers
            if ((tokenomics.epochCounter() % 2) == 0) {
                // This will be a sum up of two epoch incentives
                uint256 accountRewards = rewards[0] + rewards[1];
                uint256 accountTopUps = topUps[0] + topUps[1];

                uint256 balanceETH = address(deployer).balance;
                uint256 balanceOLAS = olas.balanceOf(deployer);
                vm.prank(deployer);
                (rewards[0], topUps[0]) = dispenser.claimOwnerIncentives(unitTypes, unitIds);

                // Check the ETH and OLAS balance after receiving incentives
                balanceETH = address(deployer).balance - balanceETH;
                balanceOLAS = olas.balanceOf(deployer) - balanceOLAS;
                assertEq(balanceETH, accountRewards);
                assertEq(balanceOLAS, accountTopUps);

                // Zero previously calculated rewards and top-ups
                rewards[0] = 0;
                rewards[1] = 0;
                topUps[0] = 0;
                topUps[1] = 0;
            }
        }
    }
}
