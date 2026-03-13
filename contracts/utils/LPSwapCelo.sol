// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

// ERC20 token interface
interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

// Uniswap V2 pair interface
interface IUniswapV2Pair {
    function totalSupply() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

// Uniswap V2 Router interface
interface IUniswapV2Router {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

// Oracle interface
interface IOracle {
    /// @dev Gets the current TWAP price in 1e18 format (OLAS per secondToken).
    function getTWAP() external view returns (uint256);
}

// L2 Standard Bridge interface (OP-stack)
interface IL2StandardBridge {
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/L2/L2StandardBridge.sol#L121
    /// @dev Initiates a withdrawal from L2 to L1 to a target account on L1.
    /// @param _l2Token Address of the L2 token to withdraw.
    /// @param _to Recipient account on L1.
    /// @param _amount Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData Extra data attached to the withdrawal.
    function withdrawTo(address _l2Token, address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData)
        external;
}

// Wormhole Token Bridge interface
interface IWormholeTokenBridge {
    /// @dev Transfers tokens via Wormhole bridge.
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param recipientChain Wormhole chain Id of the recipient chain.
    /// @param recipient Recipient address in bytes32 format.
    /// @param arbiterFee Arbiter fee (typically 0).
    /// @param nonce Nonce value.
    /// @return sequence Wormhole sequence number.
    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Token transfer failed.
/// @param token Token address.
/// @param from Sender address.
/// @param to Recipient address.
/// @param amount Token amount.
error TransferFailed(address token, address from, address to, uint256 amount);

/// @title LPSwapCelo - Smart contract for swapping whOLAS-CELO liquidity to OLAS-CELO liquidity on Celo
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract LPSwapCelo {
    event LiquiditySwapped(uint256 whOlasAmount, uint256 celoAmount, uint256 olasAmount, uint256 newLiquidity);
    event OLASBridgedToL1(uint256 amount);
    event WhOLASBridgedToL1(uint256 amount);

    // Version number
    string public constant VERSION = "0.1.0";
    // Max BPS value
    uint256 public constant MAX_BPS = 10_000;
    // Token transfer gas limit for L1
    uint32 public constant TOKEN_GAS_LIMIT = 300_000;
    // Wormhole chain Id for Ethereum L1
    uint16 public constant WORMHOLE_L1_CHAIN_ID = 2;

    // whOLAS-CELO LP token address on Ubeswap
    address public constant LP_TOKEN = 0x2976Fa805141b467BCBc6334a69AffF4D914d96A;
    // wCELO token address (token0 of LP)
    address public constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    // whOLAS token address (token1 of LP)
    address public constant WHOLAS = 0xaCFfAe8e57Ec6E394Eb1b41939A8CF7892DbDc51;
    // OLAS token address on Celo
    address public constant OLAS = 0xD80533CA29fF6F033a0b55732Ed792af9Fbb381E;
    // L2 Standard Bridge (OP-stack predeploy)
    address public constant L2_STANDARD_BRIDGE = 0x4200000000000000000000000000000000000010;
    // Ubeswap V2 Router address
    address public constant ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    // Wormhole Token Bridge address on Celo
    address public constant WORMHOLE_TOKEN_BRIDGE = 0x796Dff6D74F3E27060B71255Fe517BFb23C93eed;
    // L1 Timelock address (recipient for bridged tokens)
    address public constant L1_TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // Oracle address for TWAP-based slippage protection
    address public immutable oracle;
    // Max slippage for liquidity operations (in BPS)
    uint256 public immutable maxSlippage;

    // Reentrancy lock
    uint8 internal _locked;

    /// @dev LPSwapCelo constructor.
    /// @param _oracle UniswapPriceOracle address for TWAP slippage protection.
    /// @param _maxSlippage Max slippage in BPS (e.g., 100 = 1%).
    constructor(address _oracle, uint256 _maxSlippage) {
        // Check for zero address
        if (_oracle == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_maxSlippage == 0) {
            revert ZeroValue();
        }

        // Check for max value
        if (_maxSlippage > MAX_BPS) {
            revert Overflow(_maxSlippage, MAX_BPS);
        }

        oracle = _oracle;
        maxSlippage = _maxSlippage;

        _locked = 1;
    }

    /// @dev Swaps whOLAS-CELO liquidity to OLAS-CELO liquidity and bridges leftovers to L1.
    function swapLiquidity() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Step 1: Check LP token balance
        uint256 liquidity = IToken(LP_TOKEN).balanceOf(address(this));
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Step 2: Remove whOLAS-CELO liquidity with TWAP slippage protection
        (uint256 whOlasAmount, uint256 celoAmount) = _removeLiquidity(liquidity);

        // Step 3: Add OLAS-CELO liquidity using same amounts
        uint256 newLiquidity = _addLiquidity(whOlasAmount, celoAmount);

        emit LiquiditySwapped(whOlasAmount, celoAmount, whOlasAmount, newLiquidity);

        // Step 4: Bridge remaining OLAS to L1 Timelock via native bridge
        _bridgeOLAS();

        // Step 5: Bridge remaining whOLAS to L1 Timelock via Wormhole
        _bridgeWhOLAS();

        _locked = 1;
    }

