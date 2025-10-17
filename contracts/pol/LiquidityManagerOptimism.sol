// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore, ZeroValue, ZeroAddress} from "./LiquidityManagerCore.sol";

/// @dev Expected token addresses do not match provided ones.
/// @param provided Provided token addresses.
/// @param expected Expected token addresses.
error WrongTokenAddresses(address[] provided, address[] expected);

/// @dev Oracle slippage limit is breached.
error SlippageLimitBreached();

interface IBalancerV2 {
    enum PoolSpecialization { GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN }
    enum ExitKind { EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /**
     * @dev Called by users to exit a Pool, which transfers tokens from the Pool's balance to `recipient`. This will
     * trigger custom Pool behavior, which will typically ask for something in return from `sender` - often tokenized
     * Pool shares. The amount of tokens that can be withdrawn is limited by the Pool's `cash` balance (see
     * `getPoolTokenInfo`).
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `tokens` and `minAmountsOut` arrays must have the same length, and each entry in these indicates the minimum
     * token amount to receive for each token contract. The amounts to send are decided by the Pool and not the Vault:
     * it just enforces these minimums.
     *
     * If exiting a Pool that holds WETH, it is possible to receive ETH directly: the Vault will do the unwrapping. To
     * enable this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead
     * of the WETH address. Note that it is not possible to combine ETH and WETH in the same exit.
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If receiving ETH however, the array must
     * be sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the
     * final `assets` array might not be sorted. Pools with no registered tokens cannot be exited.
     *
     * If `toInternalBalance` is true, the tokens will be deposited to `recipient`'s Internal Balance. Otherwise,
     * an ERC20 transfer will be performed. Note that ETH cannot be deposited to Internal Balance: attempting to
     * do so will trigger a revert.
     *
     * `minAmountsOut` is the minimum amount of tokens the user expects to get out of the Pool, for each token in the
     * `tokens` array. This array must match the Pool's registered tokens.
     *
     * This causes the Vault to call the `IBasePool.onExitPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares to return). This can be encoded in the `userData` argument, which is ignored by the Vault and
     * passed directly to the Pool's contract.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    /**
     * @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when *any* of
     * the tokens' `balances` changed.
     *
     * The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
     * Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
     *
     * If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
     * order as passed to `registerTokens`.
     *
     * Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
     * the amounts used by joins, exits and swaps. For a detailed breakdown of token balances, use `getPoolTokenInfo`
     * instead.
     */
    function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );

    /**
     * @dev Returns a Pool's contract address and specialization setting.
     */
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);
}

interface ICLFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

interface IOracle {
    /// @dev Validates price according to slippage.
    function validatePrice(uint256 slippage) external view returns (bool);
}

