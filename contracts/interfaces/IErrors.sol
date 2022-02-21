// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @dev Errors.
 */
interface IErrors {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Wrong hash format.
    /// @param hashFunctionProvided Hash function classification provided.
    /// @param hashFunctionNeeded Hash function classification needed.
    /// @param sizeProvided Size of a hash digest provided.
    /// @param sizeNeeded Size of a hash digest needed.
    error WrongHash(uint8 hashFunctionProvided, uint8 hashFunctionNeeded, uint8 sizeProvided, uint8 sizeNeeded);

    /// @dev Hash already exists in the records.
    error HashExists();

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev The provided string is empty.
    error EmptyString();

    /// @dev Component Id is not correctly provided for the current routine.
    /// @param componentId Component Id.
    error WrongComponentId(uint256 componentId);

    /// @dev Agent Id is not correctly provided for the current routine.
    /// @param agentId Component Id.
    error WrongAgentId(uint256 agentId);

    /// @dev Inconsistent data of cannonical agent Ids and their correspondent slots.
    /// @param numAgentIds Number of canonical agent Ids.
    /// @param numAgentSlots Numberf of canonical agent Id slots.
    error WrongAgentIdsData(uint256 numAgentIds, uint256 numAgentSlots);

    /// @dev Canonical agent Id is not found.
    /// @param agentId Canonical agent Id.
    error AgentNotFound(uint256 agentId);

    /// @dev Component Id is not found.
    /// @param componentId Component Id.
    error ComponentNotFound(uint256 componentId);

    /// @dev Service Id is not found, although service Id might exist in the records.
    /// @dev serviceId Service Id.
    error ServiceNotFound(uint256 serviceId);

    /// @dev Service Id does not exist in registry records.
    /// @param serviceId Service Id.
    error ServiceDoesNotExist(uint256 serviceId);

    /// @dev Agent instance is already registered with a specified `serviceId`.
    /// @param serviceId Service Id.
    error AgentInstanceRegistered(uint256 serviceId);

    /// @dev Wrong operator is specified when interacting with a specified `serviceId`.
    /// @param serviceId Service Id.
    error WrongOperator(uint256 serviceId);

    /// @dev Canonical `agentId` is not found as a part of `serviceId`.
    /// @param agentId Canonical agent Id.
    /// @param serviceId Service Id.
    error AgentNotInService(uint256 agentId, uint256 serviceId);

    /// @dev Zero value when it has to be greater than zero.
    error ZeroValue();

    /// @dev Service is inactive.
    /// @param serviceId Service Id.
    error ServiceInactive(uint256 serviceId);

    /// @dev Service is active.
    /// @param serviceId Service Id.
    error ServiceActive(uint256 serviceId);

    /// @dev Agent instance registration timeout has been reached. Service is expired.
    /// @param deadline The registration deadline.
    /// @param curTime Current timestamp.
    /// @param serviceId Service Id.
    error RegistrationTimeout(uint256 deadline, uint256 curTime, uint256 serviceId);

    /// @dev Service termination block has been reached. Service is terminated.
    /// @param teminationBlock The termination block.
    /// @param curBlock Current block.
    /// @param serviceId Service Id.
    error ServiceTerminated(uint256 teminationBlock, uint256 curBlock, uint256 serviceId);

    /// @dev All the agent instance slots for a specific `serviceId` are filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsFilled(uint256 serviceId);

    /// @dev Agent instances for a specific `serviceId` are not filled.
    /// @param actual Current number of agent instances.
    /// @param maxNumAgentInstances Maximum number of agent instances to be filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsNotFilled(uint256 actual, uint256 maxNumAgentInstances, uint256 serviceId);
}
