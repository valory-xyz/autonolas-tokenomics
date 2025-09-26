// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IErrorsTokenomics} from "../interfaces/IErrorsTokenomics.sol";
import {IPositionManagerV3} from "../interfaces/IPositionManagerV3.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";

interface IFactory {
    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

interface IOracle {
    /// @dev Gets the current OLAS token price in 1e18 format.
    function getPrice() external view returns (uint256);

    /// @dev Validates price according to slippage.
    function validatePrice(uint256 slippage) external view returns (bool);

    /// @dev Updates the time-weighted average price.
    function updatePrice() external returns (bool);
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

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver, IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event UtilityAmountsManaged(address indexed olas, address indexed token, uint256 olasAmount, uint256 tokenAmount);
    event PositionMinted(uint256 indexed positionId, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1);
    event FeesCollected(address indexed sender, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1);
    event RangesChanged(address indexed token0, address indexed token1, int24 tickLower, int24 tickUpper);
    event LiquidityDecreased(uint256 indexed positionId, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 olasWithdrawAmount);

    // LiquidityManager version number
    string public constant VERSION = "0.1.0";
    // LiquidityManager proxy address slot
    // keccak256("PROXY_LIQUIDITY_MANAGER") = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
    bytes32 public constant PROXY_LIQUIDITY_MANAGER = 0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd;
    // Max allowed price deviation for TWAP pool values (10%) in 1e18 format
    uint256 public constant MAX_ALLOWED_DEVIATION = 1e17;
    // Seconds ago to look back for TWAP pool values
    uint32 public constant SECONDS_AGO = 1800;
    // Max conversion value from v2 to v3 in bps
    uint16 public constant MAX_BPS = 10_000;
    // TODO Calculate steps - linear gas spending dependency
    int24 public constant SCAN_STEPS = 5;

    // OLAS token address
    address public immutable olas;
    // Treasury address (timelock or governing bridge mediator)
    address public immutable treasury;
    // Uniswap V2 Router address
    address public immutable routerV2;
    // V2 pool related oracle address
    address public immutable oracleV2;
    // V3 position manager address
    address public immutable positionManagerV3;
    // V3 factory
    address public immutable factoryV3;

    // Owner address
    address public owner;

    // Max slippage for pool operations (in BPS, bound by 10_000)
    uint16 public maxSlippage;

    // Reentrancy lock
    uint8 internal _locked;

