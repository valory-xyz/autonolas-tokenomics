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

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

// @dev Reentrancy guard.
error ReentrancyGuard();

/// @dev Token transfer failed.
/// @param token Token address.
/// @param to Address to transfer to.
/// @param amount Token amount.
error TransferFailed(address token, address to, uint256 amount);

/// @dev Caller-supplied deadline has elapsed.
/// @param deadline Supplied deadline (unix seconds).
/// @param blockTimestamp Current block timestamp.
error DeadlineExpired(uint256 deadline, uint256 blockTimestamp);

/// @dev V3 path is disabled: liquidityManager and/or swapRouter immutable was set to zero at deployment.
///      Re-deploy the implementation with both addresses populated and call changeImplementation.
error V3PathDisabled();

/// @title BuyBackBurner - BuyBackBurner implementation contract
abstract contract BuyBackBurner {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event OraclesUpdated(address[] secondTokens, address[] oracles);
    event V3PoolsUpdated(address[] secondTokens, address[] pools);
    event BuyBack(address indexed secondToken, uint256 secondTokenAmount, uint256 olasAmount);
    event OraclePriceUpdated(address indexed oracle, address indexed sender);
    event TokenTransferred(address indexed destination, uint256 amount);
    event MaxSlippagesUpdated(address[] secondTokens, uint256[] maxSlippages);
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

    // Deprecated (proxy legacy): global oracle max slippage
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
    // Map of second token address => whitelisted V3 pool address (V3 swap path).
    // Keyed by secondToken — same shape as mapV2Oracles — so transfer() can block V3-eligible secondTokens
    // in O(1) without needing a separate fee tier / tick spacing argument from the caller.
    mapping(address => address) public mapV3Pools;
    // Map of second token address => max slippage in BPS
    mapping(address => uint256) public mapTokenMaxSlippages;

    /// @dev BuyBackBurner constructor.
    /// @notice `_liquidityManager` and `_swapRouter` are optional — pass `address(0)` to deploy
    ///         an implementation with the V3 path disabled. Every V3-touching function then reverts
    ///         with `V3PathDisabled`. To enable V3 later, deploy a new implementation with both
    ///         addresses populated and call `changeImplementation` on the proxy.
    /// @param _liquidityManager LiquidityManager address (set to zero to disable V3).
    /// @param _bridge2Burner Bridge2Burner address (required).
    /// @param _treasury Treasury address (required).
    /// @param _swapRouter Concentrated liquidity swap router address (set to zero to disable V3).
    constructor(address _liquidityManager, address _bridge2Burner, address _treasury, address _swapRouter) {
        // Bridge2Burner and treasury are required on every chain regardless of V3 availability.
        if (_bridge2Burner == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }

        liquidityManager = _liquidityManager;
        bridge2Burner = _bridge2Burner;
        treasury = _treasury;
        swapRouter = _swapRouter;
    }

    /// @dev Reverts with V3PathDisabled when either V3 immutable is zero. Guards every
    ///      V3-touching function (_buyOLASV3 inside buyBack auto-routing, setV3Pools).
    function _requireV3Enabled() internal view {
        if (liquidityManager == address(0) || swapRouter == address(0)) {
            revert V3PathDisabled();
        }
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

    /// @dev Performs swap for OLAS on V3 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @param pool V3 pool address — child reads its own fee tier or tick spacing from this address
    ///        to populate the swap router's input.
    /// @param amountOutMin Minimum acceptable OLAS output.
    /// @return olasAmount Obtained OLAS amount.
    function _performSwap(
        address secondToken,
        uint256 secondTokenAmount,
        address pool,
        uint256 amountOutMin
    ) internal virtual returns (uint256 olasAmount);

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

    /// @dev Reads the V3 pool's fee tier (Uniswap V3) or tick spacing (Slipstream).
    ///      Used at setter time to verify the pool is canonical with respect to the configured factory.
    /// @param pool V3 pool address.
    /// @return Fee tier or tick spacing as int24.
    function _readPoolFeeOrTickSpacing(address pool) internal view virtual returns (int24);

    /// @dev Buys OLAS on V2 DEX.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLAS(address secondToken, uint256 secondTokenAmount) internal virtual returns (uint256 olasAmount) {
        // Get oracle address
        address poolOracle = mapV2Oracles[secondToken];

        // Check for zero address
        require(poolOracle != address(0), "Zero oracle address");

        // Pull a fresh TWAP observation if the rate-limit window has elapsed. The oracle returns false
        // (without reverting) when called inside the window, so back-to-back buyBack calls are not DoSed.
        IOracle(poolOracle).updatePrice();

        // Get TWAP price (OLAS per secondToken) in 1e18 format
        uint256 twap = IOracle(poolOracle).getTWAP();

        // Compute minimum acceptable OLAS output with per-token slippage tolerance
        uint256 tokenMaxSlippage = mapTokenMaxSlippages[secondToken];
        uint256 amountOutMin = (secondTokenAmount * twap * (MAX_BPS - tokenMaxSlippage)) / (MAX_BPS * 1e18);

        // Perform swap to OLAS with amountOutMin enforced by the router
        olasAmount = _performSwap(secondToken, secondTokenAmount, amountOutMin);
    }

    /// @dev Buys OLAS on V3 DEX. Pool is resolved from `mapV3Pools[secondToken]`; fee tier / tick spacing
    ///      is read from the pool at swap time.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Second token amount.
    /// @return olasAmount Obtained OLAS amount.
    function _buyOLASV3(address secondToken, uint256 secondTokenAmount) internal virtual returns (uint256 olasAmount) {
        // V3 path requires both liquidityManager and swapRouter to be set at deployment
        _requireV3Enabled();

        address pool = mapV3Pools[secondToken];

        // No V3 pool configured for this secondToken
        if (pool == address(0)) {
            revert UnauthorizedToken(secondToken);
        }

        // Apply TWAP-based deviation guard and capture the TWAP-derived sqrt price
        uint160 centerSqrtPriceX96 = ILiquidityManager(liquidityManager).checkPoolAndGetCenterPrice(pool);

        address localOlas = olas;

        // Determine OLAS's position in the canonical (token0, token1) ordering for the price-branch logic.
        // The pool is guaranteed canonical at config time (setV3Pools enforces factory ancestry), so the
        // ordering implied by `secondToken > localOlas` matches the pool's actual token0/token1.
        bool olasIsToken1 = (secondToken < localOlas);

        // Derive the TWAP-implied OLAS quote for secondTokenAmount.
        // Uniswap V3 pools encode price(token0 → token1) = (sqrtPriceX96 / 2^96)^2. Compute
        // priceX128 = sqrtPriceX96^2 / 2^64 to stay within uint256, then:
        //   olas == token1: olasQuote = secondTokenAmount * priceX128 / 2^128
        //   olas == token0: olasQuote = secondTokenAmount * 2^128 / priceX128
        uint256 priceX128 =
            FixedPointMathLib.mulDivDown(uint256(centerSqrtPriceX96), uint256(centerSqrtPriceX96), 1 << 64);
        uint256 olasQuote = olasIsToken1
            ? FixedPointMathLib.mulDivDown(secondTokenAmount, priceX128, 1 << 128)
            : FixedPointMathLib.mulDivDown(secondTokenAmount, 1 << 128, priceX128);

        // Apply per-token slippage tolerance (unset slippage → amountOutMin == olasQuote → DEX reverts)
        uint256 amountOutMin =
            FixedPointMathLib.mulDivDown(olasQuote, MAX_BPS - mapTokenMaxSlippages[secondToken], MAX_BPS);

        // Perform swap to OLAS with amountOutMin enforced by the router. The child reads the swap-router-
        // facing fee tier / tick spacing from `pool` itself (canonical at config time).
        olasAmount = _performSwap(secondToken, secondTokenAmount, pool, amountOutMin);
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
    /// @notice Setting oracles[i] = address(0) removes the oracle mapping for secondTokens[i],
    ///         which disables buyBack() for that token and enables transfer() to treasury instead.
    /// @param secondTokens Set of second tokens.
    /// @param oracles Set of corresponding oracle addresses (address(0) to remove).
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

    /// @dev Sets V3 pool addresses for given second tokens. Mirrors `setV2Oracles` — same shape,
    ///      same key, same delete-via-zero semantic.
    /// @notice Setting pools[i] = address(0) clears the V3 swap path for secondTokens[i] and re-enables
    ///         transfer() to sweep that token to treasury. Each non-zero pool is verified to be canonical
    ///         under the configured factory: factoryV3.getPool(secondToken, OLAS, pool's fee/tickSpacing)
    ///         must equal the supplied pool. This closes the I-01 admin-trust surface (a non-canonical
    ///         pool would let the TWAP guard read from one pool while the swap routes through another).
    /// @param secondTokens Set of second tokens.
    /// @param pools Set of corresponding V3 pool addresses (address(0) to remove).
    function setV3Pools(address[] memory secondTokens, address[] memory pools) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Configuring V3 pools is pointless when the V3 path is disabled
        _requireV3Enabled();

        uint256 numTokens = secondTokens.length;

        // Check for array sizes
        if (numTokens == 0 || numTokens != pools.length) {
            revert WrongArrayLength();
        }

        address localOlas = olas;
        address factoryV3 = ILiquidityManager(liquidityManager).factoryV3();

        // Process data
        for (uint256 i = 0; i < numTokens; ++i) {
            // Check for zero address
            if (secondTokens[i] == address(0)) {
                revert ZeroAddress();
            }

            // Check for second token to not be OLAS
            if (secondTokens[i] == localOlas) {
                revert UnauthorizedToken(secondTokens[i]);
            }

            address pool = pools[i];
            if (pool != address(0)) {
                // Verify the pool is canonical: factory.getPool(secondToken, OLAS, pool's fee or tick spacing) == pool.
                // Skipping this would let an admin-supplied non-canonical address divert the V3 TWAP read
                // (since the swap router resolves to a different pool from the same fee tier).
                address[] memory tokens = new address[](2);
                (tokens[0], tokens[1]) = (secondTokens[i] > localOlas)
                    ? (localOlas, secondTokens[i])
                    : (secondTokens[i], localOlas);
                int24 feeOrSpacing = _readPoolFeeOrTickSpacing(pool);
                if (getV3Pool(factoryV3, tokens, feeOrSpacing) != pool) {
                    revert UnauthorizedPool(pool);
                }
            }

            mapV3Pools[secondTokens[i]] = pool;
        }

        emit V3PoolsUpdated(secondTokens, pools);
    }

    /// @dev Checks pool prices via Uniswap V3 built-in oracle.
    /// @notice This is a legacy read-only diagnostic helper for compatibility with one of apps; it accounts for
    ///         UniswapV3 only. The caller supplies `uniV3PositionManager` and this function does NOT verify that
    ///         it is the canonical one — a fake manager can route to any factory/pool of the caller's choice, so
    ///         its result must NOT be relied on by any trust-critical flow. Internal swap paths use the pinned
    ///         `liquidityManager.factoryV3()` instead (see `_buyOLAS` V3 branch). Do not wire this helper into
    ///         keeper scripts or upgrade automation.
    /// @param token0 Token0 address.
    /// @param token1 Token1 address.
    /// @param uniV3PositionManager Uniswap V3 position manager address (caller-supplied; untrusted).
    /// @param feeTier Fee tier.
    function checkPoolPrices(address token0, address token1, address uniV3PositionManager, uint24 feeTier)
        external
        view
    {
        // checkPoolPrices delegates to liquidityManager; swapRouter is not read here
        if (liquidityManager == address(0)) {
            revert V3PathDisabled();
        }

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

    /// @dev Sets per-token max slippage values in BPS.
    /// @param secondTokens Set of second tokens.
    /// @param maxSlippages Set of corresponding max slippage values in BPS.
    function setMaxSlippages(address[] memory secondTokens, uint256[] memory maxSlippages) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint256 numTokens = secondTokens.length;

        // Check for array sizes
        if (numTokens == 0 || numTokens != maxSlippages.length) {
            revert WrongArrayLength();
        }

        // Process data
        for (uint256 i = 0; i < numTokens; ++i) {
            // Check for zero address
            if (secondTokens[i] == address(0)) {
                revert ZeroAddress();
            }

            // Check for zero value
            if (maxSlippages[i] == 0) {
                revert ZeroValue();
            }

            // Check for overflow
            if (maxSlippages[i] > MAX_BPS) {
                revert Overflow(maxSlippages[i], MAX_BPS);
            }

            mapTokenMaxSlippages[secondTokens[i]] = maxSlippages[i];
        }

        emit MaxSlippagesUpdated(secondTokens, maxSlippages);
    }

    /// @dev Buys OLAS for `secondToken`. The swap path is selected automatically:
    ///      - if `mapV3Pools[secondToken] != 0` → V3 path (pool & fee/tickSpacing read from storage)
    ///      - else if `mapV2Oracles[secondToken] != 0` → V2 path
    ///      - else revert
    ///      The previous V3 overload `buyBack(address, uint256, int24, uint256)` is removed; the int24
    ///      argument is no longer needed because the pool itself encodes the fee tier / tick spacing.
    /// @notice If secondTokenAmount is zero or above the balance, it will be adjusted to current second token balance.
    /// @param secondToken Second token address.
    /// @param secondTokenAmount Suggested second token amount.
    /// @param deadline Unix timestamp after which the call reverts (0 disables the check).
    function buyBack(address secondToken, uint256 secondTokenAmount, uint256 deadline) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Deadline guard against stale mempool execution; 0 opts out for callers that don't need it
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired(deadline, block.timestamp);
        }

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

        // Auto-route: V3 if the secondToken has a configured V3 pool, else V2.
        // V3 takes precedence — once an operator points mapV3Pools[token] at a pool, that's the active path
        // for the token. To switch back to V2, clear the V3 entry via setV3Pools(token, address(0)).
        uint256 olasAmount;
        if (mapV3Pools[secondToken] != address(0)) {
            olasAmount = _buyOLASV3(secondToken, secondTokenAmount);
        } else {
            olasAmount = _buyOLAS(secondToken, secondTokenAmount);
        }

        emit BuyBack(localSecondToken, secondTokenAmount, olasAmount);

        // Get OLAS contract balance
        olasAmount = IERC20(olas).balanceOf(address(this));

        // Transfer OLAS to bridge2Burner contract
        bool success = IERC20(olas).transfer(bridge2Burner, olasAmount);
        if (!success) {
            revert TransferFailed(olas, bridge2Burner, olasAmount);
        }

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
    /// @notice If a non-standard token (e.g. USDT, which returns void instead of bool) accumulates in the contract,
    ///         the transfer() call on line 343 will revert because Solidity's IERC20.transfer() ABI-decodes a bool
    ///         return value. To support such tokens, use SafeERC20.safeTransfer() or handle the return data manually.
    /// @param token Token address.
    function transfer(address token) external {
        // Check that token is not authorized for either swap path. mapV3Pools is only populated via
        // setV3Pools, which calls _requireV3Enabled() — so when V3 is disabled at deployment, mapV3Pools
        // is necessarily empty and this V3 leg is harmlessly always-false. No explicit liquidityManager
        // guard is needed here. Closes the L-06 griefing surface where an external caller could otherwise
        // front-run buyBack and divert a V3-eligible secondToken to treasury.
        if (mapV2Oracles[token] != address(0) || mapV3Pools[token] != address(0)) {
            revert UnauthorizedToken(token);
        }

        // Get token amount
        uint256 tokenAmount = IERC20(token).balanceOf(address(this));

        if (tokenAmount == 0) {
            revert ZeroValue();
        }

        address to = treasury;

        // Check if token address is OLAS
        bool success;
        if (token == olas) {
            // Transfer OLAS directly to bridge2Burner contract
            success = IERC20(olas).transfer(bridge2Burner, tokenAmount);
            if (!success) {
                revert TransferFailed(olas, bridge2Burner, tokenAmount);
            }

            // Correct to value
            to = bridge2Burner;
        } else {
            // Transfer token to treasury contract
            success = IERC20(token).transfer(treasury, tokenAmount);
            if (!success) {
                revert TransferFailed(token, treasury, tokenAmount);
            }
        }

        emit TokenTransferred(to, tokenAmount);
    }

    /// @dev Receives native funds.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}
