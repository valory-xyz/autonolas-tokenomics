// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

error WrongLength(uint256 length1, uint256 length2);

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
    uint256 public roundCounter;
    mapping(uint256 => RoundInfo) public mapRoundInfo;
    mapping(uint256 => uint256) public mapUnitAmounts;
    
    receive() external payable {
    }

    function donate(bytes32 merkleRoot) external payable {
        uint256 rCounter = roundCounter;
        RoundInfo memory rInfo = RoundInfo(merkleRoot, msg.value);
        mapRoundInfo[rCounter] = rInfo;
        rCounter++;
        roundCounter = rCounter;
    }

    function claim(
        uint256 roundId,
        uint256[] memory unitIds,
        uint256[] memory amounts,
        MultiProof calldata multiProof
    ) external view returns (bool valid)
    {
        uint256 uLength = unitIds.length;

        if (unitIds.length != amounts.length) {
            revert WrongLength(uLength, amounts.length);
        }

        bytes32[] memory leaves = new bytes32[](uLength);
        for (uint256 i = 0; i < uLength; ++i) {
            // double hashed for better resistance to (second) pre-image attacks
            bytes32 leaf = keccak256(
                abi.encode(
                    keccak256(abi.encode(unitIds[i], amounts[i]))
                )
            );
            leaves[i] = leaf;
        }
        valid = MerkleProof.multiProofVerifyCalldata(multiProof.merkleProof, multiProof.proofFlags,
            mapRoundInfo[roundId].merkleRoot, leaves);
    }
}