// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./GenericTokenomics.sol";
import "./interfaces/IGenericBondCalculator.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/ITreasury.sol";

/*
* In this contract we consider OLAS tokens. The initial numbers will be as follows:
*  - For the first 10 years there will be the cap of 1 billion (1e27) tokens;
*  - After 10 years, the inflation rate is capped at 2% per year.
* Starting from a year 11, the maximum number of tokens that can be reached per the year x is 1e27 * (1.02)^x.
* To make sure that a unit(n) does not overflow the total supply during the year x, we have to check that
* 2^n - 1 >= 1e27 * (1.02)^x. We limit n by 96, thus it would take 220+ years to reach that total supply.
*
* We then limit each time variable to last until the value of 2^32 - 1 in seconds.
* 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970.
* Thus, this counter is safe until the year 2106.
*
* The number of blocks cannot be practically bigger than the number of seconds, since there is more than one second
* in a block. Thus, it is safe to assume that uint32 for the number of blocks is also sufficient.
*
* In conclusion, this contract is only safe to use until 2106.
*/

/// @title Bond Depository - Smart contract for OLAS Bond Depository
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Depository is GenericTokenomics {
    event CreateBond(address indexed token, uint256 productId, uint256 amountOLAS, uint256 tokenAmount);
    event CreateProduct(address indexed token, uint256 productId, uint256 supply);
    event CloseProduct(address indexed token, uint256 productId);

    // The size of the struct is 96 + 32 * 2 + 8 = 168 bits (1 full slot)
    struct Bond {
        // OLAS remaining to be paid out
        // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
        uint96 payout;
        // Bond maturity time
        // Reserves are 112 bits in size, we assume that their calculations will be limited by reserves0 x reserves1
        uint32 maturity;
        // Product Id of a bond
        // We assume that the number of products will not be bigger than the number of blocks
        uint32 productId;
        // Flag stating whether the bond was redeemed
        bool redeemed;
    }

    // The size of the struct is 256 + 160 + 96 + 32 + 224 = 768 bits (3 full slots)
    struct Product {
        // priceLP (reserve0 / totalSupply or reserve1 / totalSupply)
        // For gas optimization this number is kept squared and does not exceed type(uint224).max
        uint256 priceLP;
        // Token to accept as a payment
        address token;
        // Supply of remaining OLAS tokens
        // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
        uint96 supply;
        // Product expiry time (initialization time + vesting time)
        // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
        uint32 expiry;
        // LP tokens purchased
        // Reserves are 112 bits in size, we assume that their calculations will be limited by reserves0 x reserves1
        uint224 purchased;
    }

    // Bond Calculator contract address
    address public bondCalculator;
    // Mapping of user address => list of bonds
    mapping(address => Bond[]) public mapUserBonds;
    // Map of token address => bond products they are present
    mapping(address => Product[]) public mapTokenProducts;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _tokenomics Tokenomics address.
    constructor(address _olas, address _treasury, address _tokenomics, address _bondCalculator)
        GenericTokenomics(_olas, _tokenomics, _treasury, address(this), SENTINEL_ADDRESS, TokenomicsRole.Depository)
    {
        bondCalculator = _bondCalculator;
    }

    /// @dev Changes Bond Calculator contract address
    function changeBondCalculator(address _bondCalculator) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (_bondCalculator != address(0)) {
            bondCalculator = _bondCalculator;
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
    function deposit(address token, uint32 productId, uint224 tokenAmount, address user) external
        returns (uint96 payout, uint32 expiry, uint256 numBonds)
    {
        Product storage product = mapTokenProducts[token][productId];

        // Check for the product expiry
        // Note that if the token or productId are invalid, the expiry will be zero by default and revert the function
        expiry = product.expiry;
        if (expiry < block.timestamp) {
            revert ProductExpired(token, productId, product.expiry, block.timestamp);
        }

        // Calculate the payout in OLAS tokens based on the LP pair with the discount factor (DF) calculation
        // Note that payout cannot be zero since the price LP is non-zero, since otherwise the product would not be created
        payout = IGenericBondCalculator(bondCalculator).calculatePayoutOLAS(tokenAmount, product.priceLP);

        // Check for the sufficient supply
        if (payout > product.supply) {
            revert ProductSupplyLow(token, productId, payout, product.supply);
        }

        // Decrease the supply for the amount of payout, increase number of purchased tokens and sold OLAS tokens
        product.supply -= payout;
        product.purchased += tokenAmount;

        // Updated number of bonds for this product
        numBonds = mapUserBonds[user].length;

        // Create and add a new bond
        mapUserBonds[user].push(Bond(payout, expiry, productId, false));
        emit CreateBond(token, productId, payout, tokenAmount);

        // TODO All the transfer-related routines below can be moved to the treasury side without the need to receive funds by depository first?
        // Uniswap allowance implementation does not revert with the accurate message, check before the transfer is engaged
        if (IERC20(product.token).allowance(msg.sender, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(product.token).allowance((msg.sender), address(this)), tokenAmount);
        }
        // Transfer tokens to the depository
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 implementation has a standard transferFrom() function that returns a boolean value
        IERC20(product.token).transferFrom(msg.sender, address(this), tokenAmount);
        // Approve treasury for the specified token amount
        IERC20(product.token).approve(treasury, tokenAmount);
        // Deposit that token amount to mint OLAS tokens in exchange
        ITreasury(treasury).depositTokenForOLAS(tokenAmount, product.token, payout);
    }

    /// @dev Redeem user bonds.
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

        // Form pending bonds index array
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

    // TODO Make sure deposit and create are not run in the same block number
    /// @dev Creates a new bond product.
    /// @param token LP token to be deposited for pairs like OLAS-DAI, OLAS-ETH, etc.
    /// @param priceLP LP token price.
    /// @param supply Supply in OLAS tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    function create(address token, uint256 priceLP, uint96 supply, uint32 vesting) external returns (uint256 productId) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the pool liquidity as the LP price being greater than zero
        if (priceLP < 1e18) {
            revert Underflow(priceLP, 1e18);
        }

        // Check if the LP token is enabled and that it is the LP token
        if (!ITreasury(treasury).isEnabled(token) || !IGenericBondCalculator(bondCalculator).checkLP(token)) {
            revert UnauthorizedToken(token);
        }

        // Check if the bond amount is beyond the limits
        if (!ITokenomics(tokenomics).reserveAmountForBondProgram(supply)) {
            revert AmountLowerThan(ITokenomics(tokenomics).effectiveBond(), supply);
        }

        // Create a new product
        productId = mapTokenProducts[token].length;

        // Check for the expiration time overflow
        uint256 expiry = block.timestamp + vesting;
        if (expiry > type(uint32).max) {
            revert Overflow(expiry, type(uint32).max);
        }
        // Push newly created bond product into the list of products
        mapTokenProducts[token].push(Product(priceLP, token, supply, uint32(expiry), 0));
        emit CreateProduct(token, productId, supply);
    }

    // TODO Make this function callable by everybody, also from the redeem function
    /// @dev Close a bonding product.
    /// @param token Specified token.
    /// @param productId Product Id.
    function close(address token, uint256 productId) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint96 supply = mapTokenProducts[token][productId].supply;
        // Refund unused OLAS supply from the program if not used completely
        if (supply > 0) {
            ITokenomics(tokenomics).refundFromBondProgram(supply);
        }
        // TODO Check if delete of the mapTokenProducts[token][productId] is better
        mapTokenProducts[token][productId].supply = 0;
        
        emit CloseProduct(token, productId);
    }

    // TODO Optimize for gas usage
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

    /// @dev Gets current reserves of OLAS / totalSupply of LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX/totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP) {
        return IGenericBondCalculator(bondCalculator).getCurrentPriceLP(token);
    }
}
