// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IUniswapV3} from "../interfaces/IUniswapV3.sol";
import {TickMath} from "../libraries/TickMath.sol";

// ERC20 interface
interface IERC20 {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

// LiquidityManager interface
interface ILiquidityManager {
    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @param pool Pool address.
    /// @return Calculated center SQRT price.
    function checkPoolAndGetCenterPrice(address pool) external view returns (uint160);

    /// @dev Gets V3 factory address.
    function factoryV3() external view returns (address);
}

// Oracle V2 interface
interface IOracle {
    /// @dev Gets the current OLAS token price in 1e18 format.
    function getPrice() external view returns (uint256);

    /// @dev Validates price according to slippage.
    function validatePrice(uint256 slippage) external view returns (bool);

    /// @dev Updates the time-weighted average price.
    function updatePrice() external returns (bool);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Wrong array length.
error WrongArrayLength();

/// @dev Unauthorized pool address.
/// @param pool Pool address.
error UnauthorizedPool(address pool);

// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title BuyBackBurner - BuyBackBurner implementation contract
abstract contract BuyBackBurner {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event OraclesUpdated(address[] secondTokens, address[] oracles);
    event V3PoolStatusesUpdated(address[] pools, bool[] statuses);
    event BuyBack(address indexed secondToken, uint256 secondTokenAmount, uint256 olasAmount);
    event OraclePriceUpdated(address indexed oracle, address indexed sender);
    event TokenTransferred(address indexed destination, uint256 amount);

    // Version number
    string public constant VERSION = "0.2.0";
    // Code position in storage is keccak256("BUY_BACK_BURNER_PROXY") = "c6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19"
    bytes32 public constant BUY_BACK_BURNER_PROXY = 0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19;
    // L1 OLAS Burner address
    address public constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    // Max allowed price deviation for TWAP pool values (10%) in 1e18 format
    uint256 public constant MAX_ALLOWED_DEVIATION = 1e17;
    // Seconds ago to look back for TWAP pool values
    uint32 public constant SECONDS_AGO = 1800;

    // Contract owner
    address public owner;
    // OLAS token address
    address public olas;
    // Native token (ERC-20) address
    address public nativeToken;
    // Oracle address
    address public oracle;

    // Oracle max slippage for second token <=> OLAS
    uint256 public maxSlippage;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of account => activity counter
    mapping(address => uint256) public mapAccountActivities;

    // LiquidityManager address
    address public immutable liquidityManager;
    // Bridge2Burner address
    address public immutable bridge2Burner;
    // Treasury address
    address public immutable treasury;
    // Concentrated liquidity swap router address
    address public immutable swapRouter;

    // Map of second token address => whitelisted V2 oracle address
    mapping(address => address) public mapV2Oracles;
    // Map of V3 pool address => whitelisted status
    mapping(address => bool) public mapV3Pools;

    /// @dev BuyBackBurner constructor.
    /// @param _liquidityManager LiquidityManager address.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    /// @param _swapRouter Concentrated liquidity swap router address.
    constructor(address _liquidityManager, address _bridge2Burner, address _treasury, address _swapRouter) {
        // Check for zero address
        if (
            _liquidityManager == address(0) || _bridge2Burner == address(0) || _treasury == address(0)
                || _swapRouter == address(0)
        ) {
            revert ZeroAddress();
        }

        liquidityManager = _liquidityManager;
        bridge2Burner = _bridge2Burner;
        treasury = _treasury;
        swapRouter = _swapRouter;
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual;

    /// @dev Performs swap for OLAS on V2 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param poolOracle Pool oracle address.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, address poolOracle) internal virtual returns (uint256 olasAmount);

    /// @dev Performs swap for OLAS on V3 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, int24 feeTierOrTickSpacing)
        internal
        virtual
        returns (uint256 olasAmount);

    /// @dev Gets V3 pool based on factory, token addresses and fee tier or tick spacing.
    /// @param factory Factory address.
    /// @param tokens Token addresses.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return v3Pool V3 pool address.
    function getV3Pool(address factory, address[] memory tokens, int24 feeTierOrTickSpacing)
        public
        view
        virtual
        returns (address);

    /// @dev Buys OLAS on V2 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(address secondToken, uint256 secondTokenAmount) internal virtual returns (uint256 olasAmount) {
        // Get oracle address
        address poolOracle = mapV2Oracles[secondToken];

        // Check for zero address
        require(poolOracle != address(0), "Zero oracle address");

        // Apply slippage protection
        require(IOracle(poolOracle).validatePrice(maxSlippage), "Before swap slippage limit is breached");

        // Get current pool price
        uint256 previousPrice = IOracle(poolOracle).getPrice();

        // Perform swap to OLAS
        olasAmount = _performSwap(secondToken, secondTokenAmount, poolOracle);

        // Get current pool price
        uint256 tradePrice = IOracle(poolOracle).getPrice();

        // Validate against slippage thresholds
        uint256 lowerBound = (previousPrice * (100 - maxSlippage)) / 100;
        uint256 upperBound = (previousPrice * (100 + maxSlippage)) / 100;

        require(tradePrice >= lowerBound && tradePrice <= upperBound, "After swap slippage limit is breached");
    }

    /// @dev Buys OLAS on V3 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(address secondToken, uint256 secondTokenAmount, int24 feeTierOrTickSpacing)
        internal
        virtual
        returns (uint256 olasAmount)
    {
        address localOlas = olas;

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (secondToken > localOlas) ? (localOlas, secondToken) : (secondToken, localOlas);

        // Get factory from LiquidityManager
        // Actual factoryV3 is fetched from LiquiditiManager, since LiquiditiManager is proxy and factory might change
        address factoryV3 = ILiquidityManager(liquidityManager).factoryV3();

        // Get V3 pool from liquidity manager
        address pool = getV3Pool(factoryV3, tokens, feeTierOrTickSpacing);

        // Check for whitelisted pool address
        if (!mapV3Pools[pool]) {
            revert UnauthorizedPool(pool);
        }

        // Apply slippage protection
        ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);

        // Perform swap to OLAS
        olasAmount = _performSwap(secondToken, secondTokenAmount, feeTierOrTickSpacing);
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function initialize(bytes memory payload) external {
        // Check for already being initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
        _locked = 1;

        _initialize(payload);
    }

    /// @dev Changes the implementation contract address.
    /// @param newImplementation New implementation contract address.
    function changeImplementation(address newImplementation) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the implementation address
        assembly {
            sstore(BUY_BACK_BURNER_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Changes contract owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the ownership
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

    /// @dev Sets V2 oracle addresses for a specific V2-like full range pools based on second token.
    /// @param secondTokens Set of second tokens.
    /// @param oracles Set of corresponding oracle addresses.
    function setV2Oracles(address[] memory secondTokens, address[] memory oracles) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint256 numPools = secondTokens.length;
        
        // Check for array sizes
        if (numPools == 0 || numPools != oracles.length) {
            revert WrongArrayLength();
        }
        
        // Process data
        for (uint256 i = 0; i < numPools; ++i) {
            // Check for zero addresses
            if (secondTokens[i] == address(0) || oracles[i] == address(0)) {
                revert ZeroAddress();
            }

            mapV2Oracles[secondTokens[i]] = oracles[i];
        }

        emit OraclesUpdated(secondTokens, oracles);
    }

    /// @dev Sets V3 pool statuses.
    /// @param pools Set of V3 pools.
    /// @param statuses Set of corresponding pool statuses.
    function setV2Oracles(address[] memory pools, bool[] memory statuses) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint256 numPools = pools.length;

        // Check for array sizes
        if (numPools == 0 || numPools != statuses.length) {
            revert WrongArrayLength();
        }

        // Process data
        for (uint256 i = 0; i < numPools; ++i) {
            // Check for zero addresses
            if (pools[i] == address(0)) {
                revert ZeroAddress();
            }

            mapV3Pools[pools[i]] = statuses[i];
        }

        emit V3PoolStatusesUpdated(pools, statuses);
    }

    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @notice This is a legacy function for compatibility with one of apps, it accounts for UniswapV3 only.
    /// @param token0 Token0 address.
    /// @param token1 Token1 address.
    /// @param feeTier Fee tier.
    function checkPoolPrices(address token0, address token1, address uniV3PositionManager, uint24 feeTier)
        external
        view
    {
        // Get factory address
        address factory = IUniswapV3(uniV3PositionManager).factory();

        // Verify pool reserves before proceeding
        address pool = IUniswapV3(factory).getPool(token0, token1, feeTier);
        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Check pool via LiquidityManager contract
        ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);
    }

