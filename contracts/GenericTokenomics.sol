// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IErrorsTokenomics.sol";

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
    // Tokenomics role
    TokenomicsRole public tokenomicsRole;
    // Reentrancy lock
    uint8 internal _locked;
    // Initializer flag
    bool public initialized;
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
        if (initialized) {
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
        initialized = true;
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
