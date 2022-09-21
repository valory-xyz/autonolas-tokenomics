// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

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

    // Owner address
    address public owner;
    // OLAS token address
    address public immutable olas;
    // Tkenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;
    // Depository contract address
    address public depository;
    // Dispenser contract address
    address public dispenser;
    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev Generic Tokenomics constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    constructor(address _olas, address _tokenomics, address _treasury, address _depository, address _dispenser)
    {
        olas = _olas;
        tokenomics = _tokenomics;
        treasury = _treasury;
        depository = _depository;
        dispenser = _dispenser;
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

        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
        if (_depository != address(0)) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        if (_dispenser != address(0)) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
    }
}    
