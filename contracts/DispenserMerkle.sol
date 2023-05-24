// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/ITreasury.sol";

struct MultiProof {
    bytes32[] merkleProof;
    bool[] proofFlags;
}

interface ITokenomicsMerkle {
    /// @dev Gets component / agent owner incentives and clears the balances.
    /// @notice `account` must be the owner of components / agents Ids, otherwise the function will revert.
    /// @notice The claim happens only for provided Claims with corresponding `unitIds` belonging to the `account`.
    /// @notice Component and agent Ids must be provided in the ascending order and must not repeat.
    /// @param account Account address.
    /// @param roundIds Set of round Ids the account is claiming incentives for.
    /// @param serviceIds Set of service Ids corresponding to round Ids the account is claiming incentives for.
    /// @param claims 2D set of claim triplets: [unit types (component / agent), corresponding unit Ids and amounts].
    /// @param multiProofs Set of multi proofs corresponding to a specific round Id for Merkle tree verifications.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function calculateOwnerIncentivesWithProofs(
        address account,
        uint256[] memory roundIds,
        uint256[] memory serviceIds,
        uint256[][][] memory claims,
        MultiProof[] calldata multiProofs
    ) external returns (uint256 reward, uint256 topUp);
}

/// @title Dispenser - Smart contract for distributing incentives
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract DispenserMerkle is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event TreasuryUpdated(address indexed treasury);
    event IncentivesClaimed(address indexed owner, uint256 reward, uint256 topUp);

    // Owner address
    address public owner;
    // Reentrancy lock
    uint8 internal _locked;

    // Tokenomics contract address
    address public tokenomics;
    // Treasury contract address
    address public treasury;

    /// @dev Dispenser constructor.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    constructor(address _tokenomics, address _treasury)
    {
        owner = msg.sender;
        _locked = 1;

        // Check for at least one zero contract address
        if (_tokenomics == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }

        tokenomics = _tokenomics;
        treasury = _treasury;
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

    /// @dev Claims incentives for the owner of components / agents.
    /// @notice `msg.sender` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `msg.sender` were provided, they will be untouched and keep accumulating.
    /// @param claims 2D set of claim triplets: [unit types (component / agent), corresponding unit Ids and amounts].
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function claimOwnerIncentives(
        uint256[] memory roundIds,
        uint256[] memory serviceIds,
        uint256[][][] memory claims,
        MultiProof[] calldata multiProofs
    ) external returns (uint256 reward, uint256 topUp)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Calculate incentives
        (reward, topUp) = ITokenomicsMerkle(tokenomics).calculateOwnerIncentivesWithProofs(msg.sender, roundIds,
            serviceIds, claims, multiProofs);

        bool success;
        // Request treasury to transfer funds to msg.sender if reward > 0 or topUp > 0
        if ((reward + topUp) > 0) {
            success = ITreasury(treasury).withdrawToAccount(msg.sender, reward, topUp);
        }

        // Check if the claim is successful and has at least one non-zero incentive.
        if (!success) {
            revert ClaimIncentivesFailed(msg.sender, reward, topUp);
        }

        emit IncentivesClaimed(msg.sender, reward, topUp);

        _locked = 1;
    }
}
