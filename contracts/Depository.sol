// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITokenomics.sol";

/// @title Bond Depository - Smart contract for OLAS Bond Depository
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Depository is IErrorsTokenomics, Ownable {
    // TODO: Consider the cheaper alternative to SafeERC20
    using SafeERC20 for IERC20;

    event CreateBond(uint256 productId, uint256 amountOLAS, uint256 tokenAmount);
    event CreateProduct(address token, uint256 productId, uint256 supply);
    event TerminateProduct(address token, uint256 productId);
    event TreasuryUpdated(address treasury);
    event TokenomicsUpdated(address tokenomics);

    struct Bond {
        // OLAS remaining to be paid out
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

    // TODO: Unify vesting and expiry
    struct Product {
        // Token to accept as a payment
        address token;
        // Supply remaining in OLAS tokens
        uint256 supply;
        // Vesting time in sec
        uint256 vesting;
        // Product expiry time (initialization time + vesting time)
        uint256 expiry;
        // Number of specified tokens purchased
        uint256 purchased;
        // Number of OLAS tokens sold
        uint256 sold;
        // priceLP (reserve0/totalSupply or reserve1/totalSupply)
        // for optimization - this number does not exceed type(uint224).max 
        uint256 priceLP;
    }

    // OLAS token address
    address public immutable olas;
    // Treasury address
    address public treasury;
    // Tokenomics address
    address public tokenomics;
    // Mapping of user address => list of bonds
    mapping(address => Bond[]) public mapUserBonds;
    // Map of token address => bond products they are present
    mapping(address => Product[]) public mapTokenProducts;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _tokenomics Tokenomics address.
    constructor(address _olas, address _treasury, address _tokenomics) {
        olas = _olas;
        treasury = _treasury;
        tokenomics = _tokenomics;
    }

    /// @dev Changes various managing contract addresses.
    /// @param _treasury Treasury address.
    /// @param _tokenomics Tokenomics address.
    function changeManagers(address _treasury, address _tokenomics) external onlyOwner {
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
    }

    /// @dev Deposits tokens in exchange for a bond from a specified product.
    /// @param token Token address.
    /// @param productId Product Id.
    /// @param tokenAmount Token amount to deposit for the bond.
    /// @param user Address of a payout recipient.
    /// @return payout The amount of OLAS tokens due.
    /// @return expiry Timestamp for payout redemption.
    /// @return numBonds Number of user bonds.
    function deposit(address token, uint256 productId, uint256 tokenAmount, address user) external
        returns (uint256 payout, uint256 expiry, uint256 numBonds)
    {
        // TODO: storage vs memory optimization
        Product storage product = mapTokenProducts[token][productId];
        // Check for the correctly provided token in the product
        // TODO: Remove, since this scenario is not possible (line above protects against that)
        if (token != address(product.token)) {
            revert WrongTokenAddress(token, address(product.token));
        }

        // Check for the product expiry
        uint256 currentTime = uint256(block.timestamp);
        if (currentTime > product.expiry) {
            revert ProductExpired(token, productId, product.expiry, currentTime);
        }

        // Calculate the payout in OLAS tokens based on the LP pair with the discount factor (DF) calculation
        payout = ITokenomics(tokenomics).calculatePayoutFromLP(tokenAmount, product.priceLP);

        // Check for the sufficient supply
        if (payout > product.supply) {
            revert ProductSupplyLow(token, productId, payout, product.supply);
        }

        // Decrease the supply for the amount of payout, increase number of purchased tokens and sold OLAS tokens
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
        if (IERC20(product.token).allowance(msg.sender, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(product.token).allowance((msg.sender), address(this)), tokenAmount);
        }
        // Transfer tokens to the depository
        IERC20(product.token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        // Approve treasury for the specified token amount
        IERC20(product.token).approve(treasury, tokenAmount);
        // Deposit that token amount to mint OLAS tokens in exchange
        ITreasury(treasury).depositTokenForOLAS(tokenAmount, product.token, payout);
    }

    /// @dev Redeem bonds for the user.
    /// @param user Address of a payout recipient.
    /// @param indexes Bond indexes to redeem.
    /// @return payout Total payout sent in OLAS tokens.
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
        // No reentrancy risk here since it's the last operation, and originated from the OLAS token
        IERC20(olas).transfer(user, payout);
    }

    /// @dev Redeems all redeemable products for a user. Best to query off-chain and input in redeem() to save gas.
    /// @param user Address of the user to redeem all bonds for.
    /// @return payout Total payout sent in OLAS tokens.
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
    /// @return payout The payout amount in OLAS.
    /// @return matured True if the payout can be redeemed.
    function getBondStatus(address user, uint256 index) public view returns (uint256 payout, bool matured) {
        Bond memory bond = mapUserBonds[user][index];
        payout = bond.payout;
        matured = !bond.redeemed && bond.maturity <= block.timestamp && bond.payout != 0;
    }

    /// @dev Creates a new bond product.
    /// @param token LP token to be deposited for pairs like OLAS-DAI, OLAS-ETH, etc.
    /// @param supply Supply in OLAS tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    function create(address token, uint256 supply, uint256 vesting) external onlyOwner returns (uint256 productId) {
        // Check if the LP token is enabled and that it is the LP token
        if (!ITreasury(treasury).isEnabled(token) || !ITreasury(treasury).checkPair(token)) {
            revert UnauthorizedToken(token);
        }

        // Check if the bond amount is beyond the limits
        if (!ITokenomics(tokenomics).allowedNewBond(supply)) {
            revert AmountLowerThan(ITokenomics(tokenomics).effectiveBond(), supply);
        }

        // Create a new product
        productId = mapTokenProducts[token].length;
        uint256 priceLP = ITokenomics(tokenomics).getCurrentPriceLP(token);
        // Check for the pool liquidity as the LP price being greater than zero
        if (priceLP == 0) {
            revert ZeroValue();
        }

        Product memory product = Product(token, supply, vesting, uint256(block.timestamp + vesting), 0, 0, priceLP);
        mapTokenProducts[token].push(product);
        emit CreateProduct(token, productId, supply);
    }

    /// @dev Close a bonding product.
    /// @param token Specified token.
    /// @param productId Product Id.
    function close(address token, uint256 productId) external onlyOwner {
        mapTokenProducts[token][productId].supply = 0;
        
        emit TerminateProduct(token, productId);
    }

    /// @dev Gets activity information about a given product.
    /// @param productId Product Id.
    /// @return status True if the product is active.
    function isActive(address token, uint256 productId) public view returns (bool status) {
        status = (mapTokenProducts[token].length > productId && mapTokenProducts[token][productId].supply > 0 &&
            mapTokenProducts[token][productId].expiry > block.timestamp);
    }

    /// @dev Gets an array of all active product Ids for a specific token.
    /// @param token Token address
    /// @return ids Active product Ids.
    function getActiveProductsForToken(address token) external view returns (uint256[] memory ids) {
        // Calculate the number of active products
        uint256 numProducts = mapTokenProducts[token].length;
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
    function getProduct(address token, uint256 productId) external view returns (Product memory) {
        return mapTokenProducts[token][productId];
    }
}
