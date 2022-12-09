// The following code is from flattening this file: Treasury.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// The following code is from flattening this import statement in: Treasury.sol
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

// The following code is from flattening this import statement in: Treasury.sol
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

// The following code is from flattening this import statement in: Treasury.sol
// import "./interfaces/IOLAS.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/IOLAS.sol
pragma solidity ^0.8.17;

interface IOLAS {
    /// @dev Mints OLA tokens.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function mint(address account, uint256 amount) external;

    /// @dev Provides OLA token time launch.
    /// @return Time launch.
    function timeLaunch() external view     returns (uint256);

    /// @dev Gets the reminder of OLA possible for the mint.
    /// @return remainder OLA token remainder.
    function inflationRemainder() external view returns (uint256 remainder);

    /// @dev Provides the amount of decimals.
    /// @return Numebr of decimals.
    function decimals() external view returns(uint8);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True is the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

// The following code is from flattening this import statement in: Treasury.sol
// import "./interfaces/IServiceTokenomics.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/IServiceTokenomics.sol
pragma solidity ^0.8.17;

/// @dev Required interface for the service manipulation.
interface IServiceTokenomics {
    enum UnitType {
        Component,
        Agent
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) external view returns (bool);

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(UnitType unitType, uint256 serviceId) external view
        returns (uint256 numUnitIds, uint32[] memory unitIds);

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount);
}

// The following code is from flattening this import statement in: Treasury.sol
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


