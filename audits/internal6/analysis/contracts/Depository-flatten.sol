// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

    /// @dev Service was never deployed.
    /// @param serviceId Service Id.
    error ServiceNeverDeployed(uint256 serviceId);

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

    /// @dev Received lower value than the expected one.
    /// @param provided Provided value is lower.
    /// @param expected Expected value.
    error LowerThan(uint256 provided, uint256 expected);

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
    /// @param amount Token amount.
    error TransferFailed(address token, address from, address to, uint256 amount);

    /// @dev Incentives claim has failed.
    /// @param account Account address.
    /// @param reward Reward amount.
    /// @param topUp Top-up amount.
    error ClaimIncentivesFailed(address account, uint256 reward, uint256 topUp);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();

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

    /// @dev Caught an operation that is not supposed to happen in the same block.
    error SameBlockNumberViolation();
}


// File contracts/interfaces/IToken.sol
/// @dev Generic token interface for IERC20 and IERC721 tokens.
interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @dev Gets the total amount of tokens stored by the contract.
    /// @return Amount of tokens.
    function totalSupply() external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets remaining number of tokens that the `spender` can transfer on behalf of `owner`.
    /// @param owner Token owner.
    /// @param spender Account address that is able to transfer tokens on behalf of the owner.
    /// @return Token amount allowed to be transferred.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}


// File contracts/interfaces/ITokenomics.sol
/// @dev Interface for tokenomics management.
interface ITokenomics {
    /// @dev Gets effective bond (bond left).
    /// @return Effective bond.
    function effectiveBond() external pure returns (uint256);

    /// @dev Record global data to the checkpoint
    function checkpoint() external returns (bool);

    /// @dev Tracks the deposited ETH service donations during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param donator Donator account address.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    /// @param donationETH Overall service donation amount in ETH.
    function trackServiceDonations(
        address donator,
        uint256[] memory serviceIds,
        uint256[] memory amounts,
        uint256 donationETH
    ) external;

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


// File contracts/interfaces/ITreasury.sol
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


// File lib/solmate/src/tokens/ERC721.sol
/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) internal _ownerOf;

    mapping(address => uint256) internal _balanceOf;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        require((owner = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == _ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];

        require(owner != address(0), "NOT_MINTED");

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}


// File contracts/Depository.sol
interface IBondCalculator {
    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism accounting for dynamic IDF.
    /// @param account Account address.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @param bondVestingTime Bond vesting time.
    /// @param productMaxVestingTime Product max vesting time.
    /// @param productSupply Current product supply.
    /// @param productPayout Current product payout.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(
        address account,
        uint256 tokenAmount,
        uint256 priceLP,
        uint256 bondVestingTime,
        uint256 productMaxVestingTime,
        uint256 productSupply,
        uint256 productPayout
    ) external view returns (uint256 amountOLAS);

    /// @dev Gets current reserves of OLAS / totalSupply of Uniswap V2-like LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP);
}

/// @dev Wrong amount received / provided.
/// @param provided Provided amount.
/// @param expected Expected amount.
error WrongAmount(uint256 provided, uint256 expected);

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

// The size of the struct is 96 + 32 * 2 = 160 (1 slot)
struct Bond {
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

// The size of the struct is 160 + 96 + 160 + 96 + 32 = 2 * 256 + 32 (3 slots)
struct Product {
    // priceLP (reserve0 / totalSupply or reserve1 / totalSupply) with 18 additional decimals
    // priceLP = 2 * r0/L * 10^18 = 2*r0*10^18/sqrt(r0*r1) ~= 61 + 96 - sqrt(96 * 112) ~= 53 bits (if LP is balanced)
    // or 2* r0/sqrt(r0) * 10^18 => 87 bits + 60 bits = 147 bits (if LP is unbalanced)
    uint160 priceLP;
    // Supply of remaining OLAS tokens
    // After 10 years, the OLAS inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 supply;
    // Token to accept as a payment
    address token;
    // Current OLAS payout
    // This value is bound by the initial total supply
    uint96 payout;
    // Max bond vesting time
    // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
    uint32 vesting;
}

/// @title Bond Depository - Smart contract for OLAS Bond Depository
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Depository is ERC721, IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event BondCalculatorUpdated(address indexed bondCalculator);
    event CreateBond(address indexed token, uint256 indexed productId, address indexed owner, uint256 bondId,
        uint256 amountOLAS, uint256 tokenAmount, uint256 maturity);
    event RedeemBond(uint256 indexed productId, address indexed owner, uint256 bondId, uint256 payout);
    event CreateProduct(address indexed token, uint256 indexed productId, uint256 supply, uint256 priceLP,
        uint256 vesting);
    event CloseProduct(address indexed token, uint256 indexed productId, uint256 supply);

