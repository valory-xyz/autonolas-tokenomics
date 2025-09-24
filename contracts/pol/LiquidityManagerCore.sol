// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IErrorsTokenomics} from "../interfaces/IErrorsTokenomics.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {TickMath} from "../../libraries/TickMath.sol";
import {LiquidityAmounts} from "../../libraries/LiquidityAmounts.sol";

interface IFactory {
    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

// Bridger Burner interface
interface IOlas {
    /// @dev (Bridges and) Burns OLAS tokens.
    /// @param amount OLAS token amount to burn.
    /// @param amount OLAS token amount to burn.
    function burn(uint256 amount) external;
}

interface IOracle {
    /// @dev Gets the current OLAS token price in 1e18 format.
    function getPrice() external view returns (uint256);

    /// @dev Validates price according to slippage.
    function validatePrice(uint256 slippage) external view returns (bool);

    /// @dev Updates the time-weighted average price.
    function updatePrice() external returns (bool);
}

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

interface IPositionManager {
    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @param tokenId The ID of the token that represents the position
    /// @return nonce The nonce for permits
    /// @return operator The address that is approved for spending
    /// @return token0 The address of the token0 for a specific pool
    /// @return token1 The address of the token1 for a specific pool
    /// @return fee The fee associated with the pool
    /// @return tickLower The lower end of the tick range for the position
    /// @return tickUpper The higher end of the tick range for the position
    /// @return liquidity The liquidity of the position
    /// @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
    /// @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
    /// @return tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation
    /// @return tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation
    function positions(uint256 tokenId)
    external
    view
    returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to achieve resulting liquidity
    /// @return amount1 The amount of token1 to achieve resulting liquidity
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external payable returns (uint256 amount0, uint256 amount1);

