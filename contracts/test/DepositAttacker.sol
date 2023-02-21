// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IToken.sol";
import "../interfaces/IUniswapV2Pair.sol";

interface IDepository {
    function deposit(uint256 productId, uint256 tokenAmount) external
        returns (uint256 payout, uint256 expiry, uint256 bondId);
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

interface IZRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external returns (uint[] memory amounts);
}

/// @title DepositAttacker - Smart contract to prove that the deposit attack via price manipulation is not possible
contract DepositAttacker {
    uint256 public constant LARGE_APPROVAL = 1_000_000 * 1e18;
    
    constructor() {}

    /// @dev Emulate attack against depository using the original Uniswap interface.
    /// @param depository Address of depository.
    /// @param treasury Address of treasury.
    /// @param token Address of an LP token.
    /// @param olas Address of OLAS token
    /// @param bid number of bid
    /// @param amountTo amount LP for deposit.
    /// @param swapRouter uniswapV2 router address.
    function flashAttackDepositImmuneOriginal(address depository, address treasury, address token, address olas, uint32 bid,
        uint256 amountTo, address swapRouter) external returns (uint256 payout)
    {
        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        // await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        // depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        IToken(token).approve(treasury, LARGE_APPROVAL);
        // IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = IUniswapV2Pair(address(token)).token0();
        address token1 = IUniswapV2Pair(address(token)).token1();
        uint256 balance0 = IToken(token0).balanceOf(token);
        uint256 balance1 = IToken(token1).balanceOf(token);
        // uint256 totalSupply = pair.totalSupply();
        uint256 balanceOLA = (token0 == olas) ? balance0 : balance1;
        uint256 balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved before deposit", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before deposit", balanceDAI);
        // uint256 amountToSwap = IToken(olas).balanceOf(address(this));

        path[0] = (token0 == olas) ? token0 : token1;
        path[1] = (token0 == olas) ? token1 : token0;

        // console.log("balance OLAS in this contract before swap {pseudo flash loan OLAS}:",IToken(olas).balanceOf(address(this)));
        IToken(olas).approve(swapRouter, LARGE_APPROVAL);
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IToken(olas).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        // console.log("balance OLAS in this contract after swap:",IToken(olas).balanceOf(address(this)));

        balance0 = IToken(token0).balanceOf(token);
        balance1 = IToken(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);

        (payout, , ) = IDepository(depository).deposit(bid, amountTo);
        
        // DAI approve 
        IToken(path[1]).approve(swapRouter, LARGE_APPROVAL);
        // swap back
        path[0] = path[1];
        path[1] = olas;
        amounts = IRouter(swapRouter).swapExactTokensForTokens(IToken(path[0]).balanceOf(address(this)), 0, path, address(this), block.timestamp + 3000);
        // console.log("balance OLAS in this contract after swap:", IToken(olas).balanceOf(address(this)));

        balance0 = IToken(token0).balanceOf(token);
        balance1 = IToken(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);
    }

    /// @dev Emulate attack against depository using the cloned implementation of Uniswap.
    /// @param treasury Address of depository.
    /// @param treasury Address of treasury.
    /// @param token Address of pair
    /// @param olas Address of OLAS token
    /// @param bid number of bid
    /// @param amountTo amount LP for deposit.
    /// @param swapRouter uniswapV2 router address.
    function flashAttackDepositImmuneClone(address depository, address treasury, address token, address olas, uint32 bid,
        uint256 amountTo, address swapRouter) external returns (uint256 payout)
    {
        // Trying to deposit the amount that would result in an overflow payout for the LP supply
        // await pairODAI.connect(deployer).approve(depository.address, LARGE_APPROVAL);
        // depository.connect(deployer).deposit(pairODAI.address, bid, amountTo, deployer.address);
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        IToken(token).approve(treasury, LARGE_APPROVAL);
        // IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = IUniswapV2Pair(address(token)).token0();
        address token1 = IUniswapV2Pair(address(token)).token1();
        uint256 balance0 = IToken(token0).balanceOf(token);
        uint256 balance1 = IToken(token1).balanceOf(token);
        // uint256 totalSupply = pair.totalSupply();
        uint256 balanceOLA = (token0 == olas) ? balance0 : balance1;
        uint256 balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved before deposit", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before deposit", balanceDAI);
        // uint256 amountToSwap = IToken(olas).balanceOf(address(this));

        path[0] = (token0 == olas) ? token0 : token1;
        path[1] = (token0 == olas) ? token1 : token0;

        // console.log("balance OLAS in this contract before swap {pseudo flash loan OLAS}:",IToken(olas).balanceOf(address(this)));
        IToken(olas).approve(swapRouter, LARGE_APPROVAL);
        amounts = IZRouter(swapRouter).swapExactTokensForTokens(IToken(olas).balanceOf(address(this)), 0, path, address(this));
        // console.log("balance OLAS in this contract after swap:",IToken(olas).balanceOf(address(this)));

        balance0 = IToken(token0).balanceOf(token);
        balance1 = IToken(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);

        (payout, , ) = IDepository(depository).deposit(bid, amountTo);

        // DAI approve
        IToken(path[1]).approve(swapRouter, LARGE_APPROVAL);
        // swap back
        path[0] = path[1];
        path[1] = olas;
        amounts = IZRouter(swapRouter).swapExactTokensForTokens(IToken(path[0]).balanceOf(address(this)), 0, path, address(this));
        // console.log("balance OLAS in this contract after swap:", IToken(olas).balanceOf(address(this)));

        balance0 = IToken(token0).balanceOf(token);
        balance1 = IToken(token1).balanceOf(token);
        // totalSupply = pair.totalSupply();
        balanceOLA = (token0 == olas) ? balance0 : balance1;
        balanceDAI = (token0 == olas) ? balance1 : balance0;
        // console.log("AttackDeposit ## OLAS reserved after swap", balanceOLA);
        // console.log("AttackDeposit ## DAI reserved before swap", balanceDAI);
    }

}