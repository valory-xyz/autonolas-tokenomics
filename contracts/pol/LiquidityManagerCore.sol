// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IPositionManagerV3} from "../interfaces/IPositionManagerV3.sol";
import {IToken} from "../interfaces/IToken.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Expected token address is not found in provided tokens.
/// @param provided Provided token addresses.
/// @param expected Expected token address.
error WrongTokenAddress(address[] provided, address expected);

/// @dev Out of tick range bounds.
/// @param low Low tick provided.
/// @param center Center tick provided.
/// @param high High tick provided.
error RangeBounds(int24 low, int24 center, int24 high);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

interface INeighborhoodScanner {
    /// @dev Optimizes liquidity amounts by widening up provided ticks using binary search + neighborhood search.
    /// @notice 1. Adjusts extreme boundaries, if required.
    ///         2. Looks for correct boundaries and adjusts tick spacings accordingly.
    ///         3. Fixes one of ticks and executed binary + neighborhood search if scan option is true.
    /// Ensures non-zero intermediate for amount0 formula without linear loops.
    /// @param sqrtP Center sqrt price.
    /// @param ticks Ticks array.
    /// @param tickSpacing Tick spacing.
    /// @param initialAmounts Initial amounts array.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return loHi Optimized ticks.
    /// @return liquidity Corresponding liquidity.
    /// @return amountsDesired Corresponding desired amounts.
    function optimizeLiquidityAmounts(
        uint160 sqrtP,
        int24[] calldata ticks,
        int24 tickSpacing,
        uint256[] calldata initialAmounts,
        bool scan
    ) external pure returns (int24[] memory loHi, uint128 liquidity, uint256[] memory amountsDesired);
}

