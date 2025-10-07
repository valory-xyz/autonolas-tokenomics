// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";

/// @dev Provided zero address.
error ZeroAddress();

interface IFactory {
    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IOracle {
    /// @dev Validates price according to slippage.
    function validatePrice(uint256 slippage) external view returns (bool);
}

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Burns tokens.
    /// @param amount Token amount to burn.
    /// @param amount Token amount to burn.
    function burn(uint256 amount) external;

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02 {
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

interface IUniswapV3 {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// tick The current tick of the pool, i.e. according to the last tick transition that was run.
    /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96) if the price is on a tick
    /// boundary.
    /// observationIndex The index of the last oracle observation that was written,
    /// observationCardinality The current maximum number of observations stored in the pool,
    /// observationCardinalityNext The next maximum number of observations, to be updated when the observation.
    /// feeProtocol The protocol fee for both tokens of the pool.
    /// Encoded as two 4 bit values, where the protocol fee of token1 is shifted 4 bits and the protocol fee of token0
    /// is the lower 4 bits. Used as the denominator of a fraction of the swap fee, e.g. 4 means 1/4th of the swap fee.
    /// unlocked Whether the pool is currently locked to reentrancy
    function slot0() external view
    returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality,
        uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params) external payable
    returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
}

/// @title Liquidity Manager ETH - Smart contract for OLAS core Liquidity Manager functionality on ETH mainnet
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerETH is LiquidityManagerCore {
    // Uniswap V2 Router address
    address public immutable routerV2;
    // V2 pool related oracle address
    address public immutable oracleV2;

    /// @dev LiquidityManagerETH constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _maxSlippage Max slippage for operations.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _routerV2 Uniswap V2 Router address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        uint16 _maxSlippage,
        address _oracleV2,
        address _routerV2
    ) LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality, _maxSlippage)
    {
        // Check for zero addresses
        if (_oracleV2 == address(0) || _routerV2 == address(0)) {
            revert ZeroAddress();
        }

        oracleV2 = _oracleV2;
        routerV2 = _routerV2;
    }

    /// @dev Burns OLAS.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal virtual override {
        IToken(olas).burn(amount);
    }

    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pair)
        internal virtual override returns (uint256[] memory amounts)
    {
        address lpToken = address(uint160(uint256(v2Pair)));

        // Get this contract liquidity
        uint256 liquidity = IToken(lpToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get V2 pair tokens - assume they are in lexicographical order as per Uniswap convention
        address[] memory tokensInPair = new address[](2);
        tokensInPair[0] = IUniswapV2Pair(lpToken).token0();
        tokensInPair[1] = IUniswapV2Pair(lpToken).token1();

        // Check tokens
        if (tokensInPair[0] != tokens[0] || tokensInPair[1] != tokens[1]) {
            revert();
        }

        // Apply slippage protection
        // BPS --> %
        if (!IOracle(oracleV2).validatePrice(maxSlippage / 100)) {
            revert();
        }

        // Approve V2 liquidity
        IToken(lpToken).approve(routerV2, liquidity);

        // Remove liquidity: note that at this point of time the price is validated with desired slippage,
        // and thus min out amounts can be set to 1
        amounts = new uint256[](2);
        (amounts[0], amounts[1]) = IUniswapV2Router02(routerV2).removeLiquidity(tokens[0], tokens[1], liquidity, 1, 1,
            address(this), block.timestamp);
    }

    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTier,
        uint160
    ) internal virtual override returns (uint256 positionId, uint128 liquidity, uint256[] memory)
    {
        // Add liquidity
        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
            token0: tokens[0],
            token1: tokens[1],
            fee: uint24(feeTier),
            tickLower: ticks[0],
            tickUpper: ticks[1],
            amount0Desired: amounts[0],
            amount1Desired: amounts[1],
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            recipient: address(this),
            deadline: block.timestamp
        });

        (positionId, liquidity, amounts[0], amounts[1]) = IUniswapV3(positionManagerV3).mint(params);

        return (positionId, liquidity, amounts);
    }

    function _feeAmountTickSpacing(int24 feeTier) internal view virtual override returns (int24 tickSpacing) {
        if (feeTier < 0) {
            revert();
        }
        tickSpacing = IFactory(factoryV3).feeAmountTickSpacing(uint24(feeTier));
    }

    function _getPriceAndObservationIndexFromSlot0(address pool)
        internal view virtual override returns (uint160 sqrtPriceX96, uint16 observationIndex)
    {
        // Get current pool reserves and observation index
        (sqrtPriceX96, , observationIndex, , , , ) = IUniswapV3(pool).slot0();
    }

    function _getV3Pool(address[] memory tokens, int24 feeTier)
        internal view virtual override returns (address)
    {
        if (feeTier < 0) {
            revert();
        }

        return IFactory(factoryV3).getPool(tokens[0], tokens[1], uint24(feeTier));
    }
}
