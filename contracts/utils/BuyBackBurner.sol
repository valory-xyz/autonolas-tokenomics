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
    event BuyBack(uint256 olasAmount);
    event OraclePriceUpdated(address indexed oracle, address indexed sender);

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

    // Bridge2Burner address
    address public immutable bridge2Burner;

    /// @dev BuyBackBurner constructor.
    /// @param _bridge2Burner Bridge2Burner address.
    constructor(address _bridge2Burner) {
        // Check for zero address
        if (_bridge2Burner == address(0)) {
            revert ZeroAddress();
        }

        bridge2Burner = _bridge2Burner;
    }

    /// @dev Buys OLAS on DEX.
    /// @param nativeTokenAmount Suggested native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(uint256 nativeTokenAmount) internal virtual returns (uint256 olasAmount) {
        // Apply slippage protection
        require(IOracle(oracle).validatePrice(maxSlippage), "Before swap slippage limit is breached");

        // Get current pool price
        uint256 previousPrice = IOracle(oracle).getPrice();

        olasAmount = _performSwap(nativeTokenAmount);

        // Get current pool price
        uint256 tradePrice = IOracle(oracle).getPrice();

        // Validate against slippage thresholds
        uint256 lowerBound = (previousPrice * (100 - maxSlippage)) / 100;
        uint256 upperBound = (previousPrice * (100 + maxSlippage)) / 100;

        require(tradePrice >= lowerBound && tradePrice <= upperBound, "After swap slippage limit is breached");
    }

    /// @dev Gets TWAP price via the built-in Uniswap V3 oracle.
    /// @param pool Pool address.
    /// @return price Calculated price.
    function _getTwapFromOracle(address pool) internal view returns (uint256 price) {
        // Query the pool for the current and historical tick
        uint32[] memory secondsAgos = new uint32[](2);
        // Start of the period
        secondsAgos[0] = SECONDS_AGO;

        // Fetch the tick cumulative values from the pool
        (int56[] memory tickCumulatives, ) = IUniswapV3(pool).observe(secondsAgos);

        // Calculate the average tick over the time period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 averageTick = int24(tickCumulativeDelta / int56(int32(SECONDS_AGO)));

        // Convert the average tick to sqrtPriceX96
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);

        // Calculate the price using the sqrtPriceX96
        // Max result is uint160 * uint160 == uint320, not to overflow: 320 - 256 = 64 (2^64)
        price = FixedPointMathLib.mulDivDown(uint256(sqrtPriceX96), uint256(sqrtPriceX96), (1 << 64));
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual;

    /// @dev Performs swap for OLAS on DEX.
    /// @param nativeTokenAmount Native token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(uint256 nativeTokenAmount) internal virtual returns (uint256 olasAmount);

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
    /// @param token0 Token0 address.
    /// @param token1 Token1 address.
    /// @param fee Fee tier.
    function checkPoolPrices(
        address token0,
        address token1,
        address uniV3PositionManager,
        uint24 fee
    ) external view {
        // Get factory address
        address factory = IUniswapV3(uniV3PositionManager).factory();

        // Verify pool reserves before proceeding
        address pool = IUniswapV3(factory).getPool(token0, token1, fee);
        // Check for zero address
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Get current pool reserves and observation index
        (uint160 sqrtPriceX96, , uint16 observationIndex, , , , ) = IUniswapV3(pool).slot0();

        // Check if the pool has sufficient observation history
        (uint32 oldestTimestamp, , , ) = IUniswapV3(pool).observations(observationIndex);
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return;
        }

        // Check TWAP or historical data
        uint256 twapPrice = _getTwapFromOracle(pool);
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

    /// @dev Buys OLAS on DEX.
    /// @notice if nativeTokenAmount is zero or above the balance, it will be adjusted to current native token balance.
    /// @param nativeTokenAmount Suggested native token amount.
    function buyBack(uint256 nativeTokenAmount) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get nativeToken balance
        uint256 balance = IERC20(nativeToken).balanceOf(address(this));

        // Adjust native token amount, if needed
        if (nativeTokenAmount == 0 || nativeTokenAmount > balance) {
            nativeTokenAmount = balance;
        }
        require(nativeTokenAmount > 0, "Insufficient native token amount");

        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Buy OLAS
        uint256 olasAmount = _buyOLAS(nativeTokenAmount);

        emit BuyBack(olasAmount);

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

    /// @dev Transfers OLAS balance to Bridge2Burn contract.
    function bridge2Burn() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS balance
        uint256 olasAmount = IERC20(olas).balanceOf(address(this));
        // Check for zero value
        if (olasAmount == 0) {
            revert ZeroValue();
        }

        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        _locked = 1;
    }
}