/// @title Liquidity Manager Core - Smart contract for OLAS core Liquidity Manager functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract LiquidityManagerCore is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event MaxSlippageUpdated(uint256 maxSlippage);
    event ConvertedToV3(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy, bool scan);
    event RangesChanged(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy, bool scan);
    event UtilityAmountsManaged(address indexed olas, address indexed token, uint256 olasAmount, uint256 tokenAmount, bool olasBurnOrTransfer);
    event PositionMinted(uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy);
    event LiquidityDecreased(uint256 indexed positionId, uint256[] amounts, uint256 liquidity);
    event PositionLiquidityDecreased(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy);
    event LiquidityIncreased(uint256 indexed positionId, uint256[] amounts, uint256 liquidity);
    event PositionLiquidityIncreased(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts, uint256 liquidiy);
    event FeesCollected(address indexed sender, uint256 indexed positionId, uint256[] amounts);
    event PositionFeesCollected(address indexed pool, uint256 indexed positionId, address[] tokens, uint256[] amounts);
    event TicksSet(address[] tokens, int24 feeTierOrTickSpacing, int24[] initTicks, int24[] optimizedTicks, bool scan);
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
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality
    ) {
        // Check for zero addresses
        if (_olas == address(0) || _treasury == address(0) || _positionManagerV3 == address(0) ||
            _neighborhoodScanner == address(0))
        {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_observationCardinality == 0) {
            revert ZeroValue();
        }

        olas = _olas;
        treasury = _treasury;
        positionManagerV3 = _positionManagerV3;
        neighborhoodScanner = _neighborhoodScanner;
        observationCardinality = _observationCardinality;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    /// @dev Burns OLAS directly or transfers OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal virtual;

    /// @dev Checks provided tokens to match V2 pool ones and removes liquidity.
    /// @param tokens Tokens comprising V2 pool.
    /// @param v2Pool V2 pool hash or address.
    /// @return amounts Removed liquidity amounts.
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool) internal virtual returns (uint256[] memory amounts);

    /// @dev Gets tick spacing according to fee tier or tick spacing directly.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return tickSpacing Tick spacing.
    function _feeAmountTickSpacing(int24 feeTierOrTickSpacing) internal view virtual returns (int24 tickSpacing);

    /// @dev Gets sqrt price and observation index values from slot 0.
    /// @param pool Pool address.
    /// @return sqrtPriceX96 Sqrt price.
    /// @return observationIndex Observation index.
    function _getPriceAndObservationIndexFromSlot0(address pool) internal view virtual returns (uint160 sqrtPriceX96, uint16 observationIndex);

    /// @dev Gets V3 pool based on token addresses and fee tier or tick spacing.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return v3Pool V3 pool address.
    function _getV3Pool(address[] memory tokens, int24 feeTierOrTickSpacing) internal view virtual returns (address v3Pool);

    /// @dev Mints V3 pool position.
    /// @param tokens Token addresses.
    /// @param amounts Desired amounts.
    /// @param amountsMin Minimum amounts.
    /// @param ticks Ticks array.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param centerSqrtPriceX96 Center sqrt price.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn);

    /// @dev Optimizes given ticks at least to tick spacing (or liquidity based), and mints position.
    /// @param tokens Token addresses.
    /// @param inputAmounts Input amounts corresponding to tokens.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param initTicks Initial ticks array.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _optimizeTicksAndMintPosition(
        address[] memory tokens,
        uint256[] memory inputAmounts,
        int24 feeTierOrTickSpacing,
        uint160 sqrtP,
        int24[] memory initTicks,
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

        int24[] memory optimizedTicks;
        // Build percent band around TWAP center
        (optimizedTicks, liquidity, amountsIn) =
            INeighborhoodScanner(neighborhoodScanner).optimizeLiquidityAmounts(sqrtP, initTicks,
                tickSpacing, inputAmounts, scan);

        // Check for zero values
        if (liquidity == 0 || amountsIn[0] == 0 || amountsIn[1] == 0) {
            revert ZeroValue();
        }

        // Get min amounts
        uint256[] memory aMin = new uint256[](2);
        aMin[0] = amountsIn[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        aMin[1] = amountsIn[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Mint V3 position
        (positionId, liquidity, amountsIn) =
            _mintV3(tokens, amountsIn, aMin, optimizedTicks, feeTierOrTickSpacing, sqrtP);

        emit TicksSet(tokens, feeTierOrTickSpacing, initTicks, optimizedTicks, scan);
        emit PositionMinted(positionId, tokens, amountsIn, liquidity);
    }

    /// @dev Calculates ticks and mints position.
    /// @param tokens Token addresses.
    /// @param inputAmounts Input amounts corresponding to tokens.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param sqrtP Center sqrt price.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted position Id.
    /// @return liquidity Produced liquidity.
    /// @return amountsIn Amounts in liquidity.
    function _calculateTicksAndMintPosition(
        address[] memory tokens,
        uint256[] memory inputAmounts,
        int24 feeTierOrTickSpacing,
        uint160 sqrtP,
        int24[] calldata tickShifts,
        bool scan
    )
        internal returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsIn)
    {
        int24 centerTick = TickMath.getTickAtSqrtRatio(sqrtP);
        int24[] memory ticks = new int24[](2);
        ticks[0] = centerTick + tickShifts[0];
        ticks[1] = centerTick + tickShifts[1];

        if (ticks[0] >= centerTick || ticks[1] <= centerTick) {
            revert RangeBounds(ticks[0], centerTick, ticks[1]);
        }

        // Calculate and mint new position
        return _optimizeTicksAndMintPosition(tokens, inputAmounts, feeTierOrTickSpacing, sqrtP, ticks, scan);
    }

    /// @dev Collects fees from LP position.
    /// @notice Function does not revert if any of amounts are zero.
    /// @param positionId Position Id.
    /// @return amounts Amounts array.
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

        emit FeesCollected(msg.sender, positionId, amounts);
    }

    /// @dev Decreases liquidity for specified pool.
    /// @param pool Pool address.
    /// @param positionId Position Id.
    /// @param decreaseRate Rate of position decrease in BPS.
    /// @return liquidity Decreased liquidity amount.
    /// @return amountsOut Amounts from liquidity.
    function _decreaseLiquidity(address pool, uint256 positionId, uint16 decreaseRate)
        internal returns (uint128 liquidity, uint256[] memory amountsOut)
    {
        // Read position & liquidity
        int24[] memory ticks = new int24[](2);
        (, , , , , ticks[0], ticks[1], liquidity, , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);
        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Calculate liquidity based on provided BPS, if any
        if (decreaseRate < MAX_BPS) {
            liquidity = (liquidity * decreaseRate) / MAX_BPS;
        }

        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

        // Get sqrt prices for ticks
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);

        // Get amounts based on liquidity
        uint256[] memory amountsMin = new uint256[](2);
        (amountsMin[0], amountsMin[1]) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);

        // Get minimum amounts according to slippage
        amountsMin[0] = amountsMin[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        amountsMin[1] = amountsMin[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Assemble decrease liquidity params
        IPositionManagerV3.DecreaseLiquidityParams memory params = IPositionManagerV3.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liquidity,
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            deadline: block.timestamp
        });

        // Decrease liquidity
        amountsOut = new uint256[](2);
        (amountsOut[0], amountsOut[1]) = IPositionManagerV3(positionManagerV3).decreaseLiquidity(params);

        emit LiquidityDecreased(positionId, amountsOut, liquidity);
    }

    /// @dev Increases liquidity for specified pool.
    /// @param pool Pool address.
    /// @param positionId Position Id.
    /// @param inputAmounts Input amounts.
    /// @return liquidity Decreased liquidity amount.
    /// @return amountsIn Amounts in liquidity.
    function _increaseLiquidity(address pool, uint256 positionId, uint256[] memory inputAmounts)
        internal returns (uint128 liquidity, uint256[] memory amountsIn)
    {
        // Get current pool sqrt price
        (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

        // Read position & liquidity
        int24[] memory ticks = new int24[](2);
        (, , , , , ticks[0], ticks[1], , , , , ) = IPositionManagerV3(positionManagerV3).positions(positionId);

        // Get sqrt prices for ticks
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);
        // Compute liquidity based on amounts and sqrt prices
        liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtAB[0], sqrtAB[1], inputAmounts[0], inputAmounts[1]);

        // Check for zero value
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Get amounts for liquidity
        (inputAmounts[0], inputAmounts[1]) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtAB[0], sqrtAB[1], liquidity);
        uint256[] memory aMin = new uint256[](2);
        aMin[0] = inputAmounts[0] * (MAX_BPS - maxSlippage) / MAX_BPS;
        aMin[1] = inputAmounts[1] * (MAX_BPS - maxSlippage) / MAX_BPS;

        // Assemble increase liquidity params
        IPositionManagerV3.IncreaseLiquidityParams memory params = IPositionManagerV3.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: inputAmounts[0],
            amount1Desired: inputAmounts[1],
            amount0Min: aMin[0],
            amount1Min: aMin[1],
            deadline: block.timestamp
        });

        // Increase liquidity
        amountsIn = new uint256[](2);
        (liquidity, amountsIn[0], amountsIn[1]) = IPositionManagerV3(positionManagerV3).increaseLiquidity(params);

        emit LiquidityIncreased(positionId, amountsIn, liquidity);
    }

    /// @dev Manages utility token amounts.
    /// @notice Non-OLAS token is always transferred to treasury, OLAS is either burnt or transferred as well.
    /// @param tokens Token addresses.
    /// @param utilizationRate Token utilization rate, in BPS.
    /// @param olasBurnOrTransfer True if OLAS is burnt, false if transferred to treasury.
    function _manageUtilityAmounts(address[] memory tokens, uint16 utilizationRate, bool olasBurnOrTransfer)
        internal returns (uint256[] memory updatedBalances)
    {
        updatedBalances = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        // Get token balances
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Adjust amounts according to utilizationRate
        if (utilizationRate < MAX_BPS) {
            updatedBalances[0] = amounts[0];
            updatedBalances[1] = amounts[1];

            amounts[0] = (amounts[0] * utilizationRate) / MAX_BPS;
            amounts[1] = (amounts[1] * utilizationRate) / MAX_BPS;

            // Update leftover balances
            updatedBalances[0] -= amounts[0];
            updatedBalances[1] -= amounts[1];
        }

        // Get token balances
        uint256 olasAmount;
        uint256 tokenAmount;
        address secondToken;

        // Check for OLAS token and swap values, if needed
        if (tokens[0] == olas) {
            secondToken = tokens[1];
            olasAmount = amounts[0];
            tokenAmount = amounts[1];
        } else {
            secondToken = tokens[0];
            olasAmount = amounts[1];
            tokenAmount = amounts[0];
        }

        // Manage OLAS token
        if (olasAmount > 0) {
            if (olasBurnOrTransfer) {
                // Directly burn or transfer OLAS to Burner contract
                _burn(olasAmount);
            } else {
                // Transfer OLAS to Treasury contract
                IToken(olas).transfer(treasury, olasAmount);
            }
        }

        // Transfer another token to Treasury
        if (tokenAmount > 0) {
            SafeTransferLib.safeTransfer(secondToken, treasury, tokenAmount);
        }

        emit UtilityAmountsManaged(olas, secondToken, olasAmount, tokenAmount, olasBurnOrTransfer);
    }

    /// @dev Initialization function.
    /// @param _maxSlippage Max slippage for operations.
    function initialize(uint16 _maxSlippage) external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        // Check for zero value
        if (_maxSlippage == 0) {
            revert ZeroValue();
        }
        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        maxSlippage = _maxSlippage;

        owner = msg.sender;
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

    /// @dev Changes max slippage value.
    /// @param newMaxSlippage New max slippage value.
    function changeMaxSlippage(uint16 newMaxSlippage) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (newMaxSlippage == 0) {
            revert ZeroValue();
        }

        maxSlippage = newMaxSlippage;
        emit MaxSlippageUpdated(newMaxSlippage);
    }

    /// @dev Converts token amounts to V3 liquidity: from balances, or from V2 liquidity, or both.
    /// @param tokens Token addresses.
    /// @param v2Pool V2 pool hash / address.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param olasBurnRate OLAS burn rate in BPS: burns specified amount of OLAS from initial token amounts,
    ///        transfers same rate of another token to treasury address.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function convertToV3(address[] memory tokens, bytes32 v2Pool, int24 feeTierOrTickSpacing, int24[] calldata tickShifts, uint16 olasBurnRate, bool scan)
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

        // Check for OLAS in pair
        if (tokens[0] != olas && tokens[1] != olas) {
            revert WrongTokenAddress(tokens, olas);
        }

        // Check conversion rate overflow
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        if (v2Pool != 0) {
            // Remove liquidity from V2 pool
            _checkTokensAndRemoveLiquidityV2(tokens, v2Pool);
        }

        // Get token amounts
        amounts = new uint256[](2);
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Check for zero values
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Get V3 pool
        address v3Pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (v3Pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on OLAS burn rate
        if (olasBurnRate > 0) {
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Check current pool prices
        uint160 sqrtP = checkPoolAndGetCenterPrice(v3Pool);

        // Approve tokens for position manager
        IToken(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken(tokens[1]).approve(positionManagerV3, amounts[1]);

        // Get position Id
        positionId = mapPoolAddressPositionIds[v3Pool];

        // positionId is zero if it was not created before for this pool
        if (positionId == 0) {
            (positionId, liquidity, amounts) =
                _calculateTicksAndMintPosition(tokens, amounts, feeTierOrTickSpacing, sqrtP, tickShifts, scan);

            mapPoolAddressPositionIds[v3Pool] = positionId;

            // Increase observation cardinality
            IUniswapV3(v3Pool).increaseObservationCardinalityNext(observationCardinality);
        } else {
            // Increase liquidity with actual ticks, since position already exists
            (liquidity, amounts) = _increaseLiquidity(v3Pool, positionId, amounts);
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit ConvertedToV3(v3Pool, positionId, tokens, amounts, liquidity, scan);

        _locked = 1;
    }

    /// @dev Collects fees from LP position, burns OLAS tokens and transfers another token to treasury.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return amounts Amounts array.
    function collectFees(address[] memory tokens, int24 feeTierOrTickSpacing) external returns (uint256[] memory amounts) {
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
        amounts = _collectFees(positionId);

        // Check for zero values
        if (amounts[0] == 0 && amounts[1] == 0) {
            revert ZeroValue();
        }

        // Manage collected fees: burn OLAS, transfer another token
        _manageUtilityAmounts(tokens, MAX_BPS, true);

        emit PositionFeesCollected(pool, positionId, tokens, amounts);

        _locked = 1;
    }

    /// @dev Changes ranges of position in a specified pool.
    /// @notice Any collected fees from liquidating initial position are supplied for one with repositioned ranges.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param tickShifts Tick shifts array: shifts from central tick value.
    /// @param scan True if binary and neighborhood ticks search for optimal liquidity is requested, false otherwise.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function changeRanges(address[] memory tokens, int24 feeTierOrTickSpacing, int24[] calldata tickShifts, bool scan)
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
                _calculateTicksAndMintPosition(tokens, amounts, feeTierOrTickSpacing, centerSqrtPriceX96, tickShifts, scan);

            // Record position Id
            mapPoolAddressPositionIds[pool] = positionId;
        }

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit RangesChanged(pool, positionId, tokens, amounts, liquidity, scan);

        _locked = 1;
    }

    /// @dev Decreases liquidity for specified pool.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param decreaseRate Rate of position decrease in BPS.
    /// @param olasBurnRate OLAS burn rate in BPS, relative to specified decreaseRate: burns OLAS from decreased
    ///        token amounts and collected fees, transfers same rate of another token to treasury address.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Decreased liquidity amount.
    /// @return amounts Amounts from liquidity.
    function decreaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 decreaseRate, uint16 olasBurnRate)
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

        // Check decrease and olas burn rates
        if (decreaseRate == 0) {
            revert ZeroValue();
        }
        if (decreaseRate > MAX_BPS) {
            revert Overflow(decreaseRate, MAX_BPS);
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
        (liquidity, ) = _decreaseLiquidity(pool, positionId, decreaseRate);

        // Collect fees and tokens removed from liquidity
        amounts = _collectFees(positionId);

        // Burn OLAS and transfer another token to treasury
        if (olasBurnRate > 0) {
            _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Manage collected amounts - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit PositionLiquidityDecreased(pool, positionId, tokens, amounts, liquidity);

        _locked = 1;
    }

    /// @dev Increases liquidity for specified pool.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @param olasBurnRate OLAS burn rate in BPS: burns specified amount of OLAS from initial token amounts,
    ///        transfers same rate of another token to treasury address.
    /// @return positionId Minted or existing position Id.
    /// @return liquidity Produced liquidity.
    /// @return amounts Amounts in liquidity.
    function increaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 olasBurnRate)
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

        // Check conversion rate overflow
        if (olasBurnRate > MAX_BPS) {
            revert Overflow(olasBurnRate, MAX_BPS);
        }

        // Get token amounts
        amounts = new uint256[](2);
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Check for zero values
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Get V3 pool
        address pool = _getV3Pool(tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Recalculate amounts for adding position liquidity depending on OLAS burn rate
        if (olasBurnRate > 0) {
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

        // Get positionId
        positionId = mapPoolAddressPositionIds[pool];

        // Check for zero position
        if (positionId == 0) {
            revert ZeroValue();
        }

        // Check current pool prices
        checkPoolAndGetCenterPrice(pool);

        // Approve tokens for position manager
        IToken(tokens[0]).approve(positionManagerV3, amounts[0]);
        IToken(tokens[1]).approve(positionManagerV3, amounts[1]);

        // Increase liquidity
        (liquidity, amounts) = _increaseLiquidity(pool, positionId, amounts);

        // Manage token leftovers - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

        emit PositionLiquidityIncreased(pool, positionId, tokens, amounts, liquidity);

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

    /// @dev Gets TWAP price via built-in Uniswap V3 oracle.
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
    function checkPoolAndGetCenterPrice(address pool) public view returns (uint160 centerSqrtPriceX96) {
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
        // Calculate price deviation
        if (twapPrice > 0) {
            deviation = (instantPrice > twapPrice) ?
                mulDiv((instantPrice - twapPrice), 1e18, twapPrice) :
                mulDiv((twapPrice - instantPrice), 1e18, twapPrice);
        }

        // Check price deviation
        if (deviation > MAX_ALLOWED_DEVIATION) {
            revert Overflow(deviation, MAX_ALLOWED_DEVIATION);
        }
    }
}
