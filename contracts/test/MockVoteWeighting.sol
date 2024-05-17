// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDispenser {
    function addNominee(bytes32 nomineeHash) external;
    function removeNominee(bytes32 nomineeHash) external;
}

// Nominee struct
struct Nominee {
    bytes32 account;
    uint256 chainId;
}

/// @dev Mocking contract of vote weighting.
contract MockVoteWeighting {
    address public immutable dispenser;
    uint256 public totalWeight;

    // Set of Nominee structs
    Nominee[] public setNominees;
    // Mapping of hash(Nominee struct) => nominee Id
    mapping(bytes32 => uint256) public mapNomineeIds;
    // Mapping of hash(Nominee struct) => nominee weight
    mapping(bytes32 => uint256) public mapNomineeRelativeWeights;

    constructor(address _dispenser) {
        dispenser = _dispenser;
        setNominees.push(Nominee(0, 0));
    }

    /// @dev Checkpoint to fill data for both a specific nominee and common for all nominees.
    /// @param account Address of the nominee.
    /// @param chainId Chain Id.
    function checkpointNominee(bytes32 account, uint256 chainId) external view {
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        if (mapNomineeIds[nomineeHash] == 0) {
            revert();
        }
    }

    /// @dev Set staking weight.
    function setNomineeRelativeWeight(address account, uint256 chainId, uint256 weight) external {
        Nominee memory nominee = Nominee(bytes32(uint256(uint160(account))), chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        // 1.0 == 1e18, meaning 0.1%, or 1e-4 is equal to 1e14 in 1e18 form
        mapNomineeRelativeWeights[nomineeHash] = weight * 10**14;

        totalWeight += weight;
    }

    /// @dev Get Nominee relative weight (not more than 1.0) normalized to 1e18 and the sum of weights.
    ///         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    ///         inflation_rate * relativeWeight / 1e18.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    /// @return Value of relative weight normalized to 1e18.
    /// @return Sum of nominee weights.
    function nomineeRelativeWeight(bytes32 account, uint256 chainId, uint256) external view returns (uint256, uint256) {
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        return (mapNomineeRelativeWeights[nomineeHash], totalWeight);
    }

    /// @dev Records nominee starting epoch number.
    function addNominee(address account, uint256 chainId) external {
        Nominee memory nominee = Nominee(bytes32(uint256(uint160(account))), chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        uint256 id = setNominees.length;
        mapNomineeIds[nomineeHash] = id;
        // Push the nominee into the list
        setNominees.push(nominee);

        IDispenser(dispenser).addNominee(nomineeHash);
    }

    /// @dev Records nominee removal epoch number.
    function removeNominee(address account, uint256 chainId) external {
        Nominee memory nominee = Nominee(bytes32(uint256(uint160(account))), chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        IDispenser(dispenser).removeNominee(nomineeHash);
    }
}