    // V3 position Ids
    mapping(address => uint256) public mapPoolAddressPositionIds;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _routerV2 Uniswap V2 Router address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _maxSlippage Max slippage for operations.
    constructor(
        address _olas,
        address _treasury,
        address _oracleV2,
        address _routerV2,
        address _positionManagerV3,
        uint16 _maxSlippage
    ) {
        owner = msg.sender;

        // Check for zero addresses
        if (_olas == address(0) || _treasury == address(0) || _oracleV2 == address(0) ||
            _routerV2 == address(0) || _positionManagerV3 == address(0))
        {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_maxSlippage == 0) {
            revert ZeroValue();
        }
        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        olas = _olas;
        treasury = _treasury;
        oracleV2 = _oracleV2;
        routerV2 = _routerV2;
        positionManagerV3 = _positionManagerV3;
        maxSlippage = _maxSlippage;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    function _burn(uint256 amount) internal virtual;

    function _collectFees(address token0, address token1, uint256 positionId) internal {
        IUniswapV3.CollectParams memory params = IUniswapV3.CollectParams({
            tokenId: positionId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // Get corresponding token fees
        (uint256 amount0, uint256 amount1) = IUniswapV3(positionManagerV3).collect(params);
        // Check for zero amounts
        if (amount0 == 0 && amount1 == 0) {
            revert ZeroValue();
        }

        // Manage collected fees
        _manageUtilityAmounts(token0, token1);

        emit FeesCollected(msg.sender, token0, token1, amount0, amount1);
    }

    function _manageUtilityAmounts(address token0, address token1) internal {
        // Check for OLAS token
        if (token1 == olas) {
            token1 = token0;
        }

        // Get token balances
        uint256 olasAmount = IToken(olas).balanceOf(address(this));
        uint256 tokenAmount = IToken(token1).balanceOf(address(this));

        // Directly burns or Transfer OLAS to Burner contract
        if (olasAmount > 0) {
            _burn(olasAmount);
        }

        // Transfer to Treasury
        if (tokenAmount > 0) {
            IToken(token1).transfer(treasury, tokenAmount);
        }

        emit UtilityAmountsManaged(olas, token1, olasAmount, tokenAmount);
    }

    // Small neighborhood scan: try shifting lo/hi by ±k*spacing to minimize dust
    function _scanNeighborhood(uint256[] memory balances, int24 tickSpacing, uint160 sqrtP, int24[] memory baseLoHi)
    internal pure returns (int24[] memory bestLoHi)
    {
        uint256 bestDust = type(uint256).max;

        for (int24 i = - SCAN_STEPS; i <= SCAN_STEPS; ++i) {
            for (int24 j = - SCAN_STEPS; j <= SCAN_STEPS; ++j) {
                int24[] memory loHi = new int24[](2);
                loHi[0] = baseLoHi[0] + i * tickSpacing;
                loHi[1] = baseLoHi[1] + j * tickSpacing;
                if (loHi[0] >= loHi[1]) continue;

                uint160[] memory sqrtAB = new uint160[](2);
                sqrtAB[0] = TickMath.getSqrtRatioAtTick(loHi[0]);
                sqrtAB[1] = TickMath.getSqrtRatioAtTick(loHi[1]);

                uint128[] memory liquidity = new uint128[](2);
                liquidity[0] = LiquidityAmounts.getLiquidityForAmount0(sqrtAB[0], sqrtAB[1], balances[0]);
                liquidity[1] = LiquidityAmounts.getLiquidityForAmount1(sqrtAB[0], sqrtAB[1], balances[1]);
                liquidity[0] = liquidity[0] < liquidity[1] ? liquidity[0] : liquidity[1];
                if (liquidity[0] == 0) continue;

                uint256[] memory needs = new uint256[](2);
                (needs[0], needs[1]) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity[0]);
                uint256 dust = (balances[0] > needs[0] ? balances[0] - needs[0] : 0) + (balances[1] > needs[1] ? balances[1] - needs[1] : 0);

                if (dust < bestDust) {
                    bestDust = dust;
                    bestLoHi[0] = loHi[0];
                    bestLoHi[1] = loHi[1];
                }
            }
        }
    }

    function _ticksFromPercent(int24 centerTick, uint256 halfWidthBps, uint24 feeTier)
        internal view returns (int24 lo, int24 hi, uint160 sqrtA, uint160 sqrtB)
    {
        int24 spacing = IFactory(factoryV3).feeAmountTickSpacing(feeTier);

        // For simplicity approximate: deltaTick ≈ ln(1±w)/ln(1.0001)
        int24 dUp = int24(int256(halfWidthBps) * 1e4 / 9210);
        int24 dDown = -dUp;
        int24 rawLo = centerTick + dDown;
        int24 rawHi = centerTick + dUp;

        // Round down
        lo = (rawLo / spacing) * spacing;
        // Fix floor for negatives
        if (rawLo < 0 && (rawLo % spacing != 0)) {
            lo -= spacing;
        }

        hi = (rawHi % spacing == 0) ? rawHi : (rawHi + (spacing - (rawHi % spacing)));
        sqrtA = TickMath.getSqrtRatioAtTick(lo);
        sqrtB = TickMath.getSqrtRatioAtTick(hi);
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

    function _calculateFirstPositionParams(uint24 feeTier, address token0, address token1, uint256 amount0, uint256 amount1, int24 averageTick, uint160 averageSqrtPriceX96)
        internal view returns (IUniswapV3.MintParams memory params)
    {
        int24[] memory ticks = new int24[](2);
        uint160[] memory sqrtAB = new uint160[](2);
        // Build percent band around TWAP center
        (ticks[0], ticks[1], sqrtAB[0], sqrtAB[1]) =
            _ticksFromPercent(averageTick, MAX_BPS / 2, feeTier);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint128 liquidityMin = LiquidityAmounts.getLiquidityForAmounts(averageSqrtPriceX96, sqrtAB[0], sqrtAB[1], amount0, amount1);
        (uint256 amount0Min, uint256 amount1Min) =
            LiquidityAmounts.getAmountsForLiquidity(averageSqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidityMin);
        amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Add iquidity
        params = IUniswapV3.MintParams({
            token0: token0,
            token1: token1,
            fee: feeTier,
            tickLower: ticks[0],
            tickUpper: ticks[1],
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function _calculateIncreaseLiquidityParams(address pool, uint256 positionId, uint256 amount0, uint256 amount1)
        internal view returns (IPositionManagerV3.IncreaseLiquidityParams memory params)
    {
        // Get current instant pool price
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3(pool).slot0();

        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidityMin, , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        liquidityMin = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
        (uint256 amount0Min, uint256 amount1Min) =
                            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidityMin);
        amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        params = IPositionManagerV3.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });
    }

    function convertToV3(address lpToken, uint24 feeTier, uint16 conversionRate) external returns (uint256 liquidity, uint256 positionId) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check conversion rate
        if (conversionRate == 0) {
            revert ZeroValue();
        }
        if (conversionRate > MAX_BPS) {
            revert Overflow(conversionRate, MAX_BPS);
        }

        // Get this contract liquidity
        liquidity = IToken(lpToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get V2 pair tokens - assume they are in lexicographical order as per Uniswap convention
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();

        // TODO Shall we accept non-OLAS pairs?
        // Check for OLAS in pair
        if (token0 != olas && token1 != olas) {
            revert();
        }

        // Apply slippage protection
        // BPS --> %
        if (!IOracle(oracleV2).validatePrice(maxSlippage / 100)) {
            revert();
        }

        // Remove liquidity: note that at this point of time the price is validated with desired slippage,
        // and thus min out amounts can be set to 1
        (uint256 amount0, uint256 amount1) =
            IUniswapV2Router02(routerV2).removeLiquidity(token0, token1, liquidity, 1, 1, address(this), block.timestamp);

        // V3
        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on conversion rate
        if (conversionRate < MAX_BPS) {
            amount0 = (amount0 * conversionRate) / MAX_BPS;
            amount1 = (amount1 * conversionRate) / MAX_BPS;
        }

        // Check current pool prices
        (, uint160 averageSqrtPriceX96, int24 averageTick) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Approve tokens for position manager
        IToken(token0).approve(positionManagerV3, amount0);
        IToken(token1).approve(positionManagerV3, amount1);

        positionId = mapPoolAddressPositionIds[pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            IUniswapV3.MintParams memory params =
                _calculateFirstPositionParams(feeTier, token0, token1, amount0, amount1, averageTick, averageSqrtPriceX96);

            (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

            mapPoolAddressPositionIds[pool] = positionId;
        } else {
            IPositionManagerV3.IncreaseLiquidityParams memory params =
                _calculateIncreaseLiquidityParams(pool, positionId, amount0, amount1);

            (liquidity, amount0, amount1) = IPositionManagerV3(positionManagerV3).increaseLiquidity(params);
        }

        // Manage utility and dust
        _manageUtilityAmounts(token0, token1);

        emit PositionMinted(positionId, token0, token1, amount0, amount1);

        _locked = 1;
    }

    /// @dev Collects fees from LP position, burns OLAS tokens transfers another token to BBB.
    function collectFees(address token0, address token1, uint24 feeTier) external {
        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        uint256 positionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        (, uint160 averageSqrtPriceX96,) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Collect fees
        _collectFees(token0, token1, positionId);

        _locked = 1;
    }

    function _calculateDecreaseLiquidityParams(address pool, uint256 positionId, uint16 bps)
        internal view returns (IPositionManagerV3.DecreaseLiquidityParams memory params)
    {
        // Read position & liquidity
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Calculate liquidity based on provided BPS, if any
        if (bps > 0) {
            liquidity = (liquidity * (MAX_BPS - bps)) / MAX_BPS;
        }

        // Get current pool reserves and observation index
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3(pool).slot0();

        // Decrease liquidity
        (uint256 amount0Min, uint256 amount1Min) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
        amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        params = IPositionManagerV3.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });
    }

    function _calculateLiquidity(int24[] memory bestLoHi, uint256[] memory balances)
        internal pure returns (uint160[] memory sqrtAB, uint128 liquidity)
    {
        // Mint with best band
        sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(bestLoHi[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(bestLoHi[1]);
        liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtAB[0], sqrtAB[1], balances[0]);
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtAB[0], sqrtAB[1], balances[1]);
        liquidity = liquidity < liquidity1 ? liquidity : liquidity1;
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }
    }

    function _calculateRepositionParams(address token0, address token1, uint24 feeTier, int24 baseLo, int24 baseHi, uint160 averageSqrtPriceX96)
        internal returns (IUniswapV3.MintParams memory params)
    {
        // Get tick spacing
        int24 tickSpacing = IFactory(factoryV3).feeAmountTickSpacing(feeTier);

        // Build asymmetric band candidates around TWAP and scan neighborhood
        uint256[] memory balances = new uint256[](2);
        balances[0] = IToken(token0).balanceOf(address(this));
        balances[1] = IToken(token1).balanceOf(address(this));

        int24[] memory bestLoHi = new int24[](2);
        bestLoHi[0] = baseLo;
        bestLoHi[1] = baseHi;
        bestLoHi = _scanNeighborhood(balances, tickSpacing, averageSqrtPriceX96, bestLoHi);

        // TODO Is this already calculated above?
        (uint160[] memory sqrtAB, uint128 liquidity) = _calculateLiquidity(bestLoHi, balances);

        uint256[] memory needs = new uint256[](2);
        uint256[] memory mins = new uint256[](2);
        (needs[0], needs[1]) = LiquidityAmounts.getAmountsForLiquidity(averageSqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);
        mins[0] = needs[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        mins[1] = needs[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Add liquidity
        params = IUniswapV3.MintParams({
            token0: token0,
            token1: token1,
            fee: feeTier,
            tickLower: bestLoHi[0],
            tickUpper: bestLoHi[1],
            amount0Desired: needs[0],
            amount1Desired: needs[1],
            amount0Min: mins[0],
            amount1Min: mins[1],
            recipient: address(this),
            deadline: block.timestamp
        });

        emit RangesChanged(token0, token1, bestLoHi[0], bestLoHi[1]);
    }

    function changeRanges(address token0, address token1, uint24 feeTier, int24 baseLo, int24 baseHi) external returns (uint256 positionId) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        uint256 currentPositionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (currentPositionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        (, uint160 averageSqrtPriceX96,) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // TODO Check for different ticks?
//        if (baseLo == tickLower && baseHi == tickUpper) {
//            revert();
//        }

        IPositionManagerV3.DecreaseLiquidityParams memory decreaseParams =
            _calculateDecreaseLiquidityParams(pool, currentPositionId, 0);

        // Decrease liquidity
        (uint256 amount0, uint256 amount1) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(decreaseParams);

        // Collect fees
        _collectFees(token0, token1, currentPositionId);

        (IUniswapV3.MintParams memory params) =
            _calculateRepositionParams(token0, token1, feeTier, baseLo, baseHi, averageSqrtPriceX96);

        uint128 liquidity;
        (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

        mapPoolAddressPositionIds[pool] = positionId;

        // Manage fees and dust
        _manageUtilityAmounts(token0, token1);

        emit PositionMinted(positionId, token0, token1, amount0, amount1);

        _locked = 1;
    }

    function decreaseLiquidity(address token0, address token1, uint24 feeTier, uint16 bps, uint16 olasWithdrawRate) external returns (uint256 positionId) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check bps and utility rate
        if (bps == 0) {
            revert ZeroValue();
        }
        if (bps > MAX_BPS) {
            revert Overflow(bps, MAX_BPS);
        }
        if (olasWithdrawRate > MAX_BPS) {
            revert Overflow(olasWithdrawRate, MAX_BPS);
        }

        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        positionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        (, uint160 averageSqrtPriceX96, ) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        IPositionManagerV3.DecreaseLiquidityParams memory params = _calculateDecreaseLiquidityParams(pool, positionId, bps);

        // Decrease liquidity
        (uint256 amount0, uint256 amount1) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(params);

        // Check for OLAS withdraw amount
        uint256 olasWithdrawAmount;
        if (olasWithdrawRate > 0) {
            // Calculate OLAS withdraw amount
            olasWithdrawAmount = (token0 == olas) ? amount0 : amount1;
            olasWithdrawAmount = (olasWithdrawAmount * olasWithdrawRate) / MAX_BPS;

            // Transfer amounts to treasury
            if (olasWithdrawAmount > 0) {
                IToken(olas).transfer(treasury, olasWithdrawAmount);
            }
        }

        // Collect fees
        _collectFees(token0, token1, positionId);

        // Manage fees and dust
        _manageUtilityAmounts(token0, token1);

        emit LiquidityDecreased(positionId, token0, token1, amount0, amount1, olasWithdrawAmount);

        _locked = 1;
    }

    /// @dev Transfers token to a specified address.
    /// @param token Token address.
    /// @param to Account address to transfer to.
    /// @param amount Token amount.
    function transferToken(address token, address to, uint256 amount) external {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get token balance
        uint256 balance = IToken(token).balanceOf(address(this));
        if (amount > balance) {
            revert Overflow(amount, balance);
        }

        // Transfer token
        SafeTransferLib.safeTransfer(token, to, amount);

        // TODO Event?

        _locked = 1;
    }

    /// @dev Transfers position Id to a specified address.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transferPositionId(address token0, address token1, uint24 feeTier, address to) external returns (uint256 positionId) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        positionId = mapPoolAddressPositionIds[pool];

        // Transfer position Id
        IPositionManagerV3(positionManagerV3).transferFrom(address(this), to, positionId);

        mapPoolAddressPositionIds[pool] = 0;

        // TODO Event?

        _locked = 1;
    }

    /// @dev Gets TWAP price via the built-in Uniswap V3 oracle.
    /// @param pool Pool address.
    /// @return price Calculated price.
    function getTwapFromOracle(address pool) public view returns (uint256 price, uint160 averageSqrtPriceX96, int24 averageTick) {
        // Query the pool for the current and historical tick
        uint32[] memory secondsAgos = new uint32[](2);
        // Start of the period
        secondsAgos[0] = SECONDS_AGO;

        // Fetch the tick cumulative values from the pool
        (int56[] memory tickCumulatives, ) = IUniswapV3(pool).observe(secondsAgos);

        // Calculate the average tick over the time period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        averageTick = int24(tickCumulativeDelta / int56(int32(SECONDS_AGO)));

        // Convert the average tick to sqrtPriceX96
        averageSqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);

        // Calculate the price using the sqrtPriceX96
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        price = FixedPointMathLib.mulDivDown(uint256(averageSqrtPriceX96), uint256(averageSqrtPriceX96), (1 << 64));
    }
    
    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @param pool Pool address.
    /// @param twapPrice TWAP price.
    function checkPoolPrices(address pool, uint256 twapPrice) public view {
        // Get current pool reserves and observation index
        (uint160 sqrtPriceX96, , uint16 observationIndex, , , , ) = IUniswapV3(pool).slot0();

        // Check if the pool has sufficient observation history
        (uint32 oldestTimestamp, , , ) = IUniswapV3(pool).observations(observationIndex);
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return;
        }

        // Get instant price
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        uint256 instantPrice = FixedPointMathLib.mulDivDown(uint256(sqrtPriceX96), uint256(sqrtPriceX96), (1 << 64));

        uint256 deviation;
        if (twapPrice > 0) {
            deviation = (instantPrice > twapPrice) ?
                FixedPointMathLib.mulDivDown((instantPrice - twapPrice), 1e18, twapPrice) :
                FixedPointMathLib.mulDivDown((twapPrice - instantPrice), 1e18, twapPrice);
        }

        require(deviation <= MAX_ALLOWED_DEVIATION, "Price deviation too high");
    }

    // Build base asymmetric ticks from percent widths
    function asymmetricTicks(int24 centerTick, uint256 lowerBps, uint256 upperBps, int24 spacing)
        external pure returns (int24 lo, int24 hi)
    {
        // Approx convert bps → ticks
        int24 dDown = - int24(int256(lowerBps) * 1e4 / 9210);
        int24 dUp = int24(int256(upperBps) * 1e4 / 9210);
        int24 rawLo = centerTick + dDown;
        int24 rawHi = centerTick + dUp;

        lo = (rawLo / spacing) * spacing;
        if (rawLo < 0 && (rawLo % spacing != 0)) lo -= spacing;
        hi = (rawHi % spacing == 0) ? rawHi : (rawHi + (spacing - (rawHi % spacing)));
    }
}
