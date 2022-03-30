// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/ITreasury.sol";


/// @title Bond Depository - Smart contract for OLA Bond Depository
/// @author AL
contract BondDepository is IErrors, Ownable {
    using SafeERC20 for IERC20;

    event CreateBond(uint256 productId, uint256 amountOLA, uint256 tokenAmount);
    event CreateProduct(address token, uint256 productId, uint256 supply);
    event TerminateProduct(address token, uint256 productId);
    event DepositoryManagerUpdated(address manager);

    struct Bond {
        // OLA remaining to be paid out
        uint256 payout;
        // Bond creation time
        uint256 creation;
        // Bond maturity time
        uint256 maturity;
        // Product Id of a bond
        uint256 productId;
        // time product was redeemed
        bool redeemed;
    }

    struct Product {
        // Token to accept as a payment
        IERC20 token;
        // Supply remaining in OLA tokens
        uint256 supply;
        // Vesting time in sec
        uint256 vesting;
        // Product expiry time (initialization time + vesting time)
        uint256 expiry;
        // Number of specified tokens purchased
        uint256 purchased;
        // Number of OLA tokens sold
        uint256 sold;
    }

    // OLA interface
    IERC20 public immutable ola;
    // Treasury interface
    ITreasury public treasury;
    // Depository manager
    address public manager;
    // Mapping of user address => list of bonds
    mapping(address => Bond[]) public mapUserBonds;
    // Map of token address => bond products they are present
    mapping(address => Product[]) public mapTokenProducts;

    // TODO later fix government / manager
    constructor(address initManager, IERC20 iOLA, ITreasury iTreasury) {
        manager = initManager;
        ola = iOLA;
        treasury = iTreasury;
    }

    // Only the manager has a privilege to manipulate a treasury
    modifier onlyManager() {
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }
        _;
    }

    /// @dev Changes the treasury manager.
    /// @param newManager Address of a new treasury manager.
    function changeManager(address newManager) external onlyOwner {
        manager = newManager;
        emit DepositoryManagerUpdated(newManager);
    }

    /// @dev Deposits tokens in exchange for a bond from a specified product.
    /// @param token Token address.
    /// @param productId Product Id.
    /// @param tokenAmount Token amount to deposit for the bond.
    /// @param user Address of a payout recipient.
    /// @return payout The amount of OLA tokens due.
    /// @return expiry Timestamp for payout redemption.
    /// @return numBonds Number of user bonds.
    function deposit(address token, uint256 productId, uint256 tokenAmount, address user) external
        returns (uint256 payout, uint256 expiry, uint256 numBonds)
    {
        Product storage product = mapTokenProducts[token][productId];
        // Check for the correctly provided token in the product
        if (token != address(product.token)) {
            revert WrongTokenAddress(token, address(product.token));
        }

        // Check for the product expiry
        uint256 currentTime = uint256(block.timestamp);
        if (currentTime > product.expiry) {
            revert ProductExpired(token, productId, product.expiry, currentTime);
        }

        // Calculate the payout in OLA tokens based on the LP pair with the discount factor (DF) calculation
        payout = _calculatePayoutFromLP(token, tokenAmount);

        // Check for the sufficient supply
        if (payout > product.supply) {
            revert ProductSupplyLow(token, productId, payout, product.supply);
        }

        // Decrease the supply for the amount of payout, increase number of purchased tokens and sold OLA tokens
        product.supply -= payout;
        product.purchased += tokenAmount;
        product.sold += payout;

        numBonds = mapUserBonds[user].length;
        expiry = product.expiry;

        // Create and add a new bond
        mapUserBonds[user].push(Bond(payout, uint256(block.timestamp), expiry, productId, false));
        emit CreateBond(productId, payout, tokenAmount);

        // Transfer tokens to the depository
        product.token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        // Approve treasury for the specified token amount
        product.token.approve(address(treasury), tokenAmount);
        // Deposit that token amount to mint OLA tokens in exchange
        treasury.deposit(tokenAmount, address(product.token), payout);
    }

    /// @dev Redeem bonds for the user.
    /// @param user Address of a payout recipient.
    /// @param indexes Bond indexes to redeem.
    /// @return payout Total payout sent in OLA tokens.
    function redeem(address user, uint256[] memory indexes) public returns (uint256 payout) {
        for (uint256 i = 0; i < indexes.length; i++) {
            // Get the amount to pay and the maturity status
            (uint256 pay, bool maturity) = getBondStatus(user, indexes[i]);

            // If matured, mark as redeemed and add to the total payout
            if (maturity) {
                mapUserBonds[user][indexes[i]].redeemed = true;
                payout += pay;
            }
        }
        // No reentrancy risk here since it's the last operation, and originated from the OLA token
        ola.transfer(user, payout);
    }

    /// @dev Redeems all redeemable products for a user. Best to query off-chain and input in redeem() to save gas.
    /// @param user Address of the user to redeem all bonds for.
    /// @return payout Total payout sent in OLA tokens.
    function redeemAll(address user) external returns (uint256 payout) {
        payout = redeem(user, getPendingBonds(user));
    }

    /// @dev Gets indexes of all pending bonds for a user.
    /// @param user User address to query bonds for.
    /// @return indexes Pending bond indexes.
    function getPendingBonds(address user) public view returns (uint256[] memory indexes) {
        Bond[] memory bonds = mapUserBonds[user];

        // Calculate the number of pending bonds
        uint numBonds = bonds.length;
        bool[] memory positions = new bool[](numBonds);
        uint256 numPendingBonds;
        for (uint256 i = 0; i < numBonds; i++) {
            if (!bonds[i].redeemed && bonds[i].payout != 0) {
                positions[i] = true;
                numPendingBonds++;
            }
        }

        // Form the pending bonds index array
        indexes = new uint256[](numPendingBonds);
        uint256 numPos;
        for (uint256 i = 0; i < numBonds; i++) {
            if (positions[i]) {
                indexes[numPos] = i;
                ++numPos;
            }
        }
    }

    /// @dev Calculates the maturity and payout to claim for a single bond.
    /// @param user Address of a payout recipient.
    /// @param index The user bond index.
    /// @return payout The payout amount in OLA.
    /// @return matured True if the payout can be redeemed.
    function getBondStatus(address user, uint256 index) public view returns (uint256 payout, bool matured) {
        Bond memory bond = mapUserBonds[user][index];
        payout = bond.payout;
        matured = !bond.redeemed && bond.maturity <= block.timestamp && bond.payout != 0;
    }

    // TODO For now only Uniswapv2 is supported
    /// @dev Creates a new bond product.
    /// @param token Uniswapv2 LP token to be deposited for pairs like OLA-DAI, OLA-ETH, etc.
    /// @param supply Supply in OLA tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    function create(IERC20 token, uint256 supply, uint256 vesting) external onlyManager returns (uint256 productId) {
        // Create a new product.
        productId = mapTokenProducts[address(token)].length;
        Product memory product = Product(token, supply, vesting, uint256(block.timestamp + vesting), 0, 0);
        mapTokenProducts[address(token)].push(product);

        emit CreateProduct(address(token), productId, supply);
    }

    /// @dev Cloe a bonding product.
    /// @param token Specified token.
    /// @param productId Product Id.
    function close(address token, uint256 productId) external onlyManager {
        mapTokenProducts[token][productId].supply = 0;
        
        emit TerminateProduct(token, productId);
    }

    /// @dev Gets activity information about a given product.
    /// @param productId Product Id.
    /// @return status True if
    function isActive(address token, uint256 productId) public view returns (bool status) {
        status = (mapTokenProducts[token][productId].supply > 0 &&
            mapTokenProducts[token][productId].expiry > block.timestamp);
    }

    /// @dev Gets an array of all active product Ids for a specific token.
    /// @param token Token address
    /// @return ids Active product Ids.
    function getActiveProductsForToken(address token) external view returns (uint256[] memory ids) {
        // Calculate the number of active products
        uint numProducts = mapTokenProducts[token].length;
        bool[] memory positions = new bool[](numProducts);
        uint256 numActive;
        for (uint256 i = 0; i < numProducts; i++) {
            if (isActive(token, i)) {
                positions[i] = true;
                ++numActive;
            }
        }

        // Form the active products index array
        ids = new uint256[](numActive);
        uint256 numPos;
        for (uint256 i = 0; i < numProducts; i++) {
            if (positions[i]) {
                ids[numPos] = i;
                numPos++;
            }
        }
        return ids;
    }

    // TODO This is the mocking function for the moment
    /// @dev Calculates discount factor.
    /// @param amount Initial OLA token amount.
    /// @return amountDF OLA amount corrected by the DF.
    function _calculateDF(uint256 amount) internal pure returns (uint256 amountDF) {
        uint256 UCF = 50; // 50% just stub
        uint256 USF = 60; // 60% just stub
        uint256 sum = UCF + USF; // 50 + 60 = 110
        amountDF = (amount / 100) * sum; // 110/100, fixed later

        // The discounted amount cannot be smaller than the actual one
        if (amountDF < amount) {
            revert AmountLowerThan(amountDF, amount);
        }
    }

    // UniswapV2 https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // No license in file
    // forked for Solidity 8.x
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset

    /// @dev Gets the additional OLA amount from the LP pair token by swapping.
    /// @param amountIn Initial OLA token amount.
    /// @param reserveIn Token amount that is not OLA.
    /// @param reserveOut Token amount in OLA wit fees.
    /// @return amountOut Resulting OLA amount.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee / reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation).
    /// @param token Token address.
    /// @param amount Token amount.
    /// @return resAmount Resulting amount of OLA tokens.
    function _calculatePayoutFromLP(address token, uint256 amount) internal view
        returns (uint256 resAmount)
    {
        // Calculation of removeLiquidity
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();

        // Using balances ensures pro-rate distribution
        uint256 amount0 = (amount * balance0) / totalSupply;
        uint256 amount1 = (amount * balance1) / totalSupply;

        require(balance0 > amount0, "UniswapV2: INSUFFICIENT_LIQUIDITY token0");
        require(balance1 > amount1, "UniswapV2: INSUFFICIENT_LIQUIDITY token1");

        // Get the initial OLA token amounts
        uint256 amountOLA = (token0 == address(ola)) ? amount0 : amount1;
        uint256 amountPairForOLA = (token0 == address(ola)) ? amount1 : amount0;

        // Calculate swap tokens from the LP back to the OLA token
        balance0 -= amount0;
        balance1 -= amount1;
        uint256 reserveIn = (token0 == address(ola)) ? balance1 : balance0;
        uint256 reserveOut = (token0 == address(ola)) ? balance0 : balance1;
        amountOLA = amountOLA + getAmountOut(amountPairForOLA, reserveIn, reserveOut);

        // Get the resulting amount in OLA tokens
        resAmount = _calculateDF(amountOLA);
    }

    /// @dev Gets the product instance.
    /// @param token Token address.
    /// @param productId Product Id.
    /// @return Product instance.
    function getProduct(address token, uint256 productId) public view returns (Product memory) {
        return mapTokenProducts[token][productId];
    }
}
