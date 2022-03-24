// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IStructs.sol";

/**
 * @dev Required interface for the service manipulation.
 */
interface IService is IStructs {
    /// @dev Activates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address owner, uint256 serviceId) external payable returns (bool success);

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function createService(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold
    ) external returns (uint256 serviceId);

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    function update(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold,
        uint256 serviceId
    ) external;

    /// @dev Terminates the service.
    /// @param owner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the owner.
    function terminate(address owner, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Destroys the service instance.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function destroy(address owner, uint256 serviceId) external returns (bool success);

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Registers agent instances.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint256[] memory agentIds
    ) external payable returns (bool success);

    /// @dev Creates Gnosis Safe instance controlled by the service agent instances.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    /// @param paymentToken Token that should be used for the payment (0 is ETH)
    /// @param payment Value that should be paid
    /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    /// @return multisig Address of the created multisig.
    function createSafe(
        address owner,
        uint256 serviceId,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver,
        uint256 nonce
    ) external returns (address multisig);
}
