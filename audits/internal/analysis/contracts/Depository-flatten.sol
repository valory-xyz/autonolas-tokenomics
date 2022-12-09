// The following code is from flattening this file: Depository.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// The following code is from flattening this import statement in: Depository.sol
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// The following code is from flattening this import statement in: Depository.sol
// import "./GenericTokenomics.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/GenericTokenomics.sol
pragma solidity ^0.8.17;

// The following code is from flattening this import statement in: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/GenericTokenomics.sol
// import "./interfaces/IErrorsTokenomics.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/IErrorsTokenomics.sol
pragma solidity ^0.8.17;

/// @dev Errors.
interface IErrorsTokenomics {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Only `owner` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param owner Required sender address as an owner.
    error OwnerOnly(address sender, address owner);

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Wrong length of two arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Number of values in a second array.
    error WrongArrayLength(uint256 numValues1, uint256 numValues2);

    /// @dev Service Id does not exist in registry records.
    /// @param serviceId Service Id.
    error ServiceDoesNotExist(uint256 serviceId);

    /// @dev Zero value when it has to be different from zero.
    error ZeroValue();

    /// @dev Non-zero value when it has to be zero.
    error NonZeroValue();

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Service termination block has been reached. Service is terminated.
    /// @param teminationBlock The termination block.
    /// @param curBlock Current block.
    /// @param serviceId Service Id.
    error ServiceTerminated(uint256 teminationBlock, uint256 curBlock, uint256 serviceId);

    /// @dev Token is disabled or not whitelisted.
    /// @param tokenAddress Address of a token.
    error UnauthorizedToken(address tokenAddress);

    /// @dev Provided token address is incorrect.
    /// @param provided Provided token address.
    /// @param expected Expected token address.
    error WrongTokenAddress(address provided, address expected);

    /// @dev Bond is not redeemable (does not exist or not matured).
    /// @param bondId Bond Id.
    error BondNotRedeemable(uint256 bondId);

    /// @dev The product is expired.
    /// @param tokenAddress Address of a token.
    /// @param productId Product Id.
    /// @param deadline The program expiry time.
    /// @param curTime Current timestamp.
    error ProductExpired(address tokenAddress, uint256 productId, uint256 deadline, uint256 curTime);

    /// @dev The product is already closed.
    /// @param productId Product Id.
    error ProductClosed(uint256 productId);

    /// @dev The product supply is low for the requested payout.
    /// @param tokenAddress Address of a token.
    /// @param productId Product Id.
    /// @param requested Requested payout.
    /// @param actual Actual supply left.
    error ProductSupplyLow(address tokenAddress, uint256 productId, uint256 requested, uint256 actual);

    /// @dev Incorrect amount received / provided.
    /// @param provided Provided amount is lower.
    /// @param expected Expected amount.
    error AmountLowerThan(uint256 provided, uint256 expected);

    /// @dev Wrong amount received / provided.
    /// @param provided Provided amount.
    /// @param expected Expected amount.
    error WrongAmount(uint256 provided, uint256 expected);

    /// @dev Insufficient token allowance.
    /// @param provided Provided amount.
    /// @param expected Minimum expected amount.
    error InsufficientAllowance(uint256 provided, uint256 expected);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param value Value.
    error TransferFailed(address token, address from, address to, uint256 value);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();

    /// @dev maxBond parameter is locked and cannot be updated.
    error MaxBondUpdateLocked();

    /// @dev Rejects the max bond adjustment.
    /// @param maxBondAmount Max bond amount available at the moment.
    /// @param delta Delta bond amount to be subtracted from the maxBondAmount.
    error RejectMaxBondAdjustment(uint256 maxBondAmount, uint256 delta);

    /// @dev Failure of treasury re-balance during the reward allocation.
    /// @param epochNumber Epoch number.
    error TreasuryRebalanceFailed(uint256 epochNumber);

    /// @dev Operation with a wrong component / agent Id.
    /// @param unitId Component / agent Id.
    /// @param unitType Type of the unit (component / agent).
    error WrongUnitId(uint256 unitId, uint256 unitType);

    /// @dev The donator address is blacklisted.
    /// @param account Donator account address.
    error DonatorBlacklisted(address account);

    /// @dev The contract is already initialized.
    error AlreadyInitialized();