    // Minimum bond vesting value
    uint256 public constant MIN_VESTING = 1 days;
    // Depository version number
    string public constant VERSION = "1.1.0";
    // Base URI
    string public baseURI;
    // Owner address
    address public owner;
    // Individual bond counter
    // We assume that the number of bonds will not be bigger than the number of seconds
    uint256 public totalSupply;
    // Bond product counter
    // We assume that the number of products will not be bigger than the number of seconds
    uint256 public productCounter;
    // Minimum amount of supply such that any value below is given to the bonding account in order to close the product
    uint256 public minOLASLeftoverAmount;

    // OLAS token address
    address public immutable olas;
    // Tokenomics contract address
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
    /// @param _name Service contract name.
    /// @param _symbol Agent contract symbol.
    /// @param _baseURI Agent registry token base URI.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _tokenomics Tokenomics address.
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        address _olas,
        address _tokenomics,
        address _treasury,
        address _bondCalculator
    )
        ERC721(_name, _symbol)
    {
        // Check for at least one zero contract address
        if (_olas == address(0) || _tokenomics == address(0) || _treasury == address(0) || _bondCalculator == address(0)) {
            revert ZeroAddress();
        }

        // Check for base URI zero value
        if (bytes(_baseURI).length == 0) {
            revert ZeroValue();
        }

        olas = _olas;
        tokenomics = _tokenomics;
        treasury = _treasury;
        bondCalculator = _bondCalculator;
        baseURI = _baseURI;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    /// #if_succeeds {:msg "Changing owner"} old(owner) == msg.sender ==> owner == newOwner;
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
    /// #if_succeeds {:msg "tokenomics changed"} _tokenomics != address(0) ==> tokenomics == _tokenomics;
    /// #if_succeeds {:msg "treasury changed"} _treasury != address(0) ==> treasury == _treasury;
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
    /// #if_succeeds {:msg "bondCalculator changed"} _bondCalculator != address(0) ==> bondCalculator == _bondCalculator;
    function changeBondCalculator(address _bondCalculator) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (_bondCalculator != address(0)) {
            bondCalculator = _bondCalculator;
            emit BondCalculatorUpdated(_bondCalculator);
        }
    }

    /// @dev Creates a new bond product.
    /// @param token LP token to be deposited for pairs like OLAS-DAI, OLAS-ETH, etc.
    /// @param priceLP LP token price with 18 additional decimals.
    /// @param supply Supply in OLAS tokens.
    /// @param vesting Vesting period (in seconds).
    /// @return productId New bond product Id.
    /// #if_succeeds {:msg "productCounter increases"} productCounter == old(productCounter) + 1;
    /// #if_succeeds {:msg "isActive"} mapBondProducts[productId].supply > 0 && mapBondProducts[productId].vesting == vesting;
    function create(address token, uint256 priceLP, uint256 supply, uint256 vesting) external returns (uint256 productId) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the pool liquidity as the LP price being greater than zero
        if (priceLP == 0) {
            revert ZeroValue();
        }

        // Check the priceLP limit value
        if (priceLP > type(uint160).max) {
            revert Overflow(priceLP, type(uint160).max);
        }

        // Check that the supply is greater than zero
        if (supply == 0) {
            revert ZeroValue();
        }

        // Check the supply limit value
        if (supply > type(uint96).max) {
            revert Overflow(supply, type(uint96).max);
        }

        // Check the vesting minimum limit value
        if (vesting < MIN_VESTING) {
            revert LowerThan(vesting, MIN_VESTING);
        }

        // Check for the maturity time overflow for the current timestamp
        uint256 maturity = block.timestamp + vesting;
        if (maturity > type(uint32).max) {
            revert Overflow(maturity, type(uint32).max);
        }

        // Check if the LP token is enabled
        if (!ITreasury(treasury).isEnabled(token)) {
            revert UnauthorizedToken(token);
        }

        // Check if the bond amount is beyond the limits
        if (!ITokenomics(tokenomics).reserveAmountForBondProgram(supply)) {
            revert LowerThan(ITokenomics(tokenomics).effectiveBond(), supply);
        }

        // Push newly created bond product into the list of products
        productId = productCounter;
        mapBondProducts[productId] = Product(uint160(priceLP), uint96(supply), token, 0, uint32(vesting));
        // Even if we create a bond product every second, 2^32 - 1 is enough for the next 136 years
        productCounter = productId + 1;
        emit CreateProduct(token, productId, supply, priceLP, vesting);
    }

    /// @dev Closes bonding products.
    /// @notice This will terminate programs regardless of their vesting time.
    /// @param productIds Set of product Ids.
    /// @return closedProductIds Set of closed product Ids.
    /// #if_succeeds {:msg "productCounter not touched"} productCounter == old(productCounter);
    /// #if_succeeds {:msg "success closed"} forall (uint k in productIds) mapBondProducts[productIds[k]].vesting == 0 && mapBondProducts[productIds[k]].supply == 0;
    function close(uint256[] memory productIds) external returns (uint256[] memory closedProductIds) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Calculate the number of closed products
        uint256 numProducts = productIds.length;
        uint256[] memory ids = new uint256[](numProducts);
        uint256 numClosedProducts;
        // Traverse to close all possible products
        for (uint256 i = 0; i < numProducts; ++i) {
            uint256 productId = productIds[i];
            // Check if the product is still open by getting its supply amount
            uint256 supply = mapBondProducts[productId].supply;
            // The supply is greater than zero only if the product is active, otherwise it is already closed
            if (supply > 0) {
                // Refund unused OLAS supply from the product if it was not used by the product completely
                ITokenomics(tokenomics).refundFromBondProgram(supply);
                address token = mapBondProducts[productId].token;
                delete mapBondProducts[productId];

                ids[numClosedProducts] = productIds[i];
                ++numClosedProducts;
                emit CloseProduct(token, productId, supply);
            }
        }

        // Get the correct array size of closed product Ids
        closedProductIds = new uint256[](numClosedProducts);
        for (uint256 i = 0; i < numClosedProducts; ++i) {
            closedProductIds[i] = ids[i];
        }
    }

    /// @dev Deposits tokens in exchange for a bond from a specified product.
    /// @param productId Product Id.
    /// @param tokenAmount Token amount to deposit for the bond.
    /// @return payout The amount of OLAS tokens due.
    /// @return maturity Timestamp for payout redemption.
    /// @return bondId Id of a newly created bond.
    /// #if_succeeds {:msg "token is valid"} mapBondProducts[productId].token != address(0);
    /// #if_succeeds {:msg "input supply is non-zero"} old(mapBondProducts[productId].supply) > 0 && mapBondProducts[productId].supply <= type(uint96).max;
    /// #if_succeeds {:msg "vesting is non-zero"} mapBondProducts[productId].vesting > 0 && mapBondProducts[productId].vesting + block.timestamp <= type(uint32).max;
    /// #if_succeeds {:msg "bond Id"} totalSupply == old(totalSupply) + 1 && totalSupply <= type(uint32).max;
    /// #if_succeeds {:msg "payout"} old(mapBondProducts[productId].supply) == mapBondProducts[productId].supply + payout;
    /// #if_succeeds {:msg "OLAS balances"} IToken(mapBondProducts[productId].token).balanceOf(treasury) == old(IToken(mapBondProducts[productId].token).balanceOf(treasury)) + tokenAmount;
    function deposit(uint256 productId, uint256 tokenAmount, uint256 bondVestingTime) external
        returns (uint256 payout, uint256 maturity, uint256 bondId)
    {
        // Check the token amount
        if (tokenAmount == 0) {
            revert ZeroValue();
        }

        // Get the bonding product
        Product storage product = mapBondProducts[productId];

        // Check for the product supply, which is zero if the product was closed or never existed
        uint256 supply = product.supply;
        if (supply == 0) {
            revert ProductClosed(productId);
        }

        uint256 productMaxVestingTime = product.vesting;
        // Calculate vesting limits
        if (bondVestingTime < MIN_VESTING) {
            revert LowerThan(bondVestingTime, MIN_VESTING);
        }
        if (bondVestingTime > productMaxVestingTime) {
            revert Overflow(bondVestingTime, productMaxVestingTime);
        }
        // Calculate the bond maturity based on its vesting time
        maturity = block.timestamp + bondVestingTime;
        // Check for the time limits
        if (maturity > type(uint32).max) {
            revert Overflow(maturity, type(uint32).max);
        }

        // Get the LP token address
        address token = product.token;

        // Calculate the payout in OLAS tokens based on the LP pair with the inverse discount factor (IDF) calculation
        // Note that payout cannot be zero since the price LP is non-zero, otherwise the product would not be created
        payout = IBondCalculator(bondCalculator).calculatePayoutOLAS(msg.sender, tokenAmount, product.priceLP,
            bondVestingTime, productMaxVestingTime, supply, product.payout);

        // Check for the sufficient supply
        if (payout > supply) {
            revert ProductSupplyLow(token, productId, payout, supply);
        }

        // Decrease the supply for the amount of payout
        supply -= payout;
        // Adjust payout and set supply to zero if supply drops below the min defined value
        if (supply < minOLASLeftoverAmount) {
            payout += supply;
            supply = 0;
        }
        product.supply = uint96(supply);
        product.payout += uint96(payout);

        // Create and mint a new bond
        bondId = totalSupply;
        // Safe mint is needed since contracts can create bonds as well
        _safeMint(msg.sender, bondId);
        mapUserBonds[bondId] = Bond(uint96(payout), uint32(maturity), uint32(productId));

        // Increase bond total supply
        totalSupply = bondId + 1;

        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        // Deposit that token amount to mint OLAS tokens in exchange
        ITreasury(treasury).depositTokenForOLAS(msg.sender, tokenAmount, token, payout);

        // Check the balance after the OLAS mint
        olasBalance = IToken(olas).balanceOf(address(this)) - olasBalance;

        if (olasBalance != payout) {
            revert WrongAmount(olasBalance, payout);
        }

        // Close the product if the supply becomes zero
        if (supply == 0) {
            delete mapBondProducts[productId];
            emit CloseProduct(token, productId, supply);
        }

        emit CreateBond(token, productId, msg.sender, bondId, payout, tokenAmount, maturity);
    }

    /// @dev Redeems account bonds.
    /// @param bondIds Bond Ids to redeem.
    /// @return payout Total payout sent in OLAS tokens.
    /// #if_succeeds {:msg "payout > 0"} payout > 0;
    /// #if_succeeds {:msg "msg.sender is the only owner"} old(forall (uint k in bondIds) _ownerOf[bondIds[k]] == msg.sender);
    /// #if_succeeds {:msg "accounts deleted"} forall (uint k in bondIds) _ownerOf[bondIds[k]].account == address(0);
    /// #if_succeeds {:msg "payouts are zeroed"} forall (uint k in bondIds) mapUserBonds[bondIds[k]].payout == 0;
    /// #if_succeeds {:msg "maturities are zeroed"} forall (uint k in bondIds) mapUserBonds[bondIds[k]].maturity == 0;
    function redeem(uint256[] memory bondIds) external returns (uint256 payout) {
        for (uint256 i = 0; i < bondIds.length; ++i) {
            // Get the amount to pay and the maturity status
            uint256 pay = mapUserBonds[bondIds[i]].payout;
            bool matured = block.timestamp >= mapUserBonds[bondIds[i]].maturity;

            // Revert if the bond does not exist or is not matured yet
            if (pay == 0 || !matured) {
                revert BondNotRedeemable(bondIds[i]);
            }

            // Check that the msg.sender is the owner of the bond
            address bondOwner = _ownerOf[bondIds[i]];
            if (bondOwner != msg.sender) {
                revert OwnerOnly(msg.sender, bondOwner);
            }

            // Increase the payout
            payout += pay;

            // Get the productId
            uint256 productId = mapUserBonds[bondIds[i]].productId;

            // Burn the bond NFT
            _burn(bondIds[i]);

            // Delete the Bond struct and release the gas
            delete mapUserBonds[bondIds[i]];
            emit RedeemBond(productId, msg.sender, bondIds[i], pay);
        }

        // Check for the non-zero payout
        if (payout == 0) {
            revert ZeroValue();
        }

        // No reentrancy risk here since it's the last operation, and originated from the OLAS token
        // No need to check for the return value, since it either reverts or returns true, see the ERC20 implementation
        IToken(olas).transfer(msg.sender, payout);
    }

    /// @dev Gets an array of active or inactive product Ids.
    /// @param active Flag to select active or inactive products.
    /// @return productIds Product Ids.
    function getProducts(bool active) external view returns (uint256[] memory productIds) {
        // Calculate the number of existing products
        uint256 numProducts = productCounter;
        bool[] memory positions = new bool[](numProducts);
        uint256 numSelectedProducts;
        // Traverse to find requested products
        for (uint256 i = 0; i < numProducts; ++i) {
            // Product is always active if its supply is not zero, and inactive otherwise
            if ((active && mapBondProducts[i].supply > 0) || (!active && mapBondProducts[i].supply == 0)) {
                positions[i] = true;
                ++numSelectedProducts;
            }
        }

        // Form active or inactive products index array
        productIds = new uint256[](numSelectedProducts);
        uint256 numPos;
        for (uint256 i = 0; i < numProducts; ++i) {
            if (positions[i]) {
                productIds[numPos] = i;
                ++numPos;
            }
        }
    }

    /// @dev Gets activity information about a given product.
    /// @param productId Product Id.
    /// @return status True if the product is active.
    function isActiveProduct(uint256 productId) external view returns (bool status) {
        status = (mapBondProducts[productId].supply > 0);
    }

    /// @dev Gets bond Ids for the account address.
    /// @param account Account address to query bonds for.
    /// @param matured Flag to get matured bonds only or all of them.
    /// @return bondIds Bond Ids.
    /// @return payout Cumulative expected OLAS payout.
    /// #if_succeeds {:msg "matured bonds"} matured == true ==> forall (uint k in bondIds)
    /// mapUserBonds[bondIds[k]].account == account && block.timestamp >= mapUserBonds[bondIds[k]].maturity;
    function getBonds(address account, bool matured) external view
        returns (uint256[] memory bondIds, uint256 payout)
    {
        // Check the address
        if (account == address(0)) {
            revert ZeroAddress();
        }

        uint256 numAccountBonds;
        // Calculate the number of pending bonds
        uint256 numBonds = totalSupply;
        bool[] memory positions = new bool[](numBonds);
        // Record the bond number if it belongs to the account address and was not yet redeemed
        for (uint256 i = 0; i < numBonds; ++i) {
            // Check if the bond belongs to the account
            // If not and the address is zero, the bond was redeemed or never existed
            if (_ownerOf[i] == account) {
                // Check if requested bond is not matured but owned by the account address
                if (!matured ||
                    // Or if the requested bond is matured, i.e., the bond maturity timestamp passed
                    block.timestamp >= mapUserBonds[i].maturity)
                {
                    positions[i] = true;
                    ++numAccountBonds;
                    // The payout is always bigger than zero if the bond exists
                    payout += mapUserBonds[i].payout;
                }
            }
        }

        // Form pending bonds index array
        bondIds = new uint256[](numAccountBonds);
        uint256 numPos;
        for (uint256 i = 0; i < numBonds; ++i) {
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
        // If payout is zero, the bond has been redeemed or never existed
        if (payout > 0) {
            matured = block.timestamp >= mapUserBonds[bondId].maturity;
        }
    }

    /// @dev Gets current reserves of OLAS / totalSupply of Uniswap L2-like LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP) {
        return IBondCalculator(bondCalculator).getCurrentPriceLP(token);
    }

    /// @dev Gets the valid bond Id from the provided index.
    /// @param id Bond counter.
    /// @return Bond Id.
    function tokenByIndex(uint256 id) external view returns (uint256) {
        if (id >= totalSupply) {
            revert Overflow(id, totalSupply - 1);
        }

        return id;
    }

    /// @dev Returns bond token URI.
    /// @param bondId Bond Id.
    /// @return Bond token URI string.
    function tokenURI(uint256 bondId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, bondId));
    }
}
