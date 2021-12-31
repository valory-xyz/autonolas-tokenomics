// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ServiceRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is Ownable {
    address public immutable serviceRegistry;
    ServiceRegistry private serReg;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
        serReg = ServiceRegistry(_serviceRegistry);
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Threshold for a multisig composed by agents.
    function serviceCreate(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold)
        public
    {
        serReg.createService(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold);
    }

    /// @dev Updates a service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function serviceUpdate(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        public
    {
        serReg.updateService(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold, serviceId);
    }

    /// @dev Sets service registration window time.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param time Registration time limit.
    function serviceSetRegistrationWindow(address owner, uint256 serviceId, uint256 time) public {
        serReg.setRegistrationWindow(owner, serviceId, time);
    }

    /// @dev Sets service termination block.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param blockNum Termination block. If 0 is passed then there is no termination.
    function serviceSetTerminationBlock(address owner, uint256 serviceId, uint256 blockNum) public {
        serReg.setTerminationBlock(owner, serviceId, blockNum);
    }

    /// @dev Registers the agent instance.
    /// @param serviceId Service Id to be updated.
    /// @param agent Address of the agent instance.
    /// @param agentId Canonical Id of the agent.
    function serviceRegisterAgent(uint256 serviceId, address agent, uint256 agentId) public {
        serReg.registerAgent(msg.sender, serviceId, agent, agentId);
    }

    /// @dev Creates Safe instance controlled by the service agent instances.
    /// @param serviceId Correspondent service Id.
    function serviceCreateSafe(uint256 serviceId) external {
        serReg.createSafe(msg.sender, serviceId);
    }
}