    /// @dev The contract has to be delegate-called via proxy.
    error DelegatecallOnly();

    /// @dev The contract is paused.
    error Paused();
}


/// @title GenericTokenomics - Smart contract for generic tokenomics contract template
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract GenericTokenomics is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event DepositoryUpdated(address indexed depository);
    event DispenserUpdated(address indexed dispenser);

    enum TokenomicsRole {
        Tokenomics,
        Treasury,
        Depository,
        Dispenser
    }

    // Address of unused tokenomics roles
    address public constant SENTINEL_ADDRESS = address(0x000000000000000000000000000000000000dEaD);
    // Tokenomics proxy address slot
    // keccak256("PROXY_TOKENOMICS") = "0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f"
    bytes32 public constant PROXY_TOKENOMICS = 0xbd5523e7c3b6a94aa0e3b24d1120addc2f95c7029e097b466b2bedc8d4b4362f;
    // Reentrancy lock
    uint8 internal _locked;
    // Tokenomics role
    TokenomicsRole public tokenomicsRole;
    // Owner address
    address public owner;
    // OLAS token address
    address public olas;
    // Tkenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;
    // Depository contract address
    address public depository;
    // Dispenser contract address
    address public dispenser;

    /// @dev Generic Tokenomics initializer.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    function initialize(
        address _olas,
        address _tokenomics,
        address _treasury,
        address _depository,
        address _dispenser,
        TokenomicsRole _tokenomicsRole
    ) internal
    {
        // Check if the contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        _locked = 1;
        olas = _olas;
        tokenomics = _tokenomics;
        treasury = _treasury;
        depository = _depository;
        dispenser = _dispenser;
        tokenomicsRole = _tokenomicsRole;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
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
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    function changeManagers(address _tokenomics, address _treasury, address _depository, address _dispenser) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Tokenomics cannot change its own address
        if (_tokenomics != address(0) && tokenomicsRole != TokenomicsRole.Tokenomics) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
        // Treasury cannot change its own address, also dispenser cannot change treasury address
        if (_treasury != address(0) && tokenomicsRole != TokenomicsRole.Treasury) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
        // Depository cannot change its own address, also dispenser cannot change depository address
        if (_depository != address(0) && tokenomicsRole != TokenomicsRole.Depository && tokenomicsRole != TokenomicsRole.Dispenser) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        // Dispenser cannot change its own address, also depository cannot change dispenser address
        if (_dispenser != address(0) && tokenomicsRole != TokenomicsRole.Dispenser && tokenomicsRole != TokenomicsRole.Depository) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
    }
}    

// The following code is from flattening this import statement in: Depository.sol
// import "./interfaces/IGenericBondCalculator.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/IGenericBondCalculator.sol
pragma solidity ^0.8.17;

/// @dev Interface for generic bond calculator.
interface IGenericBondCalculator {
    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(uint256 tokenAmount, uint256 priceLP) external view
        returns (uint256 amountOLAS);

    /// @dev Get reserveX/reserveY at the time of product creation.
    /// @param token Token address.
    /// @return priceLP Resulting reserve ratio.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP);

    /// @dev Checks if the token is a UniswapV2Pair.
    /// @param token Address of an LP token.
    /// @return success True if successful.
    function checkLP(address token) external returns (bool success);
}

// The following code is from flattening this import statement in: Depository.sol
// import "./interfaces/ITokenomics.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/ITokenomics.sol
pragma solidity ^0.8.17;

/// @dev Interface for tokenomics management.
interface ITokenomics {
    /// @dev Gets effective bond (bond left).
    /// @return Effective bond.
    function effectiveBond() external pure returns (uint256);

    /// @dev Record global data to the checkpoint
    function checkpoint() external returns (bool);

    /// @dev Tracks the deposited ETH service donations during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param account Account address.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    /// @return donationETH Overall service donation amount in ETH.
    function trackServiceDonations(address account, uint256[] memory serviceIds, uint256[] memory amounts) external
        returns (uint256 donationETH);

    /// @dev Reserves OLAS amount from the effective bond to be minted during a bond program.
    /// @notice Programs exceeding the limit in the epoch are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return True if effective bond threshold is not reached.
    function reserveAmountForBondProgram(uint256 amount) external returns(bool);

