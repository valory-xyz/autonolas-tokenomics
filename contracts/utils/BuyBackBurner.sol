// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title BuyBackBurner - BuyBackBurner implementation contract
abstract contract BuyBackBurner {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event OracleUpdated(address indexed oracle);
    event BuyBack(address indexed token, uint256 tokenAmount, uint256 olasAmount);
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

    // Oracle max slippage for ERC-20 native token <=> OLAS
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
    // Treasury address
    address public immutable routerV3;

    /// @dev BuyBackBurner constructor.
    /// @param _liquidityManager LiquidityManager address.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    /// @param _routerV3 Router V3 address.
    constructor(address _liquidityManager, address _bridge2Burner, address _treasury, address _routerV3) {
        // Check for zero address
        if (
            _liquidityManager == address(0) || _bridge2Burner == address(0) || _treasury == address(0)
                || _routerV3 == address(0)
        ) {
            revert ZeroAddress();
        }

        liquidityManager = _liquidityManager;
        bridge2Burner = _bridge2Burner;
        treasury = _treasury;
        routerV3 = _routerV3;
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual;

    /// @dev Performs swap for OLAS on V2 DEX.
    /// @param nativeTokenAmount Native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(uint256 nativeTokenAmount) internal virtual returns (uint256 olasAmount);

    /// @dev Performs swap for OLAS on V3 DEX.
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address token, uint256 tokenAmount, int24 feeTierOrTickSpacing)
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
    /// @param nativeTokenAmount Native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(uint256 nativeTokenAmount) internal virtual returns (uint256 olasAmount) {
        // Apply slippage protection
        require(IOracle(oracle).validatePrice(maxSlippage), "Before swap slippage limit is breached");

        // Get current pool price
        uint256 previousPrice = IOracle(oracle).getPrice();

        // Perform swap to OLAS
        olasAmount = _performSwap(nativeTokenAmount);

        // Get current pool price
        uint256 tradePrice = IOracle(oracle).getPrice();

        // Validate against slippage thresholds
        uint256 lowerBound = (previousPrice * (100 - maxSlippage)) / 100;
        uint256 upperBound = (previousPrice * (100 + maxSlippage)) / 100;

        require(tradePrice >= lowerBound && tradePrice <= upperBound, "After swap slippage limit is breached");
    }

    /// @dev Buys OLAS on V3 DEX.
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(address token, uint256 tokenAmount, int24 feeTierOrTickSpacing)
        internal
        virtual
        returns (uint256 olasAmount)
    {
        address localOlas = olas;

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (token > localOlas) ? (localOlas, token) : (token, localOlas);

        // Get factory from LiquidityManager
        address factoryV3 = ILiquidityManager(liquidityManager).factoryV3();

        // Get V3 pool from liquidity manager
        address pool = getV3Pool(factoryV3, tokens, feeTierOrTickSpacing);

        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Apply slippage protection
        ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);

        // Perform swap to OLAS
        olasAmount = _performSwap(token, tokenAmount, feeTierOrTickSpacing);
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

    /// @dev Changes contract oracle address.
    /// @param newOracle Address of a new oracle.
    function changeOracle(address newOracle) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOracle == address(0)) {
            revert ZeroAddress();
        }

        oracle = newOracle;
        emit OracleUpdated(newOracle);
    }

    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @notice This is a legacy function for compatibility with one of apps.
    /// @param token0 Token0 address.
    /// @param token1 Token1 address.
    /// @param fee Fee tier.
    function checkPoolPrices(address token0, address token1, address uniV3PositionManager, uint24 fee) external view {
        // Get factory address
        address factory = IUniswapV3(uniV3PositionManager).factory();

        // Verify pool reserves before proceeding
        address pool = IUniswapV3(factory).getPool(token0, token1, fee);
        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Check pool via LiquidityManager contract
        ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);
    }

    /// @dev Buys OLAS on V2 DEX.
    /// @notice if nativeTokenAmount is zero or above the balance, it will be adjusted to current native token balance.
    /// @param nativeTokenAmount Suggested native token amount.
    function buyBack(uint256 nativeTokenAmount) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        address localNativeToken = nativeToken;

        // Get nativeToken balance
        uint256 balance = IERC20(localNativeToken).balanceOf(address(this));

        // Adjust native token amount, if needed
        if (nativeTokenAmount == 0 || nativeTokenAmount > balance) {
            nativeTokenAmount = balance;
        }

        if (nativeTokenAmount == 0) {
            revert ZeroValue();
        }

        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Buy OLAS
        uint256 olasAmount = _buyOLAS(nativeTokenAmount);

        emit BuyBack(localNativeToken, nativeTokenAmount, olasAmount);

        // Get OLAS contract balance
        olasAmount = IERC20(olas).balanceOf(address(this));

        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        emit TokenTransferred(bridge2Burner, olasAmount);

        _locked = 1;
    }

    /// @dev Buys OLAS on V3 DEX.
    /// @notice if tokenAmount is zero or above the balance, it will be adjusted to current native token balance.
    /// @param token Token address.
    /// @param tokenAmount Suggested token amount.
    /// @param feeTierOrTickSpacing Fee tier or tick spacing.
    function buyBack(address token, uint256 tokenAmount, int24 feeTierOrTickSpacing) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get token balance
        uint256 balance = IERC20(token).balanceOf(address(this));

        // Adjust native token amount, if needed
        if (tokenAmount == 0 || tokenAmount > balance) {
            tokenAmount = balance;
        }

        if (tokenAmount == 0) {
            revert ZeroValue();
        }

        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Buy OLAS
        uint256 olasAmount = _buyOLAS(token, tokenAmount, feeTierOrTickSpacing);

        emit BuyBack(token, tokenAmount, olasAmount);

        // Get OLAS contract balance
        olasAmount = IERC20(olas).balanceOf(address(this));

        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        emit TokenTransferred(bridge2Burner, tokenAmount);

        _locked = 1;
    }

    /// @dev Triggers oracle price update.
    function updateOraclePrice() external {
        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Update price
        bool success = IOracle(oracle).updatePrice();
        require(success, "Oracle price update failed");

        emit OraclePriceUpdated(oracle, msg.sender);
    }

    /// @dev Transfers specified token to treasury.
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
