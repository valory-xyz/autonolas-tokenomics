// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/ITokenomics.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IUniswapV2Pair.sol";

import "hardhat/console.sol";

interface IWETH {
    function deposit() external payable;
    function balanceOf(address) external returns (uint256);
    function transfer(address dst, uint wad) external returns (bool);
}

/// @title FlashLoanAttacker - Smart contract to simulate the flash loan attack to get instant top-ups
contract FlashLoanAttacker {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;

    constructor() {}

    /// @dev Simulate a flash loan attack via donation and checkpoint.
    /// @param tokenomics Tokenomics address.
    /// @param treasury Treasury address.
    /// @param serviceId Service Id.
    /// @param success True if the attack is successful.
    function flashLoanAttackTokenomics(address tokenomics, address treasury, uint256 serviceId)
        external payable returns (bool success)
    {
        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = serviceId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = msg.value;

        // Donate to services
        ITreasury(treasury).depositServiceDonationsETH{value: msg.value}(serviceIds, amounts);

        // Call the checkpoint
        ITokenomics(tokenomics).checkpoint();

        success = true;
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = (amountA * reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function flashLoanAttackETHDepository(address pair) external payable returns (bool success)
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        uint256 price0 = IUniswapV2Pair(pair).price0CumulativeLast();
        uint256 price1 = IUniswapV2Pair(pair).price1CumulativeLast();
        console.log("reserve0 before",reserve0);
        console.log("reserve1 before",reserve1);
        console.log("blockTimestampLast before",blockTimestampLast);
        console.log("price0 before",price0);
        console.log("price1 before",price1);
        uint256 amountOut = getAmountOut(msg.value, reserve1, reserve0);

        IWETH(WETH).deposit{value:msg.value}();

        IWETH(WETH).transfer(pair, msg.value);

        // let hack system
        // amountOut += 10000; Revert reason: UniswapV2: K
        uint256 balance = IWETH(OLAS).balanceOf(address(this));
        console.log("balance OLAS",balance);
        IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
        balance = IWETH(OLAS).balanceOf(address(this));
        console.log("balance OLAS",balance);

        (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        price0 = IUniswapV2Pair(pair).price0CumulativeLast();
        price1 = IUniswapV2Pair(pair).price1CumulativeLast();
        console.log("reserve0 after",reserve0);
        console.log("reserve1 after",reserve1);
        console.log("blockTimestampLast after",blockTimestampLast);
        console.log("price0 after",price0);
        console.log("price1 after",price1);
        success = true;
    }

    function flashLoanAttackOLASDepository(address pair) external returns (bool success)
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        uint256 price0 = IUniswapV2Pair(pair).price0CumulativeLast();
        uint256 price1 = IUniswapV2Pair(pair).price1CumulativeLast();
        console.log("reserve0 before",reserve0);
        console.log("reserve1 before",reserve1);
        console.log("blockTimestampLast before",blockTimestampLast);
        console.log("price0 before",price0);
        console.log("price1 before",price1);
        // Assume we have a 1 million OLAS balance
        uint256 amountOut = getAmountOut(1_000_000 ether, reserve0, reserve1);

        IWETH(WETH).transfer(pair, 1_000_000 ether);

        // let hack system
        // amountOut += 10000; Revert reason: UniswapV2: K
        uint256 balance = IWETH(OLAS).balanceOf(address(this));
        console.log("balance OLAS",balance);
        IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
        balance = IWETH(OLAS).balanceOf(address(this));
        console.log("balance OLAS",balance);

        (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        price0 = IUniswapV2Pair(pair).price0CumulativeLast();
        price1 = IUniswapV2Pair(pair).price1CumulativeLast();
        console.log("reserve0 after",reserve0);
        console.log("reserve1 after",reserve1);
        console.log("blockTimestampLast after",blockTimestampLast);
        console.log("price0 after",price0);
        console.log("price1 after",price1);
        success = true;
    }
}