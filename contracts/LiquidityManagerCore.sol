// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../lib/solmate/src/tokens/ERC721.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IErrorsTokenomics} from "./interfaces/IErrorsTokenomics.sol";
import {IToken} from "./interfaces/IToken.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV3} from "./interfaces/IUniswapV3.sol";

// BuyBackBurner interface
interface IBuyBackBurner {
    function checkPoolPrices(address token0, address token1, address uniV3PositionManager, uint24 fee) external view;
}

// OLAS interface
interface IOlas {
    /// @dev Burns OLAS tokens.
    /// @param amount OLAS token amount to burn.
    function burn(uint256 amount) external;
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

struct PoolSettings {
    // Fee tier
    uint24 feeTier;
    // Minimum tick
    int24 minTick;
    // Maximum tick
    int24 maxTick;
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
    // Max conversion value from v2 to v3
    uint256 public constant MAX_CONVERSION_VALUE = 10_000;

    // Owner address
    address public owner;

    // OLAS token address
    address public immutable olas;
    // Timelock token address
    address public immutable timelock;
    // Treasury contract address
    address public immutable treasury;
    // Buy Back Burner address
    address public immutable buyBackBurner;
    // Uniswap V2 Router address
    address public immutable routerV2;
    // V3 position manager address
    address public immutable positionManagerV3;
    // V3 factory
    address public immutable factoryV3;

    // Reentrancy lock
    uint256 internal _locked;

    // V3 pool settings
    mapping(address => PoolSettings) public mapPoolSettings;
    // V3 position Ids
    mapping(address => uint256) public mapPoolAddressPositionIds;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _timelock Timelock or its representative address.
    /// @param _treasury Treasury address.
    /// @param _buyBackBurner Buy Back Burner address.
    /// @param _routerV2 Uniswap V2 Router address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    constructor(
        address _olas,
        address _timelock,
        address _treasury,
        address _buyBackBurner,
        address _routerV2,
        address _positionManagerV3
    ) {
        owner = msg.sender;

        // Check for zero addresses
        if (_olas == address(0) || _timelock == address(0) || _treasury == address(0) || _routerV2 == address(0) ||
            _positionManagerV3 == address(0))
        {
            revert ZeroAddress();
        }

        olas = _olas;
        timelock = _timelock;
        treasury = _treasury;
        buyBackBurner = _buyBackBurner;
        routerV2 = _routerV2;
        positionManagerV3 = _positionManagerV3;

        // Get V3 factory address
        factoryV3 = IUniswapV3(positionManagerV3).factory();
    }