    /// @dev Removes whOLAS-CELO liquidity with TWAP-based slippage protection.
    /// @param liquidity LP token amount to remove.
    /// @return whOlasAmount Received whOLAS amount.
    /// @return celoAmount Received CELO amount.
    function _removeLiquidity(uint256 liquidity) internal returns (uint256 whOlasAmount, uint256 celoAmount) {
        // Compute TWAP-based manipulation-resistant minAmountsOut
        uint256 minAmountCelo;
        uint256 minAmountWhOlas;
        {
            // Get reserves and totalSupply from the pair
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(LP_TOKEN).getReserves();
            uint256 totalSupply = IUniswapV2Pair(LP_TOKEN).totalSupply();

            // k = reserve0 * reserve1 is manipulation-resistant (invariant across swaps)
            uint256 k = uint256(reserve0) * uint256(reserve1);

            // TWAP is OLAS per secondToken in 1e18 format
            // For whOLAS-CELO pair: token0 = WCELO, token1 = whOLAS
            // Oracle direction: OLAS(whOLAS) per CELO, so twap = whOLAS/CELO price
            uint256 twap = IOracle(oracle).getTWAP();

            // Compute fair reserves using constant product invariant and TWAP price
            // token0 is WCELO (secondToken), token1 is whOLAS (OLAS-like)
            // fair_r0 = sqrt(k * 1e18 / twap), fair_r1 = sqrt(k * twap / 1e18)
            uint256 fairReserve0 = FixedPointMathLib.sqrt(k * 1e18 / twap);
            uint256 fairReserve1 = FixedPointMathLib.sqrt(k * twap / 1e18);

            // Expected withdrawal amounts (proportional to fair reserves)
            // minAmount = liquidity * fairReserve / totalSupply * (MAX_BPS - maxSlippage) / MAX_BPS
            minAmountCelo = (liquidity * fairReserve0 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
            minAmountWhOlas = (liquidity * fairReserve1 * (MAX_BPS - maxSlippage)) / (totalSupply * MAX_BPS);
        }

        // Approve LP tokens for the router
        IToken(LP_TOKEN).approve(ROUTER, liquidity);

        // Remove liquidity with TWAP-derived slippage protection
        // token0 = WCELO, token1 = whOLAS
        (celoAmount, whOlasAmount) = IUniswapV2Router(ROUTER)
            .removeLiquidity(WCELO, WHOLAS, liquidity, minAmountCelo, minAmountWhOlas, address(this), block.timestamp);
    }

    /// @dev Adds OLAS-CELO liquidity using the same amounts as removed from whOLAS-CELO.
    /// @param olasDesired Desired OLAS amount (same as removed whOLAS amount).
    /// @param celoDesired Desired CELO amount (same as removed CELO amount).
    /// @return liquidity New LP token amount created.
    function _addLiquidity(uint256 olasDesired, uint256 celoDesired) internal returns (uint256 liquidity) {
        // The olasDesired and celoDesired amounts come from the TWAP-protected whOLAS-CELO removal,
        // which means they already reflect the fair OLAS/CELO price ratio.
        //
        // If the OLAS-CELO pair does not exist yet, the router creates it and uses both amounts
        // exactly, so min amounts have no effect.
        //
        // If the OLAS-CELO pair already exists, an attacker could have manipulated its reserves
        // before this call. The router's addLiquidity adjusts one of the desired amounts down to
        // match the current pool ratio. With a skewed pool, the router would accept a bad ratio
        // and the attacker profits by sandwiching the other side.
        //
        // Since whOLAS and OLAS are equivalent in value, the whOLAS-CELO TWAP serves as a valid
        // reference price for the expected OLAS/CELO ratio. Applying maxSlippage to the
        // TWAP-derived desired amounts ensures the router reverts if the OLAS-CELO pool ratio
        // deviates too far from the fair price.
        //
        // celoMin is set to the full celoDesired amount to guarantee all CELO is deposited into
        // the new pair. Any leftover OLAS (if the router adjusts it down) gets bridged to L1.
        uint256 olasMin = (olasDesired * (MAX_BPS - maxSlippage)) / MAX_BPS;

        // Approve tokens for the router
        IToken(OLAS).approve(ROUTER, olasDesired);
        IToken(WCELO).approve(ROUTER, celoDesired);

        // Add liquidity (router creates pair if it does not exist)
        (, , liquidity) = IUniswapV2Router(ROUTER)
            .addLiquidity(OLAS, WCELO, olasDesired, celoDesired, olasMin, celoDesired, address(this), block.timestamp);
    }

    /// @dev Bridges remaining OLAS to L1 Timelock via Celo native bridge (OP-stack).
    function _bridgeOLAS() internal {
        uint256 olasBalance = IToken(OLAS).balanceOf(address(this));
        if (olasBalance > 0) {
            // Approve OLAS for the L2 Standard Bridge
            IToken(OLAS).approve(L2_STANDARD_BRIDGE, olasBalance);

            // Bridge OLAS to L1 Timelock
            IL2StandardBridge(L2_STANDARD_BRIDGE).withdrawTo(OLAS, L1_TIMELOCK, olasBalance, TOKEN_GAS_LIMIT, "");

            emit OLASBridgedToL1(olasBalance);
        }
    }

    /// @dev Bridges remaining whOLAS to L1 Timelock via Wormhole Token Bridge.
    function _bridgeWhOLAS() internal {
        uint256 whOlasBalance = IToken(WHOLAS).balanceOf(address(this));
        if (whOlasBalance > 0) {
            // Approve whOLAS for the Wormhole Token Bridge
            IToken(WHOLAS).approve(WORMHOLE_TOKEN_BRIDGE, whOlasBalance);

            // Convert L1_TIMELOCK address to bytes32 for Wormhole
            bytes32 recipient = bytes32(uint256(uint160(L1_TIMELOCK)));

            // Bridge whOLAS to L1 Timelock via Wormhole
            IWormholeTokenBridge(WORMHOLE_TOKEN_BRIDGE).transferTokens(
                WHOLAS, whOlasBalance, WORMHOLE_L1_CHAIN_ID, recipient, 0, 0
            );

            emit WhOLASBridgedToL1(whOlasBalance);
        }
    }
}
