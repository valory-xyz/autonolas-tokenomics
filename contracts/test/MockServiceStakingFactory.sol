// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVerifier {
    function verifyImplementation(address implementation) external view returns (bool);
    function verifyInstance(address instance) external view returns (bool);
}

error InstanceHasNoImplementation(address instance);

/// @dev Mocking the service staking proxy factory.
contract MockServiceStakingFactory {
    // Verifier contract
    address public verifier;
    // Mapping of staking service proxy instances => implementation address
    mapping(address => address) public mapInstanceImplementations;

    function setVerifier(address newVerifier) external {
        verifier = newVerifier;
    }

    function addImplementation(address instance, address implementation) external {
        mapInstanceImplementations[instance] = implementation;
    }

    function verifyInstance(address instance) external view returns (bool success) {
        address implementation = mapInstanceImplementations[instance];
        if (implementation == address(0)) {
            revert InstanceHasNoImplementation(instance);
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address (0)) {
            success = IVerifier(localVerifier).verifyInstance(instance);
        } else {
            success = true;
        }
    }
}
