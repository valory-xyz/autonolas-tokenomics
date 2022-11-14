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

    // The size of the struct is 160 + 96 + 32 * 2 + 8 = 328 bits (2 full slots)
    struct Bond {
        // Account address
        address account;
        // OLAS remaining to be paid out
        // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
        uint96 payout;
        // Bond maturity time
        // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
        uint32 maturity;
        // Product Id of a bond
        // We assume that the number of products will not be bigger than the number of blocks
        uint32 productId;
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

    // Individual bond counter
    uint256 bondCounter;
    // Bond product counter
    uint256 productCounter;

    // Bond Calculator contract address
    address public bondCalculator;
    // Mapping of bond Id => account bond instance
    mapping(uint256 => Bond) public mapUserBonds;
    // Mapping of product Id => bond product instance
    mapping(uint256 => Product) public mapTokenProducts;

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
    /// @param productId Product Id.
    /// @param tokenAmount Token amount to deposit for the bond.
    /// @return payout The amount of OLAS tokens due.
    /// @return expiry Timestamp for payout redemption.
    /// @return bondId Id of a newly created bond.
    function deposit(uint256 productId, uint256 tokenAmount) external
        returns (uint96 payout, uint32 expiry, uint256 bondId)
    {
        Product storage product = mapTokenProducts[productId];

        // Get the LP token address
        address token = product.token;

        // Check for the product expiry
        // Note that if the token or productId are invalid, the expiry will be zero by default and revert the function
        expiry = product.expiry;
        if (expiry < block.timestamp) {
            revert ProductExpired(token, productId, product.expiry, block.timestamp);
        }

        // Calculate the payout in OLAS tokens based on the LP pair with the discount factor (DF) calculation
        // Note that payout cannot be zero since the price LP is non-zero, since otherwise the product would not be created
        payout = uint96(IGenericBondCalculator(bondCalculator).calculatePayoutOLAS(tokenAmount, product.priceLP));

        // Check for the sufficient supply
        if (payout > product.supply) {
            revert ProductSupplyLow(token, uint32(productId), payout, product.supply);
        }

        // TODO Check if it's cheaper to subtract and add with temporary variables
        // Decrease the supply for the amount of payout, increase number of purchased tokens and sold OLAS tokens
        product.supply -= payout;
        product.purchased += uint224(tokenAmount);

        // Create and add a new bond, update the bond counter
        bondId = bondCounter;
        mapUserBonds[bondId] = Bond(msg.sender, payout, expiry, uint32(productId));
        bondCounter = bondId + 1;
        emit CreateBond(token, productId, payout, tokenAmount);

        // TODO All the transfer-related routines below can be moved to the treasury side without the need to receive funds by depository first?
        // Uniswap allowance implementation does not revert with the accurate message, check before the transfer is engaged
        if (IERC20(token).allowance(msg.sender, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(token).allowance((msg.sender), address(this)), tokenAmount);
        }
        // Transfer tokens to the depository
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 implementation has a standard transferFrom() function that returns a boolean value
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        // Approve treasury for the specified token amount
        IERC20(token).approve(treasury, tokenAmount);
        // Deposit that token amount to mint OLAS tokens in exchange
        ITreasury(treasury).depositTokenForOLAS(uint224(tokenAmount), token, payout);
    }

    /// @dev Redeem account bonds.
    /// @param bondIds Bond Ids to redeem.
    /// @return payout Total payout sent in OLAS tokens.
    function redeem(uint256[] memory bondIds) public returns (uint256 payout) {
        for (uint256 i = 0; i < bondIds.length; i++) {
            // Check that the msg.sender is the owner of the bond
            if (mapUserBonds[bondIds[i]].account != msg.sender) {
                revert OwnerOnly(msg.sender, mapUserBonds[bondIds[i]].account);
            }

            // Get the amount to pay and the maturity status
            uint256 pay = mapUserBonds[bondIds[i]].payout;
            bool matured = (block.timestamp >= mapUserBonds[bondIds[i]].maturity) && pay != 0;

            // If matured, delete the Bond struct and release the gas
            if (matured) {
                uint256 productId = mapUserBonds[bondIds[i]].productId;
                delete mapUserBonds[bondIds[i]];
                payout += pay;

                // Close the program if it was not yet closed
                if (mapTokenProducts[productId].expiry > 0) {
                    uint96 supply = mapTokenProducts[productId].supply;
                    // Refund unused OLAS supply from the program if not used completely
                    if (supply > 0) {
                        ITokenomics(tokenomics).refundFromBondProgram(supply);
                    }
                    address token = mapTokenProducts[productId].token;
                    delete mapTokenProducts[productId];

                    emit CloseProduct(token, productId);
                }
            }
        }
        // No reentrancy risk here since it's the last operation, and originated from the OLAS token
        IERC20(olas).transfer(msg.sender, payout);
    }

    /// @dev Gets bond Ids of all pending bonds for the account address.
    /// @param account Account address to query bonds for.
    /// @return bondIds Pending bond Ids.
    function getPendingBonds(address account) external view returns (uint256[] memory bondIds) {
        uint256 numAccountBonds;
        // Calculate the number of pending bonds
        uint256 numBonds = bondCounter;
        bool[] memory positions = new bool[](numBonds);
        // Record the bond number if it belongs to the account address and was not yet redeemed
        for (uint256 i = 0; i < numBonds; i++) {
            if (mapUserBonds[i].account == account && mapUserBonds[i].payout > 0) {
                positions[i] = true;
                numAccountBonds++;
            }
        }

        // Form pending bonds index array
        bondIds = new uint256[](numBonds);
        uint256 numPos;
        for (uint256 i = 0; i < numBonds; i++) {
            if (positions[i]) {
                bondIds[numPos] = i;
                ++numPos;
            }
        }
    }

    /// @dev Calculates the maturity and payout to claim for a single bond.
    /// @param bondId The account bond Id.
    /// @return payout The payout amount in OLAS.
    /// @return matured True if the payout can be redeemed.
    function getBondStatus(uint256 bondId) external view returns (uint256 payout, bool matured) {
        payout = mapUserBonds[bondId].payout;
        matured = (block.timestamp >= mapUserBonds[bondId].maturity) && payout != 0;
    }

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
        if (priceLP == 0) {
            revert ZeroValue();
        }

        // Check if the LP token is enabled and that it is the LP token
        if (!ITreasury(treasury).isEnabled(token) || !IGenericBondCalculator(bondCalculator).checkLP(token)) {
            revert UnauthorizedToken(token);
        }

        // Check if the bond amount is beyond the limits
        if (!ITokenomics(tokenomics).reserveAmountForBondProgram(supply)) {
            revert AmountLowerThan(ITokenomics(tokenomics).effectiveBond(), supply);
        }

        // Check for the expiration time overflow
        uint256 expiry = block.timestamp + vesting;
        if (expiry > type(uint32).max) {
            revert Overflow(expiry, type(uint32).max);
        }

        // Push newly created bond product into the list of products
        productId = productCounter;
        mapTokenProducts[productId] = Product(priceLP, token, supply, uint32(expiry), 0);
        productCounter = productId + 1;
        emit CreateProduct(token, productId, supply);
    }

    /// @dev Close a bonding product.
    /// @param productId Product Id.
    function close(uint256 productId) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint96 supply = mapTokenProducts[productId].supply;
        // Refund unused OLAS supply from the program if not used completely
        if (supply > 0) {
            ITokenomics(tokenomics).refundFromBondProgram(supply);
        }
        address token = mapTokenProducts[productId].token;
        delete mapTokenProducts[productId];
        
        emit CloseProduct(token, productId);
    }

    /// @dev Gets activity information about a given product.
    /// @param productId Product Id.
    /// @return status True if the product is active.
    function isActiveProduct(uint256 productId) external view returns (bool status) {
        status = (mapTokenProducts[productId].supply > 0 && mapTokenProducts[productId].expiry > block.timestamp);
    }

    /// @dev Gets an array of all active product Ids for a specific token.
    /// @return productIds Active product Ids.
    function getActiveProductsForToken() external view returns (uint256[] memory productIds) {
        // Calculate the number of active products
        uint256 numProducts = productCounter;
        bool[] memory positions = new bool[](numProducts);
        uint256 numActive;
        for (uint256 i = 0; i < numProducts; i++) {
            if (mapTokenProducts[i].supply > 0 && mapTokenProducts[i].expiry > block.timestamp) {
                positions[i] = true;
                ++numActive;
            }
        }

        // Form the active products index array
        productIds = new uint256[](numActive);
        uint256 numPos;
        for (uint256 i = 0; i < numProducts; i++) {
            if (positions[i]) {
                productIds[numPos] = i;
                ++numPos;
            }
        }
        return productIds;
    }

    /// @dev Gets current reserves of OLAS / totalSupply of LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX/totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP) {
        return IGenericBondCalculator(bondCalculator).getCurrentPriceLP(token);
    }
}
