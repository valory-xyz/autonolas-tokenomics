// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IErrorsTokenomics.sol";
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
contract Depository is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
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
        // We assume that the number of products will not be bigger than the number of seconds
        uint32 productId;
    }

    // The size of the struct is 256 + 160 + 96 + 32 = 544 bits (3 full slots)
    // TODO If priceLP can be stored in uint224, then the struct is reduced to 2 full slots
    struct Product {
        // priceLP (reserve0 / totalSupply or reserve1 / totalSupply) with 18 additional decimals
        uint256 priceLP;
        // Token to accept as a payment
        address token;
        // Supply of remaining OLAS tokens
        // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
        uint96 supply;
        // Product expiry time (initialization time + vesting time)
        // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
        uint32 expiry;
    }

    // Owner address
    address public owner;
    // Individual bond counter
    // We assume that the number of bonds will not be bigger than the number of seconds
    uint32 bondCounter;
    // Bond product counter
    // We assume that the number of products will not be bigger than the number of seconds
    uint32 productCounter;
    // Reentrancy lock
    uint8 internal _locked;

    // OLAS token address
    address public olas;
    // Tkenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;
    // Bond Calculator contract address
    address public bondCalculator;

    // Mapping of bond Id => account bond instance
    mapping(uint256 => Bond) public mapUserBonds;
    // Mapping of product Id => bond product instance
    mapping(uint256 => Product) public mapBondProducts;

    /// @dev Depository constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _tokenomics Tokenomics address.
    constructor(address _olas, address _tokenomics, address _treasury, address _bondCalculator)
    {
        owner = msg.sender;
        _locked = 1;
        olas = _olas;
        tokenomics = _tokenomics;
        treasury = _treasury;
        bondCalculator = _bondCalculator;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
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

    /// @dev Changes various managing contract addresses.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    function changeManagers(address _tokenomics, address _treasury) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Change Tokenomics contract address
        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
        // Change Treasury contract address
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
    }

    /// @dev Changes Bond Calculator contract address
    ///#if_succeeds {:msg "changed"} bondCalculator != address(0); 
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
    ///#if_succeeds {:msg "token is valid" } mapBondProducts[productId].token != address(0);
    function deposit(uint256 productId, uint256 tokenAmount) external
        returns (uint256 payout, uint256 expiry, uint256 bondId)
    {
        Product storage product = mapBondProducts[productId];

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
        payout = IGenericBondCalculator(bondCalculator).calculatePayoutOLAS(tokenAmount, product.priceLP);

        // Check for the sufficient supply
        if (payout > product.supply) {
            revert ProductSupplyLow(token, uint32(productId), payout, product.supply);
        }

        // Decrease the supply for the amount of payout
        uint256 supply = product.supply - payout;
        product.supply = uint96(supply);

        // Create and add a new bond, update the bond counter
        bondId = bondCounter;
        mapUserBonds[bondId] = Bond(msg.sender, uint96(payout), uint32(expiry), uint32(productId));
        bondCounter = uint32(bondId + 1);

        // Deposit that token amount to mint OLAS tokens in exchange
        ITreasury(treasury).depositTokenForOLAS(msg.sender, tokenAmount, token, payout);

        emit CreateBond(token, productId, payout, tokenAmount);
    }

    /// @dev Redeem account bonds.
    /// @param bondIds Bond Ids to redeem.
    /// @return payout Total payout sent in OLAS tokens.
    ///#if_succeeds {:msg "payout > 0" }  payout > 0;
    ///#if_succeeds {:msg "msg.sender only and delete" } old(forall (uint k in bondIds) mapUserBonds[bondIds[k]].account == msg.sender);   
    function redeem(uint256[] memory bondIds) public returns (uint256 payout) {
        for (uint256 i = 0; i < bondIds.length; i++) {
            // Get the amount to pay and the maturity status
            uint256 pay = mapUserBonds[bondIds[i]].payout;
            bool matured = (block.timestamp >= mapUserBonds[bondIds[i]].maturity) && (pay > 0);

            // Revert if the bond does not exist or is not matured yet
            if (!matured) {
                revert BondNotRedeemable(bondIds[i]);
            }

            // Check that the msg.sender is the owner of the bond
            if (mapUserBonds[bondIds[i]].account != msg.sender) {
                revert OwnerOnly(msg.sender, mapUserBonds[bondIds[i]].account);
            }

            // Delete the Bond struct and release the gas
            uint256 productId = mapUserBonds[bondIds[i]].productId;
            delete mapUserBonds[bondIds[i]];
            payout += pay;

            // Close the program if it was not yet closed
            if (mapBondProducts[productId].expiry > 0) {
                uint96 supply = mapBondProducts[productId].supply;
                // Refund unused OLAS supply from the program if not used completely
                if (supply > 0) {
                    ITokenomics(tokenomics).refundFromBondProgram(supply);
                }
                address token = mapBondProducts[productId].token;
                delete mapBondProducts[productId];

                emit CloseProduct(token, productId);
            }
        }
        // No reentrancy risk here since it's the last operation, and originated from the OLAS token
        // No need to check for the return value, since it either reverts or returns true, see the ERC20 implementation
        IERC20(olas).transfer(msg.sender, payout);
    }

    /// @dev Gets bond Ids of all pending bonds for the account address.
    /// @param account Account address to query bonds for.
    /// @param matured Flag to record matured bonds only or all of them.
    /// @return bondIds Pending bond Ids.
    /// @return payout Cumulative expected OLAS payout.
    function getPendingBonds(address account, bool matured) external view
        returns (uint256[] memory bondIds, uint256 payout)
    {
        uint256 numAccountBonds;
        // Calculate the number of pending bonds
        uint256 numBonds = bondCounter;
        bool[] memory positions = new bool[](numBonds);
        // Record the bond number if it belongs to the account address and was not yet redeemed
        for (uint256 i = 0; i < numBonds; i++) {
            if (mapUserBonds[i].account == account && mapUserBonds[i].payout > 0) {
                // Check if requested bond is not matured but owned by the account address
                if (!matured ||
                    // Or if the requested bond is matured, i.e., the bond maturity timestamp passed
                    mapUserBonds[i].maturity < block.timestamp)
                {
                    positions[i] = true;
                    ++numAccountBonds;
                    payout += mapUserBonds[i].payout;
                }
            }
        }

        // Form pending bonds index array
        bondIds = new uint256[](numAccountBonds);
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
        matured = (block.timestamp >= mapUserBonds[bondId].maturity) && payout > 0;
    }

    /// @dev Creates a new bond product.
    /// @param token LP token to be deposited for pairs like OLAS-DAI, OLAS-ETH, etc.
    /// @param priceLP LP token price with 18 additional decimals.
    /// @param supply Supply in OLAS tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    ///#if_succeeds {:msg "productCounter increases" } productCounter == old(productCounter + 1);
    ///#if_succeeds {:msg "isActive" } mapBondProducts[productId].supply > 0 && mapBondProducts[productId].expiry > block.timestamp;
    function create(address token, uint256 priceLP, uint256 supply, uint256 vesting) external returns (uint256 productId) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the pool liquidity as the LP price being greater than zero
        if (priceLP == 0) {
            revert ZeroValue();
        }

        // Check if the LP token is enabled
        if (!ITreasury(treasury).isEnabled(token)) {
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
        mapBondProducts[productId] = Product(priceLP, token, uint96(supply), uint32(expiry));
        productCounter = uint32(productId + 1);
        emit CreateProduct(token, productId, supply);
    }

    /// @dev Close a bonding product.
    /// @notice This will terminate the program regardless of the expiration time.
    /// @param productId Product Id.
    ///#if_succeeds {:msg "productCounter not touched" } productCounter == old(productCounter);
    ///#if_succeeds {:msg "success closed" } mapBondProducts[productId].expiry == 0 || mapBondProducts[productId].supply == 0;
    function close(uint256 productId) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check if the product is still open
        if (mapBondProducts[productId].expiry == 0) {
            revert ProductClosed(productId);
        }

        uint96 supply = mapBondProducts[productId].supply;
        // Refund unused OLAS supply from the program if not used completely
        if (supply > 0) {
            ITokenomics(tokenomics).refundFromBondProgram(supply);
        }
        address token = mapBondProducts[productId].token;
        delete mapBondProducts[productId];
        
        emit CloseProduct(token, productId);
    }

    /// @dev Gets activity information about a given product.
    /// @param productId Product Id.
    /// @return status True if the product is active.
    function isActiveProduct(uint256 productId) external view returns (bool status) {
        status = (mapBondProducts[productId].supply > 0 && mapBondProducts[productId].expiry > block.timestamp);
    }

    /// @dev Gets an array of all active product Ids for a specific token.
    /// @return productIds Active product Ids.
    function getActiveProducts() external view returns (uint256[] memory productIds) {
        // Calculate the number of active products
        uint256 numProducts = productCounter;
        bool[] memory positions = new bool[](numProducts);
        uint256 numActive;
        for (uint256 i = 0; i < numProducts; i++) {
            if (mapBondProducts[i].supply > 0 && mapBondProducts[i].expiry > block.timestamp) {
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
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP) {
        return IGenericBondCalculator(bondCalculator).getCurrentPriceLP(token);
    }
}
