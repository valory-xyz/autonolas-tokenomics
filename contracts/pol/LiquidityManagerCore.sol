// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IErrorsTokenomics} from "../interfaces/IErrorsTokenomics.sol";
import {IPositionManagerV3} from "../interfaces/IPositionManagerV3.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";

interface INeighborhoodScanner {
    function scanNeighborhood(
        int24 tickSpacing,
        uint160 sqrtP,
        int24[] memory loHiCandidates,
        uint256[] memory amounts
    )
    external
    pure
    returns (
        int24[] memory loHiBest,
        uint128 Lbest,
        uint256[] memory used
    );
}

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver, IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event UtilityAmountsManaged(address indexed olas, address indexed token, uint256 olasAmount, uint256 tokenAmount);
    event PositionMinted(uint256 indexed positionId, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidiy);
    event FeesCollected(address indexed sender, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1);
    event TicksSet(address indexed token0, address indexed token1, int24 feeTierOrTickSpacing, int24 tickLower, int24 tickUpper);
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
    // // Max bps value
    uint16 public constant MAX_BPS = 10_000;
    // The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    // The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;
    // Safety steps
    int24 internal constant SAFETY_STEPS = 2;
    // Steps near to tick boundaries
    int24 internal constant NEAR_STEPS = SAFETY_STEPS;
    // 2^96
    uint160 public constant Q96 = 0x1000000000000000000000000;

    // OLAS token address
    address public immutable olas;
    // Treasury address (timelock or governing bridge mediator)
    address public immutable treasury;
    // V3 position manager address
    address public immutable positionManagerV3;
    // V3 factory
    address public immutable factoryV3;
    // Neighborhood ticks scanner
    address public immutable neighborhoodScanner;
    // Observations cardinality
    uint16 public immutable observationCardinality;

    // Owner address
    address public owner;

    // Max slippage for pool operations (in BPS, bound by 10_000)
    uint16 public maxSlippage;

    // Reentrancy lock
    uint8 internal _locked;

    // V3 position Ids
    mapping(address => uint256) public mapPoolAddressPositionIds;

    /// @dev LiquidityManagerCore constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _maxSlippage Max slippage for operations.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        uint16 _maxSlippage
    ) {
        owner = msg.sender;

        // Check for zero addresses
        if (_olas == address(0) || _treasury == address(0) || _positionManagerV3 == address(0) ||
            _neighborhoodScanner == address(0))
        {
            revert ZeroAddress();
        }

        // Check for zero values
        if (_maxSlippage == 0 || _observationCardinality == 0) {
            revert ZeroValue();
        }
        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        olas = _olas;
        treasury = _treasury;
        positionManagerV3 = _positionManagerV3;
        neighborhoodScanner = _neighborhoodScanner;
        observationCardinality = _observationCardinality;
        maxSlippage = _maxSlippage;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    function _burn(uint256 amount) internal virtual;

    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsOut);

    function _removeLiquidityV2(bytes32 v2Pool) internal virtual returns (address[] memory tokens, uint256[] memory amounts);

    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing) internal view virtual returns (int24 tickSpacing);

    function _getPriceAndObservationIndexFromSlot0(address pool) internal view virtual returns (uint160 sqrtPriceX96, uint16 observationIndex);

    function _getV3Pool(address token0, address token1, int24 feeTierOrTickSpacing) internal view virtual returns (address v3Pool);

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

    // sqrt(num/den) in Q96: sqrt((num<<192)/den), returns already scaled in Q96
    function _sqrtRatioX96(uint256 num, uint256 den) private pure returns (uint160) {
        uint256 x192 = (num << 192) / den;
        return uint160(FixedPointMathLib.sqrt(x192));
    }

    function _floorToSpacing(int24 t, int24 spacing) private pure returns (int24) {
        int24 q = t / spacing;
        if (t < 0 && (t % spacing != 0)) q -= 1;
        return q * spacing;
    }

    function _ceilToSpacing(int24 t, int24 spacing) private pure returns (int24) {
        int24 q = t / spacing;
        if (t > 0 && (t % spacing != 0)) q += 1;
        if (t < 0 && (t % spacing != 0)) q += 1; // proper ceil for negatives
        return q * spacing;
    }

    // check if intermediate = floor(sqrtA * sqrtB / Q96) is non-zero
    function _hasNonZeroIntermediate(int24 lo, int24 hi) private pure returns (bool) {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(lo);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(hi);
        uint256 intermediate = mulDiv(uint256(sqrtA), uint256(sqrtB), Q96);
        return (intermediate > 0);
    }

    // ---------- binary search to raise hi ----------
    // Finds minimal hi ∈ [hi0, hiMax], multiple of spacing, such that intermediate > 0.
    // If not found, returns hiMax as "best possible".
    function _bsearchRaiseHi(
        int24 lo,
        int24 hi0,
        int24 hiMax,
        int24 spacing
    ) private pure returns (int24) {
        hi0  = _ceilToSpacing(hi0, spacing);
        hiMax = _floorToSpacing(hiMax, spacing);
        if (hi0 > hiMax) hi0 = hiMax;

        int24 L = hi0;
        int24 R = hiMax;
        int24 ans = hiMax;

        // Binary search while L <= R
        for (uint256 i = 0; i < 100; ++i) {
            int24 mid = _floorToSpacing( (L + R) / 2, spacing );
            if (mid < L) mid = L;

            if (_hasNonZeroIntermediate(lo, mid)) {
                ans = mid;
                R = mid - spacing;         // search for smaller hi
            } else {
                L = mid + spacing;         // need to raise hi further
            }

            // Break condition: L > R
            if (L > R) break;
        }
        return ans;
    }

    // ---------- binary search to raise lo ----------
    // Finds minimal lo ∈ [loMin, hi - spacing], multiple of spacing, such that intermediate > 0 (with fixed hi).
    // If not found, returns hi - spacing (maximum possible raise of lo).
    function _bsearchRaiseLo(
        int24 loMin,
        int24 hi,
        int24 spacing
    ) private pure returns (int24) {
        loMin = _ceilToSpacing(loMin, spacing);
        int24 loMax = _floorToSpacing(hi - spacing, spacing);
        if (loMin > loMax) loMin = loMax;

        int24 L = loMin;
        int24 R = loMax;
        int24 ans = loMax;

        while (L <= R) {
            int24 mid = _ceilToSpacing( (L + R) / 2, spacing );
            if (mid > loMax) mid = loMax;

            if (_hasNonZeroIntermediate(mid, hi)) {
                ans = mid;
                R = mid - spacing;   // try smaller lo
            } else {
                L = mid + spacing;   // need to raise lo further
            }
        }
        return ans;
    }

    /// @notice Asymmetric ticks from bps around centerTick with WidenUp mode + binary search.
    /// Ensures non-zero intermediate for amount0 formula without linear loops.
    function _asymmetricTicksFromBpsWidenUp(
        uint160 centerSqrtPriceX96,
        uint160[] memory sqrtLowerUpperX96,
        int24 feeTierOrTickSpacing,
        uint256[] memory balances,
        bool scan
    ) internal view returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired) {
        // Get tick spacing
        int24 tickSpacing = _feeAmountTickSpacing(feeTierOrTickSpacing);
        // Check for zero value
        if (tickSpacing == 0) {
            revert ZeroValue();
        }

        // 4) clamp to MIN/MAX sqrt
        if (sqrtLowerUpperX96[0] < TickMath.MIN_SQRT_RATIO) {
            sqrtLowerUpperX96[0] = TickMath.MIN_SQRT_RATIO;
        }
        if (sqrtLowerUpperX96[1] > TickMath.MAX_SQRT_RATIO) {
            sqrtLowerUpperX96[1] = TickMath.MAX_SQRT_RATIO;
        }

        // 5) raw ticks
        loHi = new int24[](2);
        loHi[0] = TickMath.getTickAtSqrtRatio(sqrtLowerUpperX96[0]);
        loHi[1] = TickMath.getTickAtSqrtRatio(sqrtLowerUpperX96[1]);

        // 6) snap to spacing + safety margins
        int24 minSp = _ceilToSpacing(MIN_TICK, tickSpacing);
        int24 maxSp = _floorToSpacing(MAX_TICK, tickSpacing);
        int24 minSafe = minSp + SAFETY_STEPS * tickSpacing;
        int24 maxSafe = maxSp - SAFETY_STEPS * tickSpacing;

        loHi[0] = _floorToSpacing(loHi[0], tickSpacing);
        loHi[1] = _ceilToSpacing(loHi[1], tickSpacing);

        if (loHi[0] < minSafe) loHi[0] = minSafe;
        if (loHi[1] > maxSafe) loHi[1] = maxSafe;

        // 7) ensure non-empty interval
        if (loHi[0] >= loHi[1]) {
            loHi[0] = minSafe;
            loHi[1] = _ceilToSpacing(loHi[0] + tickSpacing, tickSpacing);
            if (loHi[1] > maxSafe) loHi[1] = maxSafe;
            require(loHi[0] < loHi[1], "EMPTY_RANGE");
        }

        // if already non-zero, return
        if (_hasNonZeroIntermediate(loHi[0], loHi[1])) {
            if (scan) {
                (loHi, liquidity, amountsDesired) = INeighborhoodScanner(neighborhoodScanner).scanNeighborhood(tickSpacing, centerSqrtPriceX96,
                    loHi, balances);
            }
            amountsDesired = balances;
            return (loHi, liquidity, amountsDesired);
        }

        // 8) choose widening side based on closeness to global boundaries
        bool nearMin = (loHi[0] - minSp) <= NEAR_STEPS * tickSpacing;
        bool nearMax = (maxSp - loHi[1]) <= NEAR_STEPS * tickSpacing;

        if (nearMin && !nearMax) {
            // lower near MIN → raise loHi[1] (widen upwards)
            loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            }
        } else if (nearMax && !nearMin) {
            // upper near MAX → raise loHi[0]
            loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            }
        } else {
            // neither or both near boundaries: first try raising loHi[1]
            loHi[1] = _bsearchRaiseHi(loHi[0], loHi[1], maxSafe, tickSpacing);
            if (!_hasNonZeroIntermediate(loHi[0], loHi[1])) {
                loHi[0] = _bsearchRaiseLo(minSafe, loHi[1], tickSpacing);
            }
        }

        require(loHi[0] >= minSafe && loHi[1] <= maxSafe && loHi[0] < loHi[1], "RANGE_BOUNDS");
        require(_hasNonZeroIntermediate(loHi[0], loHi[1]), "AMOUNT0_ZERO_LIQ");
    }

    function _mint(
        address[] memory tokens,
        uint256[] memory amounts,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96,
        uint160[] memory sqrtAB,
        bool scan,
        int24[] memory tickShifts
    )
        internal returns (uint256 positionId)
    {
        // Build percent band around TWAP center
        (int24[] memory ticks, uint128 liquidity, uint256[] memory amountsDesired) =
            _asymmetricTicksFromBpsWidenUp(centerSqrtPriceX96, sqrtAB, feeTierOrTickSpacing, amounts, scan);

        uint256[] memory amountsMin = new uint256[](2);
        if (!scan) {
            ticks[0] += tickShifts[0];
            ticks[1] += tickShifts[1];
            sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
            sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);

            // Compute expected amounts for increase (TWAP) -> slippage guards
            liquidity = LiquidityAmounts.getLiquidityForAmounts(centerSqrtPriceX96, sqrtAB[0], sqrtAB[1], amounts[0], amounts[1]);
            // Check for zero value
            if (liquidity == 0) {
                revert ZeroValue();
            }

            (amountsDesired[0], amountsDesired[1]) =
                LiquidityAmounts.getAmountsForLiquidity(centerSqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);
        }
        amountsMin[0] = amountsDesired[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        amountsMin[1] = amountsDesired[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        (positionId, liquidity, amounts) = _mintV3(tokens, amountsDesired, amountsMin, ticks, feeTierOrTickSpacing, centerSqrtPriceX96);

        emit TicksSet(tokens[0], tokens[1], feeTierOrTickSpacing, ticks[0], ticks[1]);
        emit PositionMinted(positionId, tokens[0], tokens[1], amounts[0], amounts[1], liquidity);
    }

    function _calculateFirstPositionParams(
        int24 feeTierOrTickSpacing,
        address[] memory tokens,
        uint256[] memory amounts,
        uint160 centerSqrtPriceX96,
        uint32[] memory lowerHigherBps,
        bool scan,
        int24[] memory tickShifts
    )
        internal returns (uint256 positionId)
    {
        //uint32 lowerBps,   // down from center, bps (100 = -1.00%)
        //uint32 upperBps,   // up from center, bps (100 = +1.00%)
        require(lowerHigherBps[0] <= MAX_BPS && lowerHigherBps[1] <= 1_000_000, "BPS_OOB");

        // TODO % between TICK_MIN and TICK_MAX: min(bound by MIN-MAX(center tick ± TICK_MIN/MAX)) - and apply input % shift
        // 2) factors sqrt((10000 ± bps)/10000) in Q96
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = _sqrtRatioX96(MAX_BPS - lowerHigherBps[0], MAX_BPS);
        sqrtAB[1] = _sqrtRatioX96(MAX_BPS + lowerHigherBps[1], MAX_BPS);

        // 3) target sqrt-prices
        sqrtAB[0] = uint160(mulDiv(uint256(centerSqrtPriceX96), uint256(sqrtAB[0]), Q96));
        sqrtAB[1] = uint160(mulDiv(uint256(centerSqrtPriceX96), uint256(sqrtAB[1]), Q96));

        // Calculate and mint new position
        return _mint(tokens, amounts, feeTierOrTickSpacing, centerSqrtPriceX96, sqrtAB, scan, tickShifts);
    }

    function _calculateIncreaseLiquidityParams(address pool, uint256 positionId, uint256 amount0, uint256 amount1)
        internal view returns (IPositionManagerV3.IncreaseLiquidityParams memory params)
    {
        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

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

    function convertToV3(bytes32 v2Pool, int24 feeTierOrTickSpacing, uint16 conversionRate, uint32[] memory lowerHigherBps, bool scan, int24[] memory tickShifts)
        external returns (uint256 positionId, uint256 liquidity)
    {
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

        //if (v2Pool == 0) {

        //} else {
            // Remove liquidity from V2 pool
            (address[] memory tokens, uint256[] memory amounts) = _removeLiquidityV2(v2Pool);
        //}

        // Get V3 pool
        address v3Pool = _getV3Pool(tokens[0], tokens[1], feeTierOrTickSpacing);

        // Check for zero address
        if (v3Pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on conversion rate
        if (conversionRate < MAX_BPS) {
            amounts[0] = (amounts[0] * conversionRate) / MAX_BPS;
            amounts[1] = (amounts[1] * conversionRate) / MAX_BPS;
        }

        // Check current pool prices
        uint160 centerSqrtPriceX96 = checkPoolAndGetCenterPrice(v3Pool);

        // Approve tokens for position manager
        IToken(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken(tokens[1]).approve(positionManagerV3, amounts[1]);

        positionId = mapPoolAddressPositionIds[v3Pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            positionId = _calculateFirstPositionParams(feeTierOrTickSpacing, tokens, amounts, centerSqrtPriceX96,
                lowerHigherBps, scan, tickShifts);

            mapPoolAddressPositionIds[v3Pool] = positionId;

            // Increase observation cardinality
            IUniswapV3(v3Pool).increaseObservationCardinalityNext(observationCardinality);
        } else {
            IPositionManagerV3.IncreaseLiquidityParams memory params =
                _calculateIncreaseLiquidityParams(v3Pool, positionId, amounts[0], amounts[1]);

            (liquidity, amounts[0], amounts[1]) = IPositionManagerV3(positionManagerV3).increaseLiquidity(params);
        }

        // TODO transfer both to treasury
        // Manage fees and dust
        _manageUtilityAmounts(tokens[0], tokens[1]);

        // TODO return liquidity and maybe amounts

        _locked = 1;
    }

    /// @dev Collects fees from LP position, burns OLAS tokens transfers another token to BBB.
    function collectFees(address token0, address token1, int24 feeTierOrTickSpacing) external {
        // TODO reentrancy
        // Get V3 pool
        address pool = _getV3Pool(token0, token1, feeTierOrTickSpacing);

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
        checkPoolAndGetCenterPrice(pool);

        // Collect fees
        _collectFees(token0, token1, positionId);

        // Manage collected fees
        _manageUtilityAmounts(token0, token1);

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

        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

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

//    function changeRanges(address token0, address token1, int24 feeTierOrTickSpacing, uint160 sqrtLowerX96, uint160 sqrtUpperX96, bool scan)
//        external returns (uint256 positionId, uint128 liquidity)
//    {
//        if (_locked > 1) {
//            revert ReentrancyGuard();
//        }
//        _locked = 2;
//
//        // Check for contract ownership
//        if (msg.sender != owner) {
//            revert OwnerOnly(msg.sender, owner);
//        }
//
//        // Sanity checks
//        if (sqrtLowerX96 > sqrtUpperX96) {
//            revert Overflow(sqrtLowerX96, sqrtUpperX96);
//        }
//
//        // Get V3 pool
//        address pool = _getV3Pool(token0, token1, feeTierOrTickSpacing);
//
//        // Check for zero address
//        if (pool == address(0)) {
//            revert ZeroAddress();
//        }
//
//        // Get position Id
//        uint256 currentPositionId = mapPoolAddressPositionIds[pool];
//
//        // Check for zero value
//        if (currentPositionId == 0) {
//            revert ZeroValue();
//        }
//
//        // Check current pool prices
//        uint160 centerSqrtPriceX96 = checkPoolAndGetCenterPrice(pool);
//
//        IPositionManagerV3.DecreaseLiquidityParams memory decreaseParams =
//            _calculateDecreaseLiquidityParams(pool, currentPositionId, 0);
//
//        // Decrease liquidity
//        uint256[] memory amounts = new uint256[](2);
//        (amounts[0], amounts[1]) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(decreaseParams);
//
//        // Collect fees
//        _collectFees(token0, token1, currentPositionId);
//        // TODO burn fees or supply to a new position?
//
//        address[] memory tokens = new address[](2);
//        tokens[0] = token0;
//        tokens[1] = token1;
//        uint160[] memory sqrtAB = new uint160[](2);
//        sqrtAB[0] = sqrtLowerX96;
//        sqrtAB[1] = sqrtUpperX96;
//        // Calculate and mint new position
//        positionId = _mint(tokens, amounts, feeTierOrTickSpacing, centerSqrtPriceX96, sqrtAB, scan);
//
//        mapPoolAddressPositionIds[pool] = positionId;
//
//        // TODO transfer leftovers both to treasury
//        // Manage fees and dust
//        _manageUtilityAmounts(token0, token1);
//
//        _locked = 1;
//    }

    function decreaseLiquidity(address token0, address token1, int24 feeTierOrTickSpacing, uint16 bps, uint16 olasWithdrawRate) external returns (uint256 positionId) {
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
        address pool = _getV3Pool(token0, token1, feeTierOrTickSpacing);

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
        checkPoolAndGetCenterPrice(pool);

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

        // If full position is decreased, remove it such that there is a possibility to create a new one
        if (bps == MAX_BPS) {
            mapPoolAddressPositionIds[pool] = 0;
        }

        // Collect fees
        _collectFees(token0, token1, positionId);

        // Manage collected fees and dust
        _manageUtilityAmounts(token0, token1);

        emit LiquidityDecreased(positionId, token0, token1, amount0, amount1, olasWithdrawAmount);

        _locked = 1;
    }

//    /// @dev Transfers token to a specified address.
//    /// @param token Token address.
//    /// @param to Account address to transfer to.
//    /// @param amount Token amount.
//    function transferToken(address token, address to, uint256 amount) external {
//        if (_locked > 1) {
//            revert ReentrancyGuard();
//        }
//        _locked = 2;
//
//        // Check for contract ownership
//        if (msg.sender != owner) {
//            revert OwnerOnly(msg.sender, owner);
//        }
//
//        // Get token balance
//        uint256 balance = IToken(token).balanceOf(address(this));
//        if (amount > balance) {
//            revert Overflow(amount, balance);
//        }
//
//        // Transfer token
//        SafeTransferLib.safeTransfer(token, to, amount);
//
//        // TODO Event?
//
//        _locked = 1;
//    }

//    /// @dev Transfers position Id to a specified address.
//    /// @param to Account address to transfer to.
//    /// @param positionId Position Id.
//    function transferPositionId(address token0, address token1, int24 feeTierOrTickSpacing, address to) external returns (uint256 positionId) {
//        if (_locked > 1) {
//            revert ReentrancyGuard();
//        }
//        _locked = 2;
//
//        // Check for contract ownership
//        if (msg.sender != owner) {
//            revert OwnerOnly(msg.sender, owner);
//        }
//
//        // Get V3 pool
//        address pool = _getV3Pool(token0, token1, feeTierOrTickSpacing);
//
//        // Check for zero address
//        if (pool == address(0)) {
//            revert ZeroAddress();
//        }
//
//        // Get position Id
//        positionId = mapPoolAddressPositionIds[pool];
//
//        // Transfer position Id
//        IPositionManagerV3(positionManagerV3).transferFrom(address(this), to, positionId);
//
//        mapPoolAddressPositionIds[pool] = 0;
//
//        // TODO Event?
//
//        _locked = 1;
//    }

    /// @dev Gets TWAP price via the built-in Uniswap V3 oracle.
    /// @param pool Pool address.
    /// @return price Calculated price.
    /// @return centerSqrtPriceX96 Calculated center SQRT price.
    function getTwapFromOracle(address pool) public view returns (uint256 price, uint160 centerSqrtPriceX96) {
        // Query the pool for the current and historical tick
        uint32[] memory secondsAgos = new uint32[](2);
        // Start of the period
        secondsAgos[0] = SECONDS_AGO;

        // Fetch the tick cumulative values from the pool: either from observations, or from slot0
        (int56[] memory tickCumulatives, ) = IUniswapV3(pool).observe(secondsAgos);

        // Calculate the average tick over the time period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 centerTick = int24(tickCumulativeDelta / int56(int32(SECONDS_AGO)));

        // Convert the average tick to sqrtPriceX96
        centerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(centerTick);

        // Calculate the price using the sqrtPriceX96
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        price = FixedPointMathLib.mulDivDown(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));
    }
    
    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @param pool Pool address.
    /// @return centerSqrtPriceX96 Calculated center SQRT price.
    function checkPoolAndGetCenterPrice(address pool)
        public view returns (uint160 centerSqrtPriceX96)
    {
        uint16 observationIndex;
        // Get current pool sqrt price and observation index
        (centerSqrtPriceX96, observationIndex) = _getPriceAndObservationIndexFromSlot0(pool);

        // Get pool observation
        (uint32 oldestTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, ) =
            IUniswapV3(pool).observations(observationIndex);

        // Check if the pool has sufficient observation history
        if ((tickCumulative == 0 && secondsPerLiquidityCumulativeX128 == 0) ||
            (oldestTimestamp + SECONDS_AGO < block.timestamp))
        {
            return centerSqrtPriceX96;
        }

        uint256 twapPrice;
        // Check TWAP or historical data
        (twapPrice, centerSqrtPriceX96) = getTwapFromOracle(pool);
        // Get instant price
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        uint256 instantPrice = FixedPointMathLib.mulDivDown(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));

        uint256 deviation;
        if (twapPrice > 0) {
            deviation = (instantPrice > twapPrice) ?
                FixedPointMathLib.mulDivDown((instantPrice - twapPrice), 1e18, twapPrice) :
                FixedPointMathLib.mulDivDown((twapPrice - instantPrice), 1e18, twapPrice);
        }

        require(deviation <= MAX_ALLOWED_DEVIATION, "Price deviation too high");
    }
}
