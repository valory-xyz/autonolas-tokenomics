// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

error WrongLength(uint256 length1, uint256 length2);

error AlreadyClaimed(uint256 roundId, uint256 unitId);

error ZeroValue();

error InsufficientBalance(uint256 requested, uint256 available);

error ClaimProofFailed(uint256 roundId);

struct MultiProof {
    bytes32[] merkleProof;
    bool[] proofFlags;
}

struct RoundInfo {
    bytes32 merkleRoot;
    uint256 amount;
}

/// @title MockTokenomicsMerkle - Smart contract for mocking the tokenomics based on Merkle proofs
contract MockTokenomicsMerkle {
    event Donation(address indexed sender, uint256 amount, uint256 indexed rountId, bytes32 merkleRoot, bytes32 hashIPFS);
    event Claim(address indexed sender, uint256 roundId, uint256[] unitIds, uint256[] amounts);

    uint256 public roundCounter;
    mapping(uint256 => RoundInfo) public mapRoundInfo;
    mapping(uint256 => uint256) public mapUnitAmounts;
    mapping(uint256 => mapping(uint256 => bool)) public mapClaimedRoundUnits;
    
    receive() external payable {
    }

    function donate(bytes32 merkleRoot, bytes32 hashIPFS) external payable returns (uint256 roundId) {
        roundId = roundCounter;
        mapRoundInfo[roundId] = RoundInfo(merkleRoot, msg.value);
        roundCounter = roundId + 1;

        emit Donation(msg.sender, msg.value, roundId, merkleRoot, hashIPFS);
    }

    function claim(
        uint256 roundId,
        uint256[] memory unitIds,
        uint256[] memory amounts,
        MultiProof calldata multiProof
    ) external returns (bool valid)
    {
        uint256 uLength = unitIds.length;

        if (unitIds.length == 0 || unitIds.length != amounts.length) {
            revert WrongLength(uLength, amounts.length);
        }

        bytes32[] memory leaves = new bytes32[](uLength);
        for (uint256 i = 0; i < uLength; ++i) {
            // Check for the claimed round
            if (mapClaimedRoundUnits[roundId][unitIds[i]]) {
                revert AlreadyClaimed(roundId, unitIds[i]);
            }

            // Check for the zero amount
            if (amounts[i] == 0) {
                revert ZeroValue();
            }

            // Double hashed for better resistance to (second) pre-image attacks
            bytes32 leaf = keccak256(
                abi.encode(
                    keccak256(abi.encode(unitIds[i], amounts[i]))
                )
            );
            leaves[i] = leaf;
        }

        valid = MerkleProof.multiProofVerifyCalldata(multiProof.merkleProof, multiProof.proofFlags,
            mapRoundInfo[roundId].merkleRoot, leaves);

        if (valid) {
            uint256 amount = mapRoundInfo[roundId].amount;
            for (uint256 i = 0; i < uLength; ++i) {
                // Check for the balance left
                if (amounts[i] > amount) {
                    revert InsufficientBalance(amounts[i], amount);
                }
                amount -= amounts[i];
                mapClaimedRoundUnits[roundId][unitIds[i]] = true;
            }
            mapRoundInfo[roundId].amount = amount;
        } else {
            revert ClaimProofFailed(roundId);
        }

        emit Claim(msg.sender, roundId, unitIds, amounts);
    }
}