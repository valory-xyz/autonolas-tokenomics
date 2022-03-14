// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IMultihash.sol";

/**
 * @dev Required interface for the service manipulation.
 */
interface IService is IMultihash {
    /// @dev Activates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param deadline Agent instance registration deadline.
    function activateRegistration(address owner, uint256 serviceId, uint256 deadline) external;

    /// @dev Deactivates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function deactivateRegistration(address owner, uint256 serviceId) external;

    /// @dev Destroys the service instance.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function destroy(address owner, uint256 serviceId) external;

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function createService(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        uint256[] memory agentNumSlots,
        uint256 threshold
    ) external returns (uint256 serviceId);

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    function update(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        uint256[] memory agentNumSlots,
        uint256 threshold,
        uint256 serviceId
    ) external;

    /// @dev Sets agent instance registration deadline.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Service Id to be updated.
    /// @param deadline Registration deadline.
    function setRegistrationDeadline(address owner, uint256 serviceId, uint256 deadline) external;

    /// @dev Terminates the service.
    /// @param owner Owner of the service.
    /// @param serviceId Service Id to be updated.
    function terminate(address owner, uint256 serviceId) external;

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    function unbond(address operator, uint256 serviceId) external;

    /// @dev Registers agent instance.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to be updated.
    /// @param agent Address of the agent instance.
    /// @param agentId Canonical Id of the agent.
    function registerAgent(address operator, uint256 serviceId, address agent, uint256 agentId) external;

    /// @dev Creates Gnosis Safe instance controlled by the service agent instances.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    /// @param paymentToken Token that should be used for the payment (0 is ETH)
    /// @param payment Value that should be paid
    /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    /// @return Address of the created multisig.
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
    ) external returns (address);
}
