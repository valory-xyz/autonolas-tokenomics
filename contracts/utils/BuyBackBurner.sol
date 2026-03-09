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
    /// @dev Gets the current TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256);

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

/// @dev Unauthorized token address.
/// @param token Token address.
error UnauthorizedToken(address token);

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
    event FundsReceived(address indexed sender, uint256 amount);

    // Version number
    string public constant VERSION = "0.3.0";
    // Code position in storage is keccak256("BUY_BACK_BURNER_PROXY") = "c6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19"
    bytes32 public constant BUY_BACK_BURNER_PROXY = 0xc6d7bd4bd971fa336816fe30b665cc6caccce8b123cc8ea692d132f342c4fc19;
    // L1 OLAS Burner address
    address public constant OLAS_BURNER = 0x51eb65012ca5cEB07320c497F4151aC207FEa4E0;
    // Max BPS value
    uint256 public constant MAX_BPS = 10_000;
    // Max allowed price deviation for TWAP pool values (10%) in 1e18 format
    uint256 public constant MAX_ALLOWED_DEVIATION = 1e17;
    // Seconds ago to look back for TWAP pool values
    uint32 public constant SECONDS_AGO = 1800;

    // Contract owner
    address public owner;
    // OLAS token address
    address public olas;
    // Deprecated (proxy legacy): Native token (ERC-20) address
    address public nativeToken;
    // Deprecated (proxy legacy): Oracle address
    address public oracle;

    // Oracle max slippage for second token <=> OLAS
    uint256 public maxSlippage;
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Map of account => activity counter
    mapping(address => uint256) public mapAccountActivities;

    // Bridge2Burner address
    address public immutable bridge2Burner;
    // Treasury address
    address public immutable treasury;

    // Map of second token address => whitelisted V2 oracle address
    mapping(address => address) public mapV2Oracles;

    /// @dev BuyBackBurner constructor.
    /// @param _bridge2Burner Bridge2Burner address.
    /// @param _treasury Treasury address.
    constructor(address _bridge2Burner, address _treasury) {
        // Check for zero address
        if (_bridge2Burner == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }

        bridge2Burner = _bridge2Burner;
        treasury = _treasury;
    }

    /// @dev BuyBackBurner initializer.
    /// @param payload Initializer payload.
    function _initialize(bytes memory payload) internal virtual;

    /// @dev Performs swap for OLAS on V2 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param amountOutMin Minimum acceptable OLAS output.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(address secondToken, uint256 secondTokenAmount, uint256 amountOutMin)
        internal
        virtual
        returns (uint256 olasAmount);

    /// @dev Buys OLAS on V2 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(address secondToken, uint256 secondTokenAmount) internal virtual returns (uint256 olasAmount) {
        // Get oracle address
        address poolOracle = mapV2Oracles[secondToken];

        // Check for zero address
        require(poolOracle != address(0), "Zero oracle address");

        // Get TWAP price (OLAS per secondToken) in 1e18 format
        uint256 twap = IOracle(poolOracle).getTWAP();

        // Compute minimum acceptable OLAS output with slippage tolerance
        uint256 amountOutMin = (secondTokenAmount * twap * (MAX_BPS - maxSlippage)) / (MAX_BPS * 1e18);

        // Perform swap to OLAS with amountOutMin enforced by the router
        olasAmount = _performSwap(secondToken, secondTokenAmount, amountOutMin);
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
            // Check for zero address
            if (secondTokens[i] == address(0)) {
                revert ZeroAddress();
            }

            // Check for second token to not be OLAS
            if (secondTokens[i] == olas) {
                revert UnauthorizedToken(secondTokens[i]);
            }

            mapV2Oracles[secondTokens[i]] = oracles[i];
        }

        emit OraclesUpdated(secondTokens, oracles);
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

    /// @dev Triggers V2 oracle price update.
    /// @param secondToken Second token address.
    function updateOraclePrice(address secondToken) external {
        // Record msg.sender activity
        mapAccountActivities[msg.sender]++;

        // Get oracle address
        address poolOracle = mapV2Oracles[secondToken];

        // Check for zero address
        require(poolOracle != address(0), "Zero oracle address");

        // Update price
        bool success = IOracle(poolOracle).updatePrice();
        require(success, "Oracle price update failed");

        emit OraclePriceUpdated(poolOracle, msg.sender);
    }

    /// @dev Transfers specified token to treasury.
    /// @param token Token address.
    function transfer(address token) external {
        // Check that token is not set for swapping into OLAS
        if (mapV2Oracles[token] != address(0)) {
            revert UnauthorizedToken(token);
        }

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

    /// @dev Receives native funds.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}