    /// @dev Refunds unused bond program amount.
    /// @param amount Amount to be refunded from the bond program.
    function refundFromBondProgram(uint256 amount) external;

    /// @dev Gets component / agent owner incentives and clears the balances.
    /// @param account Account address.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerIncentives(address account, uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp);

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf);

    /// @dev Gets the service registry contract address
    /// @return Service registry contract address;
    function serviceRegistry() external view returns (address);
}

// The following code is from flattening this import statement in: Depository.sol
// import "./interfaces/ITreasury.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/ITreasury.sol
pragma solidity ^0.8.17;

/// @dev Interface for treasury management.
interface ITreasury {
    /// @dev Allows approved address to deposit an asset for OLAS.
    /// @param account Account address making a deposit of LP tokens for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olaMintAmount) external;

    /// @dev Deposits service donations in ETH.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable;

    /// @dev Gets information about token being enabled.
    /// @param token Token address.
    /// @return enabled True is token is enabled.
    function isEnabled(address token) external view returns (bool enabled);

    /// @dev Check if the token is UniswapV2Pair.
    /// @param token Address of a token.
    function checkPair(address token) external returns (bool);

    /// @dev Withdraws ETH and / or OLAS amounts to the requested account address.
    /// @notice Only dispenser contract can call this function.
    /// @notice Reentrancy guard is on a dispenser side.
    /// @notice Zero account address is not possible, since the dispenser contract interacts with msg.sender.
    /// @param account Account address.
    /// @param accountRewards Amount of account rewards.
    /// @param accountTopUps Amount of account top-ups.
    /// @return success True if the function execution is successful.
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external returns (bool success);

    /// @dev Re-balances treasury funds to account for the treasury reward for a specific epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @return success True, if the function execution is successful.
    function rebalanceTreasury(uint256 treasuryRewards) external returns (bool success);
}


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
        // We assume that the number of products will not be bigger than the number of seconds
        uint32 productId;
    }

    // The size of the struct is 256 + 160 + 96 + 32 + 224 = 768 bits (3 full slots)
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
        // LP tokens purchased
        // Reserves are 112 bits in size, we assume that their calculations will be limited by reserves0 x reserves1
        uint224 purchased;
    }

    // Individual bond counter
    // We assume that the number of bonds will not be bigger than the number of seconds
    uint32 bondCounter;
    // Bond product counter
    // We assume that the number of products will not be bigger than the number of seconds
    uint32 productCounter;

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
    constructor(address _olas, address _treasury, address _tokenomics, address _bondCalculator)
        GenericTokenomics()
    {
        super.initialize(_olas, _tokenomics, _treasury, address(this), SENTINEL_ADDRESS, TokenomicsRole.Depository);
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

        // Decrease the supply for the amount of payout, increase number of purchased tokens and sold OLAS tokens
        uint256 supply = product.supply - payout;
        product.supply = uint96(supply);
        uint256 purchased = product.purchased + tokenAmount;
        product.purchased = uint224(purchased);

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
        IERC20(olas).transfer(msg.sender, payout);
    }

    /// @dev Gets bond Ids of all pending bonds for the account address.
    /// @param account Account address to query bonds for.
    /// @return bondIds Pending bond Ids.
    /// @return payout Cumulative expected OLAS payout.
    function getPendingBonds(address account) external view returns (uint256[] memory bondIds, uint256 payout) {
        uint256 numAccountBonds;
        // Calculate the number of pending bonds
        uint256 numBonds = bondCounter;
        bool[] memory positions = new bool[](numBonds);
        // Record the bond number if it belongs to the account address and was not yet redeemed
        for (uint256 i = 0; i < numBonds; i++) {
            if (mapUserBonds[i].account == account && mapUserBonds[i].payout > 0) {
                positions[i] = true;
                ++numAccountBonds;
                payout += mapUserBonds[i].payout;
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
    function create(address token, uint256 priceLP, uint256 supply, uint256 vesting) external returns (uint256 productId) {
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
        mapBondProducts[productId] = Product(priceLP, token, uint96(supply), uint32(expiry), 0);
        productCounter = uint32(productId + 1);
        emit CreateProduct(token, productId, supply);
    }

    /// @dev Close a bonding product.
    /// @notice This will terminate the program regardless of the expiration time.
    /// @param productId Product Id.
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