    /// @dev Transfers position.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transferFrom(address from, address to, uint256 positionId) external;
}

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver, IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);

    // LiquidityManager version number
    string public constant VERSION = "0.1.0";
    // LiquidityManager proxy address slot
    // keccak256("PROXY_LIQUIDITY_MANAGER") = "0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
    bytes32 public constant PROXY_LIQUIDITY_MANAGER = 0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd;
    // Max conversion value from v2 to v3 in bps
    uint256 public constant MAX_BPS = 10_000;
    // Seconds ago to look back for TWAP pool values
    uint32 public constant SECONDS_AGO = 1800;
    // Max allowed price deviation for TWAP pool values (10%) in 1e18 format
    uint256 public constant MAX_ALLOWED_DEVIATION = 1e17;
    // TODO Calculate steps - linear gas spending dependency
    uint8 public constant SCAN_STEPS = 5;

    // Owner address
    address public owner;

    // OLAS token address
    address public immutable olas;
    // Timelock token address
    address public immutable timelock;
    // Treasury contract address
    address public immutable treasury;
    // TODO Extract to L2 contracts only
    // Bridge to Burner address
    address public immutable bridge2Burner;
    // Uniswap V2 Router address
    address public immutable routerV2;
    // V2 pool related oracle address
    address public immutable oracleV2;
    // V3 position manager address
    address public immutable positionManagerV3;
    // V3 factory
    address public immutable factoryV3;

    // Max slippage for pool operations (in BPS, bound by 10_000)
    uint256 public maxSlippage;

    // Reentrancy lock
    uint256 internal _locked;

    // V3 position Ids
    mapping(address => uint256) public mapPoolAddressPositionIds;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _timelock Timelock or its representative address.
    /// @param _treasury Treasury address.
    /// @param _bridge2Burner Bridge to Burner address.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _routerV2 Uniswap V2 Router address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _maxSlippage Max slippage for operations.
    constructor(
        address _olas,
        address _timelock,
        address _treasury,
        address _bridge2Burner,
        address _oracleV2,
        address _routerV2,
        address _positionManagerV3,
        uint256 _maxSlippage
    ) {
        owner = msg.sender;

        // Check for zero addresses
        if (_olas == address(0) || _timelock == address(0) || _treasury == address(0) || _oracleV2 == address(0) ||
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
        timelock = _timelock;
        treasury = _treasury;
        bridge2Burner = _bridge2Burner;
        oracleV2 = _oracleV2;
        routerV2 = _routerV2;
        positionManagerV3 = _positionManagerV3;
        maxSlippage = _maxSlippage;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    function _burn(bytes memory bridgePayload) internal;

    function _manageUtilityAmounts(address token0, address token1) internal {
        // Get token balances
        uint256 amount0 = IToken(token0).balanceOf(address(this));
        uint256 amount1 = IToken(token1).balanceOf(address(this));

        // Check for OLAS token
        if (token0 == olas) {
            // TODO change to _burn() - then separate between L1 and L2?
            // Transfer to Burner
            IToken(olas).transfer(bridge2Burner, amount0);
            // Transfer to Timelock
            IToken(token1).transfer(timelock, amount1);
        } else {
            // Transfer to Burner
            IToken(olas).transfer(bridge2Burner, amount1);
            // Transfer to Timelock
            IToken(token0).transfer(timelock, amount0);
        }
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

    function _ticksFromPercent(int24 centerTick, uint16 halfWidthBps, int24 spacing)
        internal pure returns (int24 lo, int24 hi, uint160 sqrtA, uint160 sqrtB)
    {
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

    function convertToV3(address lpToken, uint24 feeTier, uint256 conversionRate) external returns (uint256 liquidity, uint256 positionId) {
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

        // Apply slippage protection
        // BPS --> %
        if (!IOracle(oracleV2).validatePrice(maxSlippage / 100)) {
            revert();
        }

        // TODO Check if need to calculate desired amounts
        // Remove liquidity
        (uint256 amount0, uint256 amount1) =
            IUniswapV2(routerV2).removeLiquidity(token0, token1, liquidity, 1, 1, address(this), block.timestamp);

        // V3
        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity
        if (conversionRate < MAX_BPS) {
            amount0 = amount0 * (MAX_BPS - conversionRate) / MAX_BPS;
            amount1 = amount1 * (MAX_BPS - conversionRate) / MAX_BPS;
        }

        // Check current pool prices
        (uint256 price, uint160 averageSqrtPriceX96, int24 averageTick) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Approve tokens for position manager
        IToken(token0).approve(positionManagerV3, amount0);
        IToken(token1).approve(positionManagerV3, amount1);

        positionId = mapPoolAddressPositionIds[pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            // Build percent band around TWAP center
            int24 tickSpacing = IFactory(factoryV3).feeAmountTickSpacing(feeTier);
            (int24 tickLower, int24 tickUpper, uint160 sqrtA, uint160 sqrtB) =
                _ticksFromPercent(averageTick, MAX_BPS / 2, tickSpacing);

            // Compute expected amounts for increase (TWAP) -> slippage guards
            uint128 liquidityMin = LiquidityAmounts.getLiquidityForAmounts(averageSqrtPriceX96, sqrtA, sqrtB, amount0, amount1);
            (uint256 amount0Min, uint256 amount1Min) =
                LiquidityAmounts.getAmountsForLiquidity(averageSqrtPriceX96, sqrtA, sqrtB, liquidityMin);
            uint256 amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
            uint256 amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

            // Add iquidity
            IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
                token0: token0,
                token1: token1,
                fee: feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp
            });

            (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

            mapPoolAddressPositionIds[pool] = positionId;
        } else {
            // Get current instant pool price
            (uint160 sqrtPriceX96, , uint16 observationIndex, , , , ) = IUniswapV3(pool).slot0();

            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManager(positionManagerV3).positions(positionId);

            // Compute expected amounts for increase (TWAP) -> slippage guards
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            uint128 liquidityMin = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
            (uint256 amount0Min, uint256 amount1Min) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidityMin);
            uint256 amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
            uint256 amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

            IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp
            });

            (liquidity, amount0, amount1) = IPositionManager(positionManagerV3).increaseLiquidity(params);
        }

        // Manage utility and dust
        _manageUtilityAmounts(token0, token1);

        // TODO event

        _locked = 1;
    }

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

        // TODO event
        // emit FeesCollected(msg.sender,
    }

    /// @dev Collects fees from LP position, burns OLAS tokens transfers another token to BBB.
    function collectFees(address token0, address token1, uint24 feeTier) external {
        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

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
        (uint256 price, uint160 averageSqrtPriceX96, int24 averageTick) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Collect fees
        _collectFees(token0, token1, positionId);

        _locked = 1;
    }

    // Build base asymmetric ticks from percent widths
    function _asymmetricTicks(int24 centerTick, uint16 lowerBps, uint16 upperBps, int24 spacing)
        internal pure returns (int24 lo, int24 hi)
    {
        // Approx convert bps → ticks
        int24 dDown = - int24(int256(lowerBps) * 1e4 / 9210);
        int24 dUp   = + int24(int256(upperBps) * 1e4 / 9210);
        int24 rawLo = centerTick + dDown;
        int24 rawHi = centerTick + dUp;

        lo = (rawLo / spacing) * spacing;
        if (rawLo < 0 && (rawLo % spacing != 0)) lo -= spacing;
        hi = (rawHi % spacing == 0) ? rawHi : (rawHi + (spacing - (rawHi % spacing)));
    }

    // Small neighborhood scan: try shifting lo/hi by ±k*spacing to minimize dust
    function _scanNeighborhood(uint256 b0, uint256 b1, int24 tickSpacing, uint160 sqrtP, int24 baseLo, int24 baseHi, uint8 steps)
        internal view returns (int24 bestLo, int24 bestHi)
    {
        uint256 bestDust = type(uint256).max;
        bestLo = baseLo; bestHi = baseHi;

        for (int i = -int(steps); i <= int(steps); i++) {
            for (int j = -int(steps); j <= int(steps); j++) {
                int24 lo = baseLo + int24(i) * tickSpacing;
                int24 hi = baseHi + int24(j) * tickSpacing;
                if (lo >= hi) continue;

                uint160 sqrtA = TickMath.getSqrtRatioAtTick(lo);
                uint160 sqrtB = TickMath.getSqrtRatioAtTick(hi);

                uint128 L0 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sqrtA, sqrtB, b0);
                uint128 L1 = LiquidityAmounts.getLiquidityForAmount1(sqrtP, sqrtA, sqrtB, b1);
                uint128 Lm = L0 < L1 ? L0 : L1;
                if (Lm == 0) continue;

                (uint256 need0, uint256 need1) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtA, sqrtB, Lm);
                uint256 dust = (b0 > need0 ? b0 - need0 : 0) + (b1 > need1 ? b1 - need1 : 0);

                if (dust < bestDust) { bestDust = dust; bestLo = lo; bestHi = hi; }
            }
        }
    }

    function changeRanges(address token0, address token1, uint24 feeTier, uint16 lowerBps, uint16 upperBps) external returns (uint256 positionId) {
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

        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        uint256 currentPositionId = mapPoolAddressPositionIds[pool];

        // Check for zero value
        if (currentPositionId == 0) {
            revert ZeroValue();
        }

        // TODO Check for different poolSettings, otherwise revert

        // Check current pool prices
        (uint256 price, uint160 averageSqrtPriceX96, int24 averageTick) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Build percent band around TWAP center
        int24 tickSpacing = IFactory(factoryV3).feeAmountTickSpacing(feeTier);
        (int24 tickLower, int24 tickUpper, uint160 sqrtA, uint160 sqrtB) =
            _ticksFromPercent(averageTick, MAX_BPS / 2, tickSpacing);

        // TODO
        // Read position & liquidity
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManager(positionManagerV3).positions(currentPositionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get current pool reserves and observation index
        (uint160 sqrtPriceX96, , uint16 observationIndex, , , , ) = IUniswapV3(pool).slot0();

        // Decrease + collect
        (uint256 amount0Min, uint256 amount1Min) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
        uint256 amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        uint256 amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        // TODO Slippage
        IPositionManager.DecreaseLiquidityParams memory decreaseParams = IPositionManager.DecreaseLiquidityParams({
            tokenId: currentPositionId,
            liquidity: liquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });

        // Decrease liquidity
        (uint256 amount0, uint256 amount1) = IPositionManager(positionManagerV3).decreaseLiquidity(decreaseParams);

        // Collect fees
        _collectFees(token0, token1, currentPositionId);

        // Build asymmetric band candidates around TWAP and scan neighborhood
        uint256 b0 = IToken(token0).balanceOf(address(this));
        uint256 b1 = IToken(token1).balanceOf(address(this));

        (int24 baseLo, int24 baseHi) = _asymmetricTicks(averageTick, lowerBps, upperBps, tickSpacing);
        (int24 bestLo, int24 bestHi) = _scanNeighborhood(b0, b1, tickSpacing, averageSqrtPriceX96, baseLo, baseHi, SCAN_STEPS);

        // Mint with best band
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(bestLo);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(bestHi);
        uint128 L0 = LiquidityAmounts.getLiquidityForAmount0(averageSqrtPriceX96, sqrtA, sqrtB, b0);
        uint128 L1 = LiquidityAmounts.getLiquidityForAmount1(averageSqrtPriceX96, sqrtA, sqrtB, b1);
        uint128 Lm = L0 < L1 ? L0 : L1;
        if (Lm == 0) return;

        (uint256 need0, uint256 need1) = LiquidityAmounts.getAmountsForLiquidity(averageSqrtPriceX96, sqrtA, sqrtB, Lm);
        uint256 min0 = need0 * (MAX_BPS - maxSlippage) / MAX_BPS;
        uint256 min1 = need1 * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Add iquidity
        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
            token0: token0,
            token1: token1,
            fee: feeTier,
            tickLower: bestLo,
            tickUpper: bestHi,
            amount0Desired: need0,
            amount1Desired: need1,
            amount0Min: min0,
            amount1Min: min1,
            recipient: address(this),
            deadline: block.timestamp
        });

        (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

        mapPoolAddressPositionIds[pool] = positionId;

        // Manage fees and dust
        _manageUtilityAmounts(token0, token1);

        // TODO Event

        _locked = 1;
    }

    function decreaseLiquidity(address token0, address token1, uint24 feeTier, uint256 bps, uint256 withdrawRate) external returns (uint256 positionId) {
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
        if (utilityRate > MAX_BPS) {
            revert Overflow(utilityRate, MAX_BPS);
        }

        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);

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
        (uint256 price, uint160 averageSqrtPriceX96, int24 averageTick) = getTwapFromOracle(pool);
        checkPoolPrices(pool, averageSqrtPriceX96);

        // Build percent band around TWAP center
        int24 tickSpacing = IFactory(factoryV3).feeAmountTickSpacing(feeTier);
        (int24 tickLower, int24 tickUpper, uint160 sqrtA, uint160 sqrtB) =
            _ticksFromPercent(averageTick, MAX_BPS / 2, tickSpacing);

        // TODO
        // Read position & liquidity
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManager(positionManagerV3).positions(positionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Calculate liquidity based on provided BPS
        liquidity = (liquidity * (MAX_BPS - bps)) / MAX_BPS;

        // Get current pool reserves and observation index
        (uint160 sqrtPriceX96, , uint16 observationIndex, , , , ) = IUniswapV3(pool).slot0();

        // Decrease + collect
        (uint256 amount0Min, uint256 amount1Min) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
        uint256 amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        uint256 amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        IPositionManager.DecreaseLiquidityParams memory decreaseParams = IPositionManager.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });

        // Decrease liquidity
        (uint256 amount0, uint256 amount1) = IPositionManager(positionManagerV3).decreaseLiquidity(decreaseParams);

        // Manage withdraw amounts
        if (withdrawRate > 0) {
            // Calculate utility amounts
            amount0 = amount0 * withdrawRate / MAX_BPS;
            amount1 = amount1 * withdrawRate / MAX_BPS;

            // Transfer amounts to timelock
            if (amount0 > 0) {
                IToken(token0).transfer(timelock, amount0);
            }
            if (amount1 > 0) {
                IToken(token1).transfer(timelock, amount1);
            }
        }

        // Collect fees
        _collectFees(token0, token1, positionId);

        // Manage fees and dust
        _manageUtilityAmounts(token0, token1);

        // TODO Event

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

        // TODO Event

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

        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get position Id
        positionId = mapPoolAddressPositionIds[pool];

        // Transfer position Id
        IPositionManager(positionManagerV3).transferFrom(address(this), to, positionId);

        mapPoolAddressPositionIds[pool] = 0;

        // TODO Event

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
}