/*
* In this contract we consider both ETH and OLAS tokens.
* For ETH tokens, there are currently about 121 million tokens.
* Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply.
* Lately the inflation rate was lower and could actually be deflationary.
*
* For OLAS tokens, the initial numbers will be as follows:
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

/// @title Treasury - Smart contract for managing OLAS Treasury
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Treasury is GenericTokenomics {

    event DepositTokenFromAccount(address indexed account, address indexed token, uint256 tokenAmount, uint256 olasAmount);
    event DepositETHFromServices(address indexed sender, uint256 donation);
    event Withdraw(address indexed token, uint256 tokenAmount);
    event TokenReserves(address indexed token, uint256 reserves);
    event EnableToken(address indexed token);
    event DisableToken(address indexed token);
    event TransferToDispenserOLAS(uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);
    event TreasuryPaused();
    event TreasuryUnpaused();

    enum TokenState {
        NonExistent,
        Enabled,
        Disabled
    }
    
    struct TokenInfo {
        // State of a token in this treasury
        TokenState state;
        // Reserves of a token
        // Reserves are 112 bits in size, we assume that their calculations will be limited by reserves0 x reserves1
        uint224 reserves;
    }

    // ETH received from services
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHFromServices;
    // ETH owned by treasury
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHOwned;
    // Contract pausing
    uint8 public paused = 1;
    // Token address => token info related to bonding
    mapping(address => TokenInfo) public mapTokens;
    // Set of registered tokens
    address[] public tokenRegistry;

    // A well-known representation of an ETH as address
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Treasury constructor.
    /// @param _olas OLAS token address.
    /// @param _depository Depository address.
    /// @param _tokenomics Tokenomics address.
    /// @param _dispenser Dispenser address.
    constructor(address _olas, address _depository, address _tokenomics, address _dispenser) payable
        GenericTokenomics()
    {
        super.initialize(_olas, _tokenomics, address(this), _depository, _dispenser, TokenomicsRole.Treasury);
        ETHOwned = uint96(msg.value);
    }

    /// @dev Receives ETH.
    receive() external payable {
        uint96 amount = ETHOwned;
        amount += uint96(msg.value);
        ETHOwned = amount;
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @dev Allows the depository to deposit an asset for OLAS.
    /// @notice Only depository contract can call this function.
    /// @param account Account address making a deposit of LP tokens for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olasMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olasMintAmount) external
    {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        TokenInfo storage tokenInfo = mapTokens[token];
        // Check if the token is authorized by the registry
        if (tokenInfo.state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        uint256 reserves = tokenInfo.reserves + tokenAmount;
        tokenInfo.reserves = uint224(reserves);

        // Uniswap allowance implementation does not revert with the accurate message, check before the transfer is engaged
        if (IERC20(token).allowance(account, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(token).allowance((account), address(this)), tokenAmount);
        }

        // Transfer tokens from account to treasury and add to the token treasury reserves
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 realization has a standard transferFrom() function that returns a boolean value
        IERC20(token).transferFrom(account, address(this), tokenAmount);

        // Mint specified number of OLAS tokens corresponding to tokens bonding deposit
        // The olasMintAmount is guaranteed by the product supply limit, which is limited by the effectiveBond
        IOLAS(olas).mint(msg.sender, olasMintAmount);

        emit DepositTokenFromAccount(account, token, tokenAmount, olasMintAmount);
    }

    /// @dev Deposits service donations in ETH.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable {
        if (msg.value == 0) {
            revert ZeroValue();
        }

        // Check for the same length of arrays
        uint256 numServices = serviceIds.length;
        if (amounts.length != numServices) {
            revert WrongArrayLength(numServices, amounts.length);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < numServices; ++i) {
            if (amounts[i] == 0) {
                revert ZeroValue();
            }
            totalAmount += amounts[i];
        }

        // Check if the total transferred amount corresponds to the sum of amounts from services
        if (msg.value != totalAmount) {
            revert WrongAmount(msg.value, totalAmount);
        }

        // Accumulate received donation from services
        uint256 donationETH = ITokenomics(tokenomics).trackServiceDonations(msg.sender, serviceIds, amounts);
        donationETH += ETHFromServices;
        ETHFromServices = uint96(donationETH);

        emit DepositETHFromServices(msg.sender, donationETH);
    }

    /// @dev Allows owner to transfer tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token or ETH address.
    /// @return success True is the transfer is successful.
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // All the LP tokens must go under the bonding condition
        if (token == ETH_TOKEN_ADDRESS) {
            uint96 amountOwned = ETHOwned;
            // Check if treasury has enough amount of owned ETH
            if ((amountOwned + 1) > tokenAmount) {
                // This branch is used to transfer ETH to a specified address
                amountOwned -= uint96(tokenAmount);
                ETHOwned = amountOwned;
                emit Withdraw(address(0), tokenAmount);
                // Send ETH to the specified address
                (success, ) = to.call{value: tokenAmount}("");
                if (!success) {
                    revert TransferFailed(address(0), address(this), to, tokenAmount);
                }
            } else {
                // Insufficient amount of treasury owned ETH
                revert AmountLowerThan(tokenAmount, amountOwned);
            }
        } else {
            TokenInfo storage tokenInfo = mapTokens[token];
            // Only approved token reserves can be used for redemptions
            if (tokenInfo.state != TokenState.Enabled) {
                revert UnauthorizedToken(token);
            }
            // Decrease the global LP token record
            uint256 reserves = tokenInfo.reserves;
            reserves -= tokenAmount;
            tokenInfo.reserves = uint224(reserves);

            success = true;
            emit Withdraw(token, tokenAmount);
            // Transfer LP token
            // We assume that LP tokens enabled in the protocol are safe by default
            // UniswapV2ERC20 realization has a standard transfer() function
            IERC20(token).transfer(to, tokenAmount);
        }
    }

    /// @dev Withdraws ETH and / or OLAS amounts to the requested account address.
    /// @notice Only dispenser contract can call this function.
    /// @notice Reentrancy guard is on a dispenser side.
    /// @notice Zero account address is not possible, since the dispenser contract interacts with msg.sender.
    /// @param account Account address.
    /// @param accountRewards Amount of account rewards.
    /// @param accountTopUps Amount of account top-ups.
    /// @return success True if the function execution is successful.
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external
        returns (bool success)
    {
        // Check if the contract is paused
        if (paused == 2) {
            revert Paused();
        }

        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        uint256 amountETHFromServices = ETHFromServices;
        // Send ETH rewards, if any
        if (accountRewards > 0 && amountETHFromServices >= accountRewards) {
            amountETHFromServices -= accountRewards;
            ETHFromServices = uint96(amountETHFromServices);
            (success, ) = account.call{value: accountRewards}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), treasury, accountRewards);
            }
        }

        // Send OLAS top-ups
        if (accountTopUps > 0) {
            // Tokenomics has already accounted for the account's top-up amount,
            // thus the the mint does not break the inflation schedule
            IOLAS(olas).mint(account, accountTopUps);
            success = true;
            emit TransferToDispenserOLAS(accountTopUps);
        }
    }

    /// @dev Enables a token to be exchanged for OLAS.
    /// @param token Token address.
    function enableToken(address token) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        TokenState state = mapTokens[token].state;
        if (state != TokenState.Enabled) {
            if (state == TokenState.NonExistent) {
                tokenRegistry.push(token);
            }
            mapTokens[token].state = TokenState.Enabled;
            emit EnableToken(token);
        }
    }

    /// @dev Disables a token from the ability to exchange for OLAS.
    /// @param token Token address.
    function disableToken(address token) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        TokenInfo storage tokenInfo = mapTokens[token];
        if (tokenInfo.state != TokenState.Disabled) {
            // The reserves of a token must be zero in order to disable it
            if (tokenInfo.reserves > 0) {
                revert NonZeroValue();
            }
            tokenInfo.state = TokenState.Disabled;
            emit DisableToken(token);
        }
    }

    /// @dev Gets information about token being enabled for bonding.
    /// @param token Token address.
    /// @return enabled True if token is enabled.
    function isEnabled(address token) external view returns (bool enabled) {
        enabled = (mapTokens[token].state == TokenState.Enabled);
    }

    /// @dev Re-balances treasury funds to account for the treasury reward for a specific epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @return success True, if the function execution is successful.
    function rebalanceTreasury(uint256 treasuryRewards) external returns (bool success) {
        // Check if the contract is paused
        if (paused == 2) {
            revert Paused();
        }

        // Check for the tokenomics contract access
        if (msg.sender != tokenomics) {
            revert ManagerOnly(msg.sender, tokenomics);
        }

        // Collect treasury's own reward share
        success = true;
        if (treasuryRewards > 0) {
            uint256 amountETHFromServices = ETHFromServices;
            if (amountETHFromServices >= treasuryRewards) {
                // Update ETH from services value
                amountETHFromServices -= treasuryRewards;
                // Update treasury ETH owned values
                uint256 amountETHOwned = ETHOwned;
                amountETHOwned += treasuryRewards;
                // Assign back to state variables
                ETHOwned = uint96(amountETHOwned);
                ETHFromServices = uint96(amountETHFromServices);
            } else {
                // There is not enough amount from services to allocate to the treasury
                success = false;
            }
        }
    }

    /// @dev Drains slashed funds from the service registry.
    /// @return amount Drained amount.
    function drainServiceSlashedFunds() external returns (uint256 amount) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get the service registry contract address
        address serviceRegistry = ITokenomics(tokenomics).serviceRegistry();
        // Call the service registry drain function
        amount = IServiceTokenomics(serviceRegistry).drain();
    }

    /// @dev Pauses the contract.
    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit TreasuryPaused();
    }

    /// @dev Unpauses the contract.
    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit TreasuryUnpaused();
    }
}



