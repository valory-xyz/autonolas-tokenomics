// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ServiceRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is Ownable {
    address public immutable serviceRegistry;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentSlots Agent instance slots by canonical agent Id. Passed as a (key, value) array sequence.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Threshold for a multisig composed by agents.
    function serviceCreate(address owner, string memory name, string memory description, uint256[] memory agentSlots,
        uint256[] memory operatorSlots, uint256 threshold)
        public
    {
        ServiceRegistry serReg = ServiceRegistry(serviceRegistry);
        serReg.createService(owner, name, description, agentSlots, operatorSlots, threshold);
    }
}