    /// @dev Buys OLAS on V2 DEX.
    /// @notice if secondTokenAmount is zero or above the balance, it will be adjusted to current second token balance.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Suggested second token amount.
    function buyBack(address secondToken, uint256 secondTokenAmount) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        address localSecondToken = secondToken;

        // Get secondToken balance
        uint256 balance = IERC20(localSecondToken).balanceOf(address(this));

        // Adjust second token amount, if needed
        if (secondTokenAmount == 0 || secondTokenAmount > balance) {
            secondTokenAmount = balance;
        }

        if (secondTokenAmount == 0) {
            revert ZeroValue();
        }

        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Buy OLAS
        uint256 olasAmount = _buyOLAS(secondToken, secondTokenAmount);

        emit BuyBack(localSecondToken, secondTokenAmount, olasAmount);

        // Get OLAS contract balance
        olasAmount = IERC20(olas).balanceOf(address(this));

        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        emit TokenTransferred(bridge2Burner, olasAmount);

        _locked = 1;
    }

    /// @dev Buys OLAS on V3 DEX.
    /// @notice if secondTokenAmount is zero or above the balance, it will be adjusted to current second token balance.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Suggested second token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    function buyBack(address secondToken, uint256 secondTokenAmount, int24 feeTierOrTickSpacing) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get token balance
        uint256 balance = IERC20(secondToken).balanceOf(address(this));

