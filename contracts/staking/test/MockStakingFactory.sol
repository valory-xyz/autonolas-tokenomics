// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVerifier {
    function verifyImplementation(address implementation) external view returns (bool);
    function verifyInstance(address instance) external view returns (bool);
}

/// @dev Mocking the service staking proxy factory.
contract MockStakingFactory {
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

    function verifyInstance(address instance) external view returns (bool) {
        address implementation = mapInstanceImplementations[instance];
        if (implementation == address(0)) {
            return false;
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address (0)) {
            return IVerifier(localVerifier).verifyInstance(instance);
        }

        return true;
    }
}
