// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../Dispenser.sol";
import "../Depository.sol";
import "../Tokenomics.sol";
import "../Treasury.sol";
import {GenericBondCalculator} from "../GenericBondCalculator.sol";
import "./ERC20Token.sol";
import "./MockRegistry.sol";
import "./MockVE.sol";
import {ZuniswapV2Factory} from "../../lib/zuniswapv2/src/ZuniswapV2Factory.sol";
import {ZuniswapV2Router} from "../../lib/zuniswapv2/src/ZuniswapV2Router.sol";
import {ZuniswapV2Pair} from "../../lib/zuniswapv2/src/ZuniswapV2Pair.sol";

contract TestTokenomics {
    Depository public depository;
    Dispenser public dispenser;
    ERC20Token public olas;
    ERC20Token public dai;
    MockRegistry public componentRegistry;
    MockRegistry public agentRegistry;
    MockRegistry public serviceRegistry;
    MockVE public ve;
    Treasury public treasury;
    Tokenomics public tokenomics;
    GenericBondCalculator public genericBondCalculator;
    ZuniswapV2Factory public factory;
    ZuniswapV2Router public router;

    uint256[] internal emptyArray;
    uint256[] internal serviceIds;
    uint256[] internal serviceAmounts;
    uint256[] internal unitTypes;
    uint256[] internal unitIds;
    uint256 internal initialMint = 10_000_000_000e18;
    uint256 internal largeApproval = 1_000_000_000_000e18;
    uint256 internal epochLen = 1 weeks;
    uint256 internal amountOLAS = 5_000_000 ether;
    uint256 internal amountDAI = 5_000_000 ether;
    uint256 internal minAmountOLAS = 5_00 ether;
    uint256 internal minAmountDAI = 5_00 ether;
    uint256 internal supplyProductOLAS =  2_000 ether;
    uint256 internal defaultPriceLP = 2 ether;
    uint256 internal vesting = 2 weeks;
    uint256 internal initialLiquidity;
    address internal pair;
    uint256 public priceLP;
    uint256 internal productId;
    uint256 internal bondId;
    bool internal initialized;

    constructor(address _factory, address _router, address _olas, address _dai, address _tokenomics, address payable _treasury, address _depository,
        address _dispenser, address payable _componentRegistry, address payable _agentRegistry, address payable _serviceRegistry) payable
    {
        emptyArray = new uint256[](0);
        serviceIds = new uint256[](2);
        (serviceIds[0], serviceIds[1]) = (1, 2);
        serviceAmounts = new uint256[](2);
        unitTypes = new uint256[](2);
        unitIds = new uint256[](2);

        componentRegistry = MockRegistry(_componentRegistry);
        agentRegistry = MockRegistry(_agentRegistry);
        serviceRegistry = MockRegistry(_serviceRegistry);
        tokenomics = Tokenomics(_tokenomics);
        treasury = Treasury(_treasury);
        depository = Depository(_depository);
        dispenser = Dispenser(_dispenser);
        olas = ERC20Token(_olas);
        dai = ERC20Token(_dai);

        // Deploy factory and router
        factory = ZuniswapV2Factory(_factory);
        router = ZuniswapV2Router(_router);
    }

    receive() external payable {
    }

    function setUp() external {
        if (initialized) {
            revert();
        }
        initialized = true;
        olas.changeMinter(address(this));
        dai.changeMinter(address(this));
        olas.mint(address(this), initialMint);
        dai.mint(address(this), initialMint);

        // Set treasury contract as a minter for OLAS
        olas.changeMinter(address(treasury));

        // Change all unit owners
        serviceRegistry.changeUnitOwner(1, address(this));
        serviceRegistry.changeUnitOwner(2, address(this));
        componentRegistry.changeUnitOwner(1, address(this));
        componentRegistry.changeUnitOwner(2, address(this));
        agentRegistry.changeUnitOwner(1, address(this));
        agentRegistry.changeUnitOwner(2, address(this));

        // Create LP token
        factory.createPair(address(olas), address(dai));
        // Get the LP token address
        pair = factory.pairs(address(olas), address(dai));

        // Add liquidity
        olas.approve(address(router), largeApproval);
        dai.approve(address(router), largeApproval);

        (, , initialLiquidity) = router.addLiquidity(
            address(dai),
            address(olas),
            amountDAI,
            amountOLAS,
            amountDAI,
            amountOLAS,
            address(this)
        );

        // Enable LP token in treasury
        treasury.enableToken(pair);
        priceLP = depository.getCurrentPriceLP(pair);

        // Give a large approval for treasury
        ZuniswapV2Pair(pair).approve(address(treasury), largeApproval);

        // Create the first bond product
        productId = depository.create(pair, priceLP, supplyProductOLAS, vesting);

        // Deposit to one bond
        (, , bondId) = depository.deposit(productId, 1_000 ether);
    }


    /// @dev Donate to services, call checkpoint and claim incentives.
    function fullTokenomicsRun(uint256 amount0, uint256 amount1) external {
        require(amount0 + amount1 < address(this).balance, "test balance is low");
        (serviceAmounts[0], serviceAmounts[1]) = (amount0, amount1);
        treasury.depositServiceDonationsETH{value: serviceAmounts[0] + serviceAmounts[1]}(serviceIds, serviceAmounts);

        // Checkpoint only if we move to the next epoch
        uint256 eCounter = tokenomics.epochCounter() - 1;
        EpochPoint memory tPoint = tokenomics.mapEpochTokenomics(eCounter);
        uint256 lastEndTime = tPoint.endTime;
        uint256 eLength = tokenomics.epochLen();
        if (block.timestamp > (lastEndTime + eLength)) {
            tokenomics.checkpoint();
        }

        // Define the types of units to claim rewards and top-ups for
        (unitTypes[0], unitTypes[1]) = (0, 1);
        // Define unit Ids to claim rewards and top-ups for
        (unitIds[0], unitIds[1]) = (1, 1);
        (uint256 reward, uint256 topUp) = tokenomics.getOwnerIncentives(address(this), unitTypes, unitIds);
        if (reward + topUp > 0) {
            dispenser.claimOwnerIncentives(unitTypes, unitIds);
        }

        (unitIds[0], unitIds[1]) = (2, 2);
        (reward, topUp) = tokenomics.getOwnerIncentives(address(this), unitTypes, unitIds);
        if (reward + topUp > 0) {
            dispenser.claimOwnerIncentives(unitTypes, unitIds);
        }
    }

    /// @dev Create bond prodict with the specified LP token.
    function createBondProduct(uint256 supply) external {
        productId = depository.create(pair, priceLP, supply, vesting);
    }

    /// @dev Deposit LP token to the bond product with the max of uint96 tokenAmount.
    function depositBond96Id0(uint96 tokenAmount) external {
        if (tokenAmount < ZuniswapV2Pair(pair).balanceOf(address(this))) {
            depository.deposit(0, tokenAmount);
        }
    }

    /// @dev Deposit LP token to the bond product with the max of uint96 tokenAmount.
    function depositBond96(uint96 tokenAmount) external {
        if (tokenAmount < ZuniswapV2Pair(pair).balanceOf(address(this))) {
            depository.deposit(productId, tokenAmount);
        }
    }

    /// @dev Deposit LP token to the bond product.
    function depositBond256Id0(uint256 tokenAmount) external {
        depository.deposit(0, tokenAmount);
    }

    /// @dev Deposit LP token to the bond product.
    function depositBond256(uint256 tokenAmount) external {
        depository.deposit(productId, tokenAmount);
    }

    /// @dev Redeem OLAS from the bond program.
    function redeemBond() external {
        (uint256[] memory bondIds, ) = depository.getBonds(address(this), true);
        depository.redeem(bondIds);
    }

    /// @dev Withdraw LP tokens.
    function withdrawLPToken(uint256 tokenAmount) external {
        require(tokenAmount < 1_000);
        treasury.withdraw(address(0), tokenAmount, pair);
    }

    /// @dev Withdraw ETH.
    function withdrawETH(uint256 tokenAmount) external {
        require(tokenAmount < 100_000);
        treasury.withdraw(address(0), tokenAmount, treasury.ETH_TOKEN_ADDRESS());
    }
}
