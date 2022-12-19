// The following code is from flattening this file: GenericTokenomics.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// The following code is from flattening this import statement in: GenericTokenomics.sol
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



