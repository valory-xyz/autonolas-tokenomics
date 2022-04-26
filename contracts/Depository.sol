// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITokenomics.sol";

/// @title Bond Depository - Smart contract for OLA Bond Depository
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Depository is IErrors, Ownable {
    using SafeERC20 for IERC20;

    event CreateBond(uint256 productId, uint256 amountOLA, uint256 tokenAmount);
    event CreateProduct(address token, uint256 productId, uint256 supply);
    event TerminateProduct(address token, uint256 productId);
    event TreasuryUpdated(address treasury);
    event TokenomicsUpdated(address tokenomics);

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

    // OLA token address
    address public immutable ola;
    // Treasury address
    address public treasury;
    // Tokenomics address
    address public tokenomics;
    // Mapping of user address => list of bonds
    mapping(address => Bond[]) public mapUserBonds;
    // Map of token address => bond products they are present
    mapping(address => Product[]) public mapTokenProducts;

    constructor(address _ola, address _treasury, address _tokenomics) {
        ola = _ola;
        treasury = _treasury;
        tokenomics = _tokenomics;
    }

    function changeTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function changeTokenomics(address newTokenomics) external onlyOwner {
        tokenomics = newTokenomics;
        emit TokenomicsUpdated(newTokenomics);
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
        uint256 epoch = block.number / ITokenomics(tokenomics).epochLen();
        // df uint with defined decimals
        payout = ITokenomics(tokenomics).calculatePayoutFromLP(token, tokenAmount, epoch);
        
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

        // Take into account this bond in current epoch
        ITokenomics(tokenomics).usedBond(payout);

        // Uniswap allowance implementation does not revert with the accurate message, check before SafeMath is engaged
        if (product.token.allowance(msg.sender, address(this)) < tokenAmount) {
            revert InsufficientAllowance(product.token.allowance((msg.sender), address(this)), tokenAmount);
        }
        // Transfer tokens to the depository
        product.token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        // Approve treasury for the specified token amount
        product.token.approve(treasury, tokenAmount);
        // Deposit that token amount to mint OLA tokens in exchange
        ITreasury(treasury).depositTokenForOLA(tokenAmount, address(product.token), payout);
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
        IERC20(ola).transfer(user, payout);
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

    /// @dev Creates a new bond product.
    /// @param token LP token to be deposited for pairs like OLA-DAI, OLA-ETH, etc.
    /// @param supply Supply in OLA tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    function create(IERC20 token, uint256 supply, uint256 vesting) external onlyOwner returns (uint256 productId) {
        // Create a new product.
        if(!ITokenomics(tokenomics).allowedNewBond(supply)) {
            // fixed later to correct revert
            revert AmountLowerThan(ITokenomics(tokenomics).getBondLeft(), supply);
        }
        productId = mapTokenProducts[address(token)].length;
        Product memory product = Product(token, supply, vesting, uint256(block.timestamp + vesting), 0, 0);
        mapTokenProducts[address(token)].push(product);

        emit CreateProduct(address(token), productId, supply);
    }

    /// @dev Cloe a bonding product.
    /// @param token Specified token.
    /// @param productId Product Id.
    function close(address token, uint256 productId) external onlyOwner {
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

    /// @dev Gets the product instance.
    /// @param token Token address.
    /// @param productId Product Id.
    /// @return Product instance.
    function getProduct(address token, uint256 productId) public view returns (Product memory) {
        return mapTokenProducts[token][productId];
    }
}
