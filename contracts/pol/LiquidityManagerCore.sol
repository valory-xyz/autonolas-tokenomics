// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IErrorsTokenomics} from "../interfaces/IErrorsTokenomics.sol";
import {IPositionManagerV3} from "../interfaces/IPositionManagerV3.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";

interface INeighborhoodScanner {
    function optimizeLiquidityAmounts(
        uint160 centerSqrtPriceX96,
        int24[] memory ticks,
        int24 tickSpacing,
        uint256[] memory balances,
        bool scan
    ) external pure returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired);
}

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver, IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event UtilityAmountsManaged(address indexed olas, address indexed token, uint256 olasAmount, uint256 tokenAmount, bool burnOrTransfer);
    event PositionMinted(uint256 indexed positionId, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidiy);
    event LiquidityDecreased(uint256 indexed positionId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityIncreased(uint256 indexed positionId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event FeesCollected(address indexed sender, uint256 indexed positionId, uint256 amount0, uint256 amount1);
    event TicksSet(address indexed token0, address indexed token1, int24 feeTierOrTickSpacing, int24 tickLower, int24 tickUpper);
    event PositionTransferred(uint256 indexed positionId, address indexed to);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount);

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

    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool) internal virtual returns (uint256[] memory amounts);

    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing) internal view virtual returns (int24 tickSpacing);

    function _getPriceAndObservationIndexFromSlot0(address pool) internal view virtual returns (uint160 sqrtPriceX96, uint16 observationIndex);

    function _getV3Pool(address[] memory tokens, int24 feeTierOrTickSpacing) internal view virtual returns (address v3Pool);

    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsOut);

    /// @notice Function does not revert if any of amounts are zero.
    function _collectFees(uint256 positionId) internal returns (uint256[] memory amounts) {
        IUniswapV3.CollectParams memory params = IUniswapV3.CollectParams({
            tokenId: positionId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        amounts = new uint256[](2);
        // Get corresponding token fees
        (amounts[0], amounts[1]) = IUniswapV3(positionManagerV3).collect(params);

        emit FeesCollected(msg.sender, positionId, amounts[0], amounts[1]);
    }

    function _adjustTicksAndMintPosition(
        address[] memory tokens,
        uint256[] memory inputAmounts,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96,
        int24[] memory ticks,
        bool scan
    )
        internal returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn)
    {
        // Get tick spacing
        int24 tickSpacing = _feeAmountTickSpacing(feeTierOrTickSpacing);
        // Check for zero value
        if (tickSpacing == 0) {
            revert ZeroValue();
        }

        // Build percent band around TWAP center
        (ticks, liquidity, amountsIn) =
            INeighborhoodScanner(neighborhoodScanner).optimizeLiquidityAmounts(centerSqrtPriceX96, ticks, tickSpacing,
                inputAmounts, scan);

        uint256[] memory amountsMin = new uint256[](2);
        amountsMin[0] = amountsIn[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        amountsMin[1] = amountsIn[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        (positionId, liquidity, amountsIn) =
            _mintV3(tokens, amountsIn, amountsMin, ticks, feeTierOrTickSpacing, centerSqrtPriceX96);

        emit TicksSet(tokens[0], tokens[1], feeTierOrTickSpacing, ticks[0], ticks[1]);
        emit PositionMinted(positionId, tokens[0], tokens[1], amountsIn[0], amountsIn[1], liquidity);
    }

    function _calculateTicksAndMintPosition(
        int24 feeTierOrTickSpacing,
        address[] memory tokens,
        uint256[] memory inputAmounts,
        uint160 centerSqrtPriceX96,
        int24[] memory tickShifts,
        bool scan
    )
        internal returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn)
    {
        int24 centerTick = TickMath.getTickAtSqrtRatio(centerSqrtPriceX96);
        tickShifts[0] = centerTick + tickShifts[0];
        tickShifts[1] = centerTick + tickShifts[1];

        if (tickShifts[0] >= centerTick || tickShifts[1] <= centerTick) {
            revert();
        }

        // Calculate and mint new position
        return _adjustTicksAndMintPosition(tokens, inputAmounts, feeTierOrTickSpacing, centerSqrtPriceX96, tickShifts, scan);
    }

    function _decreaseLiquidity(address pool, uint256 positionId, uint16 bps)
        internal returns (uint256[] memory amountsOut)
    {
        // Read position & liquidity
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Calculate liquidity based on provided BPS, if any
        if (bps < MAX_BPS) {
            liquidity = (liquidity * bps) / MAX_BPS;
        }

        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

        // Decrease liquidity
        (uint256 amount0Min, uint256 amount1Min) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
        amount0Min = amount0Min * (MAX_BPS - maxSlippage) / MAX_BPS;
        amount1Min = amount1Min * (MAX_BPS - maxSlippage) / MAX_BPS;

        IPositionManagerV3.DecreaseLiquidityParams memory params = IPositionManagerV3.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });

        amountsOut = new uint256[](2);
        (amountsOut[0], amountsOut[1]) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(params);

        emit LiquidityDecreased(positionId, liquidity, amountsOut[0], amountsOut[1]);
    }

    function _increaseLiquidity(address pool, uint256 positionId, uint256[] memory inputAmounts)
        internal returns (uint128 liquidity, uint256[] memory amountsIn)
    {
        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

        int24[] memory ticks = new int24[](2);
        (, , , , , ticks[0], ticks[1], liquidity, , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);
        uint128 liquidityMin = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtAB[0], sqrtAB[1], inputAmounts[0], inputAmounts[1]);

        if (liquidity > liquidityMin) {
            liquidity = liquidityMin;
        }

        uint256[] memory aMin = new uint256[](2);
        (aMin[0], aMin[1]) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);
        aMin[0] = inputAmounts[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        aMin[1] = inputAmounts[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        IPositionManagerV3.IncreaseLiquidityParams memory params = IPositionManagerV3.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: inputAmounts[0],
            amount1Desired: inputAmounts[1],
            amount0Min: aMin[0],
            amount1Min: aMin[1],
            deadline: block.timestamp
        });

        amountsIn = new uint256[](2);
        (liquidity, amountsIn[0], amountsIn[1]) = IPositionManagerV3(positionManagerV3).increaseLiquidity(params);

        emit LiquidityIncreased(positionId, liquidity, amountsIn[0], amountsIn[1]);
    }

    function _manageUtilityAmounts(address[] memory tokens, uint32 conversionRate, bool burnOrTransfer)
        internal returns (uint256[] memory updatedBalances)
    {
        updatedBalances = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Adjust amounts
        if (conversionRate < MAX_BPS) {
            updatedBalances[0] = amounts[0];
            updatedBalances[1] = amounts[1];

            amounts[0] = (amounts[0] * conversionRate) / MAX_BPS;
            amounts[1] = (amounts[1] * conversionRate) / MAX_BPS;

            updatedBalances[0] -= amounts[0];
            updatedBalances[1] -= amounts[1];
        }

        // Get token balances
        uint256 olasAmount;
        uint256 tokenAmount;

        // Check for OLAS token
        if (tokens[0] == olas) {
            olasAmount = amounts[0];
            tokenAmount = amounts[1];
        } else {
            tokens[1] = tokens[0];
            olasAmount = amounts[1];
            tokenAmount = amounts[0];
        }

        // Directly burns or Transfer OLAS to Burner contract
        if (olasAmount > 0) {
            if (burnOrTransfer) {
                _burn(olasAmount);
            } else {
                IToken(olas).transfer(treasury, olasAmount);
            }
        }

        // Transfer to Treasury
        if (tokenAmount > 0) {
            IToken(tokens[1]).transfer(treasury, tokenAmount);
        }

        emit UtilityAmountsManaged(olas, tokens[1], olasAmount, tokenAmount, burnOrTransfer);
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

    function convertToV3(address[] memory tokens, bytes32 v2Pool, int24 feeTierOrTickSpacing, int24[] memory tickShifts, uint16 conversionRate, bool scan)
        external returns (uint256 positionId, uint256 liquidity, uint256[] memory amounts)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Shall we accept non-OLAS pairs?
        // Check for OLAS in pair
        if (tokens[0] != olas && tokens[1] != olas) {
            revert();
        }

        // Check conversion rate
        if (conversionRate == 0) {
            revert ZeroValue();
        }
        if (conversionRate > MAX_BPS) {
            revert Overflow(conversionRate, MAX_BPS);
        }

        if (v2Pool != 0) {
            // Remove liquidity from V2 pool
            _checkTokensAndRemoveLiquidityV2(tokens, v2Pool);
        }
        
        // Get token amounts
        amounts = new uint256[](2);
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Get V3 pool
        address v3Pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (v3Pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on conversion rate
        if (conversionRate < MAX_BPS) {
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, conversionRate, true);
        }

        // Check current pool prices
        uint160 centerSqrtPriceX96 = checkPoolAndGetCenterPrice(v3Pool);

        // Approve tokens for position manager
        IToken(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken(tokens[1]).approve(positionManagerV3, amounts[1]);

        positionId = mapPoolAddressPositionIds[v3Pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            (positionId, liquidity, amounts) =
                _calculateTicksAndMintPosition(feeTierOrTickSpacing, tokens, amounts, centerSqrtPriceX96, tickShifts, scan);

            mapPoolAddressPositionIds[v3Pool] = positionId;

            // Increase observation cardinality
            IUniswapV3(v3Pool).increaseObservationCardinalityNext(observationCardinality);
        } else {
            (liquidity, amounts) = _increaseLiquidity(v3Pool, positionId, amounts);
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        _locked = 1;
    }

    /// @dev Collects fees from LP position, burns OLAS tokens transfers another token to BBB.
    function collectFees(address[] memory tokens, int24 feeTierOrTickSpacing) external {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

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
        uint256[] memory amounts = _collectFees(positionId);

        // Check for zero values
        if (amounts[0] == 0 && amounts[1] == 0) {
            revert ZeroValue();
        }

        // Manage collected fees: burn OLAS, transfer another token
        _manageUtilityAmounts(tokens, MAX_BPS, true);

        _locked = 1;
    }

    function changeRanges(address[] memory tokens, int24 feeTierOrTickSpacing, int24[] memory tickShifts, bool scan)
        external returns (uint256 positionId, uint128 liquidity, uint256[] memory amounts)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

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
        uint160 centerSqrtPriceX96 = checkPoolAndGetCenterPrice(pool);

        // Decrease liquidity
        _decreaseLiquidity(pool, currentPositionId, MAX_BPS);

        // Collect fees and tokens removed from liquidity
        amounts = _collectFees(currentPositionId);

        // Check that we have liquidity for both tokens
        if (amounts[0] > 0 && amounts[1] > 0) {
            // Approve tokens for position manager
            IToken(tokens[0]).approve(positionManagerV3, amounts[0]);
            IToken(tokens[1]).approve(positionManagerV3, amounts[1]);

            // Calculate params and mint new position
            (positionId, liquidity, amounts) =
                _calculateTicksAndMintPosition(feeTierOrTickSpacing, tokens, amounts, centerSqrtPriceX96, tickShifts, scan);

            mapPoolAddressPositionIds[pool] = positionId;
        } else {
            mapPoolAddressPositionIds[pool] = 0;
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        _locked = 1;
    }

    function decreaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 bps, uint16 olasBurnRate)
        external returns (uint256 positionId, uint256[] memory amounts)
    {
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
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

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

        // Decrease liquidity
        _decreaseLiquidity(pool, positionId, bps);

        // Collect fees and tokens removed from liquidity
        amounts = _collectFees(positionId);

        // Transfer OLAS and another token to treasury
        if (olasBurnRate > 0) {
            _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Manage collected amounts - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        // If full position is decreased, remove it such that there is a possibility to create a new one
        if (bps == MAX_BPS) {
            mapPoolAddressPositionIds[pool] = 0;
        }

        _locked = 1;
    }

    /// @dev Transfers position Id to a specified address.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transferPositionId(address[] memory tokens, int24 feeTierOrTickSpacing, address to)
        external returns (uint256 positionId)
    {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

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

        // Transfer position Id
        IPositionManagerV3(positionManagerV3).transferFrom(address(this), to, positionId);

        mapPoolAddressPositionIds[pool] = 0;

        emit PositionTransferred(positionId, to);

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

        emit TokenTransferred(token, to, amount);

        _locked = 1;
    }

    /// @dev Gets TWAP price via the built-in Uniswap V3 oracle.
    /// @param pool Pool address.
    /// @return price Calculated price.
    /// @return centerSqrtPriceX96 Calculated center SQRT price.
    function getTwapFromOracle(address pool) public view returns (uint256 price, uint160 centerSqrtPriceX96) {
        // Query the pool for the current and historical tick
        uint32[] memory secondsAgo = new uint32[](2);
        // Start of the period
        secondsAgo[0] = SECONDS_AGO;

        // Fetch the tick cumulative values from the pool: either from observations, or from slot0
        (int56[] memory tickCumulatives, ) = IUniswapV3(pool).observe(secondsAgo);

        // Calculate the average tick over the time period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 centerTick = int24(tickCumulativeDelta / int56(int32(SECONDS_AGO)));

        // Convert the average tick to sqrtPriceX96
        centerSqrtPriceX96 = TickMath.getSqrtRatioAtTick(centerTick);

        // Calculate the price using the sqrtPriceX96
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        price = mulDiv(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));
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

        // Get oldest observations timestamp
        (uint32 oldestTimestamp, , , ) = IUniswapV3(pool).observations(observationIndex);

        // Check if the pool had enough activity during last SECONDS_AGO period
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return centerSqrtPriceX96;
        }

        uint256 twapPrice;
        bytes memory payload = abi.encodeCall(this.getTwapFromOracle, (pool));
        // Check TWAP or historical data
        (bool success, bytes memory returnData)= address(this).staticcall(payload);

        // If the call has failed - observe was not successful, meaning the pool has not have enough activity yet
        if (!success) {
            return centerSqrtPriceX96;
        }

        // Get returned values from oracle
        (twapPrice, centerSqrtPriceX96) = abi.decode(returnData, (uint256, uint160));

        // Get instant price
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        uint256 instantPrice = mulDiv(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), (1 << 64));

        uint256 deviation;
        if (twapPrice > 0) {
            deviation = (instantPrice > twapPrice) ?
                mulDiv((instantPrice - twapPrice), 1e18, twapPrice) :
                mulDiv((twapPrice - instantPrice), 1e18, twapPrice);
        }

        require(deviation <= MAX_ALLOWED_DEVIATION, "Price deviation too high");
    }
}