    function _manageUtilityAmounts(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 conversionRate
    ) internal returns (uint256 amount0Position, uint256 amount1Position) {
        // Calculate position amounts
        uint256 amount0Utility = amount0 * conversionRate / MAX_CONVERSION_VALUE;
        uint256 amount1Utility = amount1 * conversionRate / MAX_CONVERSION_VALUE;

        // Adjust utility amounts
        amount0Position = amount0 - amount0Utility;
        amount1Position = amount1 - amount0Utility;

        // Check for OLAS token
        if (token0 == olas) {
            // Burn OLAS
            IOlas(olas).burn(amount0Utility);
            // Transfer to Timelock
            IToken(token1).transfer(timelock, amount1Utility);
        } else {
            // Burn OLAS
            IOlas(olas).burn(amount1Utility);
            // Transfer to Timelock
            IToken(token0).transfer(timelock, amount0Utility);
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

//    /// @dev Gets required V3 pool cardinality.
//    /// @return Pool cardinality.
//    function _observationCardinalityNext() internal virtual pure returns (uint16) {
//        // ETH mainnet V3 pool cardinality that corresponds to 720 seconds window (720 / 12 seconds per block)
//        return 60;
//    }
//
//    // TODO Move to forge script as V3 pool must be already created
//    function createV3Pool(address token0, address token1, uint24 feeTier, uint256 conversionRate) external returns (uint256 positionId, uint256 liquidity) {
//        // Get V3 pool
//        address pool = IUniswapV3(factoryV3).getPool(token0, token1, feeTier);
//
//        // If pool does not exists - create one
//        if (pool != address(0)) {
//            revert();
//        }
//        // Calculate the price ratio (amount1 / amount0) scaled by 1e18 to avoid floating point issues
//        uint256 price = FixedPointMathLib.divWadDown(amount1, amount0);
//
//        // Calculate the square root of the price ratio in X96 format
//        uint160 sqrtPriceX96 = uint160((FixedPointMathLib.sqrt(price) * (1 << 96)) / 1e9);
//
//        // Create pool
//        pool = IUniswapV3(positionManagerV3).createAndInitializePoolIfNecessary(token0, token1, feeTier, sqrtPriceX96);
//
//        // Approve tokens for position manager
//        IToken(token0).approve(positionManagerV3, amount0);
//        IToken(token1).approve(positionManagerV3, amount1);
//
//        // TODO Slippage
//        // Add iquidity
//        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
//            token0: token0,
//            token1: token1,
//            fee: FEE_TIER,
//            tickLower: MIN_TICK,
//            tickUpper: MAX_TICK,
//            amount0Desired: amount0,
//            amount1Desired: amount1,
//            amount0Min: 0, // Accept any amount of token0
//            amount1Min: 0, // Accept any amount of token1
//            recipient: address(this),
//            deadline: block.timestamp
//        });
//
//        (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);
//
//        // Increase observation cardinality
//        IUniswapV3(pool).increaseObservationCardinalityNext(_observationCardinalityNext());
//    }

    function convertToV3(address lpToken, PoolSettings memory poolSettings, uint256 conversionRate, uint256 initPositionId) external returns (uint256 liquidity, uint256 positionId) {
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
        if (conversionRate > MAX_CONVERSION_VALUE) {
            revert Overflow(conversionRate, MAX_CONVERSION_VALUE);
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

        // TODO Slippage
        // Remove liquidity
        (uint256 amount0, uint256 amount1) =
            IUniswapV2(routerV2).removeLiquidity(token0, token1, liquidity, 1, 1, address(this), block.timestamp);

        // V3
        // Get V3 pool
        address pool = IUniswapV3(factoryV3).getPool(token0, token1, poolSettings.feeTier);

        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Manage utility amounts and recalculate amounts for adding position liquidity
        if (conversionRate < MAX_CONVERSION_VALUE) {
            (amount0, amount1) = _manageUtilityAmounts(token0, token1, amount0, amount1, conversionRate);
        }

        // Check current pool prices
        IBuyBackBurner(buyBackBurner).checkPoolPrices(token0, token1, positionManagerV3, poolSettings.feeTier);

        // Approve tokens for position manager
        IToken(token0).approve(positionManagerV3, amount0);
        IToken(token1).approve(positionManagerV3, amount1);

        // TODO Slippage
        if (initPositionId == 0) {
            // Add iquidity
            IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
                token0: token0,
                token1: token1,
                fee: poolSettings.feeTier,
                tickLower: poolSettings.minTick,
                tickUpper: poolSettings.maxTick,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0, // Accept any amount of token0
                amount1Min: 0, // Accept any amount of token1
                recipient: address(this),
                deadline: block.timestamp
            });

            (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

            mapPoolAddressPositionIds[pool] = positionId;
        } else {
            positionId = initPositionId;
            IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
                tokenId: initPositionId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

            (liquidity, amount0, amount1) = IPositionManager(positionManagerV3).increaseLiquidity(params);
        }

        // TODO event

        _locked = 1;
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
        IBuyBackBurner(buyBackBurner).checkPoolPrices(token0, token1, positionManagerV3, feeTier);

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

        // TODO event
        // emit FeesCollected(msg.sender,

        if (token0 == olas) {
            // Burn olas tokens
            IOlas(olas).burn(amount0);

            // Transfer another token amount
            IToken(token0).transfer(timelock, amount1);
        } else {
            // Burn olas tokens
            IOlas(olas).burn(amount1);

            // Transfer another token amount
            IToken(token0).transfer(timelock, amount0);
        }

        _locked = 1;
    }

    function changeRanges(address token0, address token1, uint24 feeTier, PoolSettings memory poolSettings) external returns (uint256 positionId) {
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

        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = IPositionManager(positionManagerV3).positions(currentPositionId);

        // TODO Check for different poolSettings, otherwise revert

        // TODO getAmountsForLiquidity()
        uint256 amount0;
        uint256 amount1;

        // TODO Slippage
        IPositionManager.DecreaseLiquidityParams memory decreaseParams = IPositionManager.DecreaseLiquidityParams({
            tokenId: currentPositionId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // Decrease liquidity
        (uint256 amount00, uint256 amount11) = IPositionManager(positionManagerV3).decreaseLiquidity(decreaseParams);

        // Add iquidity
        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
            token0: token0,
            token1: token1,
            fee: poolSettings.feeTier,
            tickLower: poolSettings.minTick,
            tickUpper: poolSettings.maxTick,
            amount0Desired: amount00,
            amount1Desired: amount11,
            amount0Min: 0, // Accept any amount of token0
            amount1Min: 0, // Accept any amount of token1
            recipient: address(this),
            deadline: block.timestamp
        });

        (positionId, liquidity, amount0, amount1) = IUniswapV3(positionManagerV3).mint(params);

        mapPoolAddressPositionIds[pool] = positionId;

        // TODO Event

        _locked = 1;
    }

    /// @dev Transfers position Id to a specified address.
    /// @param to Account address to transfer to.
    /// @param positionId Position Id.
    function transfer(address to, uint256 positionId) external {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Transfer position Id
        IPositionManager(positionManagerV3).transferFrom(address(this), to, positionId);

        _locked = 1;
    }
}