        // Adjust second token amount, if needed
        if (secondTokenAmount == 0 || secondTokenAmount > balance) {
            secondTokenAmount = balance;
        }

        if (secondTokenAmount == 0) {
            revert ZeroValue();
        }

        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Buy OLAS
        uint256 olasAmount = _buyOLAS(secondToken, secondTokenAmount, feeTierOrTickSpacing);

        emit BuyBack(secondToken, secondTokenAmount, olasAmount);

        // Get OLAS contract balance
        olasAmount = IERC20(olas).balanceOf(address(this));

        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        emit TokenTransferred(bridge2Burner, secondTokenAmount);

        _locked = 1;
    }

    /// @dev Triggers V2 oracle price update.
    /// @param poolOracle Pool oracle address.
    function updateOraclePrice(address poolOracle) external {
        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Update price
        bool success = IOracle(poolOracle).updatePrice();
        require(success, "Oracle price update failed");

        emit OraclePriceUpdated(poolOracle, msg.sender);
    }

    /// @dev Transfers specified token to treasury.
    /// @param token Token address.
    function transfer(address token) external {
        // Get token amount
        uint256 tokenAmount = IERC20(token).balanceOf(address(this));

        if (tokenAmount == 0) {
            revert ZeroValue();
        }

        address to = treasury;

        // Check if token address is OLAS
        if (token == olas) {
            // Transfer OLAS directly to bridge2Burner contract
            IERC20(olas).transfer(bridge2Burner, tokenAmount);

            // Correct to value
            to = bridge2Burner;
        } else {
            // Transfer token to treasury contract
            IERC20(token).transfer(treasury, tokenAmount);
        }

        emit TokenTransferred(to, tokenAmount);
    }
}