interface IToken {
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

interface ISlipstreamV3 {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// tick The current tick of the pool, i.e. according to the last tick transition that was run.
    /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96) if the price is on a tick
    /// boundary.
    /// observationIndex The index of the last oracle observation that was written,
    /// observationCardinality The current maximum number of observations stored in the pool,
    /// observationCardinalityNext The next maximum number of observations, to be updated when the observation.
    /// unlocked Whether the pool is currently locked to reentrancy
    function slot0()
    external
    view
    returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        bool unlocked
    );

    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title Liquidity Manager Optimism - Smart contract for OLAS core Liquidity Manager functionality on Optimism stack chains
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LiquidityManagerOptimism is LiquidityManagerCore {
    // Balancer vault address
    address public immutable balancerVault;
    // V2 pool related oracle address
    address public immutable oracleV2;
    // Bridge to Burner address
    address public immutable bridge2Burner;

    /// @dev LiquidityManagerOptimism constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _positionManagerV3 Uniswap V3 position manager address.
    /// @param _neighborhoodScanner Neighborhood ticks scanner.
    /// @param _observationCardinality Observation cardinality for fresh pools.
    /// @param _maxSlippage Max slippage for operations.
    /// @param _oracleV2 V2 pool related oracle address.
    /// @param _balancerVault Balancer vault address.
    /// @param _bridge2Burner Bridge to Burner address.
    constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        uint16 _maxSlippage,
        address _oracleV2,
        address _balancerVault,
        address _bridge2Burner
    ) LiquidityManagerCore(_olas, _treasury, _positionManagerV3, _neighborhoodScanner, _observationCardinality, _maxSlippage)
    {
        // Check for zero address
        if (_oracleV2 == address(0) || _balancerVault == address(0) || _bridge2Burner == address(0)) {
            revert ZeroAddress();
        }

        oracleV2 = _oracleV2;
        balancerVault = _balancerVault;
        bridge2Burner = _bridge2Burner;
    }

    /// @dev Transfer OLAS to Burner contract.
    /// @param amount OLAS amount.
    function _burn(uint256 amount) internal override {
        IToken(olas).transfer(bridge2Burner, amount);
    }

    /// @inheritdoc LiquidityManagerCore
    function _checkTokensAndRemoveLiquidityV2(address[] memory tokens, bytes32 v2Pool)
        internal virtual override returns (uint256[] memory amounts)
    {
        // Get pool address
        (address poolToken, ) = IBalancerV2(balancerVault).getPool(v2Pool);
        // Get this contract liquidity
        uint256 liquidity = IToken(poolToken).balanceOf(address(this));
        // Check for zero balance
        if (liquidity == 0) {
            revert ZeroValue();
        }

        address[] memory tokensInPool = new address[](2);
        // Get V2 pool tokens and amounts
        (tokensInPool, amounts, ) = IBalancerV2(balancerVault).getPoolTokens(v2Pool);

        // Check tokens
        if (tokensInPool[0] != tokens[0] || tokensInPool[1] != tokens[1]) {
            revert WrongTokenAddresses(tokens, tokensInPool);
        }

        // Check for zero balances
        if (amounts[0] == 0 || amounts[1] == 0) {
            revert ZeroValue();
        }

        // Apply slippage protection via V2 oracle: transform BPS into % as required by the function
        if (!IOracle(oracleV2).validatePrice(maxSlippage / 100)) {
            revert SlippageLimitBreached();
        }

        // Price is validated with desired slippage, and thus min out amounts can be set to 1
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        IBalancerV2.ExitPoolRequest memory request = IBalancerV2.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(IBalancerV2.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, liquidity),
            toInternalBalance: false
        });

        // Remove liquidity
        IBalancerV2(balancerVault).exitPool(v2Pool, address(this), payable(address(this)), request);
    }

    /// @inheritdoc LiquidityManagerCore
    function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 tickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual override returns (uint256 positionId, uint128 liquidity, uint256[] memory)
    {
        // Params for minting
        ISlipstreamV3.MintParams memory params = ISlipstreamV3.MintParams({
            token0: tokens[0],
            token1: tokens[1],
            tickSpacing: tickSpacing,
            tickLower: ticks[0],
            tickUpper: ticks[1],
            amount0Desired: amounts[0],
            amount1Desired: amounts[1],
            amount0Min: amountsMin[0],
            amount1Min: amountsMin[1],
            recipient: address(this),
            deadline: block.timestamp,
            sqrtPriceX96: centerSqrtPriceX96
        });

        // Mint position
        (positionId, liquidity, amounts[0], amounts[1]) = ISlipstreamV3(positionManagerV3).mint(params);

        return (positionId, liquidity, amounts);
    }

    /// @dev Gets tick spacing according to fee tier or tick spacing directly.
    /// @param tickSpacing Tick spacing.
    function _feeAmountTickSpacing(int24 tickSpacing) internal view virtual override returns (int24) {
        return tickSpacing;
    }

    /// @inheritdoc LiquidityManagerCore
    function _getPriceAndObservationIndexFromSlot0(address pool)
        internal view virtual override returns (uint160 sqrtPriceX96, uint16 observationIndex)
    {
        // Get current pool reserves and observation index
        (sqrtPriceX96, , observationIndex, , , ) = ISlipstreamV3(pool).slot0();
    }

    /// @dev Gets V3 pool based on token addresses and tick spacing.
    /// @param tokens Token addresses.
    /// @param tickSpacing Tick spacing.
    /// @return V3 pool address.
    function _getV3Pool(address[] memory tokens, int24 tickSpacing)
        internal view virtual override returns (address)
    {
        return ICLFactory(factoryV3).getPool(tokens[0], tokens[1], tickSpacing);
    }
}
