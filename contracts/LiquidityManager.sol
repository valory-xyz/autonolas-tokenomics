// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IErrorsTokenomics} from "./interfaces/IErrorsTokenomics.sol";
import {IToken} from "./interfaces/IToken.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

interface IUniswapV2 {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

/// @title Liquidity Manager - Smart contract for OLAS Liquidity Manager
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManager is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);

    // LiquidityManager version number
    string public constant VERSION = "0.1.0";
    // LiquidityManager proxy address slot
    // keccak256("PROXY_LIQUIDITY_MANAGER") = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
    bytes32 public constant PROXY_LIQUIDITY_MANAGER = 0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd;
    
    // Owner address
    address public owner;

    // OLAS token address
    address public immutable olas;
    // Treasury contract address
    address public immutable treasury;
    // Uniswap V2 Router address
    address public immutable routerV2;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _routerV2 Uniswap V2 Router address.
    constructor(address _olas, address _treasury, address _routerV2)
    {
        owner = msg.sender;

        // Check for zero addresses
        if (_olas == address(0) || _treasury == address(0) || _routerV2 == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        treasury = _treasury;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes liquidity manager implementation contract address.
    /// @notice Make sure the implementation contract has a function to change the implementation.
    /// @param implementation LiquidityManager implementation contract address.
    function changeImplementation(address implementation) external {
        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (implementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the implementation address under the designated storage slot
        assembly {
            sstore(PROXY_LIQUIDITY_MANAGER, implementation)
        }
        emit ImplementationUpdated(implementation);
    }

    function convertToV3(address lpToken, uint256 conversionRate) external {
        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get this contract liquidity
        uint256 liquidity = IToken(lpToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();

        // TODO Slippage
        // Remove liquidity
        (uint256 amountA, uint256 amountB) =
            IUniswapV2(routerV2).removeLiquidity(token0, token1, liquidity, 1, 1, address(this), block.timestamp);

        // V3
    }
}
