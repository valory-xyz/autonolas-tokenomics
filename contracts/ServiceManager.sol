// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IStructs.sol";
import "./interfaces/IService.sol";

/// @title Service Manager - Periphery smart contract for managing services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is IErrors, IStructs, Ownable {
    event GnosisSafeCreate(address multisig);

    address public immutable serviceRegistry;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Fallback function
    fallback() external payable {
        revert WrongFunction();
    }

    /// @dev Receive function
    receive() external payable {
        revert WrongFunction();
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    function serviceCreate(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold
    ) public returns (uint256)
    {
        return IService(serviceRegistry).createService(owner, name, description, configHash, agentIds, agentParams,
            threshold);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function serviceUpdate(
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold,
        uint256 serviceId
    ) public
    {
        IService(serviceRegistry).update(msg.sender, name, description, configHash, agentIds, agentParams,
            threshold, serviceId);
    }

    /// @dev Terminates the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the owner.
    function serviceTerminate(uint256 serviceId) public returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).terminate(msg.sender, serviceId);
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function serviceUnbond(uint256 serviceId) public returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).unbond(msg.sender, serviceId);
    }

    /// @dev Destroys the service instance and frees up its storage.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function serviceDestroy(uint256 serviceId) public returns (bool success) {
        success = IService(serviceRegistry).destroy(msg.sender, serviceId);
    }

    /// @dev Activates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function serviceActivateRegistration(uint256 serviceId) public payable returns (bool success) {
        success = IService(serviceRegistry).activateRegistration{value: msg.value}(msg.sender, serviceId);
    }

    /// @dev Registers agent instances.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function serviceRegisterAgents(
        uint256 serviceId,
        address[] memory agentInstances,
        uint256[] memory agentIds
    ) public payable returns (bool success) {
        success = IService(serviceRegistry).registerAgents{value: msg.value}(msg.sender, serviceId, agentInstances, agentIds);
    }

    /// @dev Creates Safe instance controlled by the service agent instances.
    /// @param serviceId Correspondent service Id.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    /// @param paymentToken Token that should be used for the payment (0 is ETH)
    /// @param payment Value that should be paid
    /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    /// @return multisig Address of the created multisig.
    function serviceCreateSafe(
        uint256 serviceId,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver,
        uint256 nonce
    ) public returns (address multisig)
    {
        multisig = IService(serviceRegistry).createSafe(msg.sender, serviceId, to, data, fallbackHandler,
            paymentToken, payment, paymentReceiver, nonce);
        emit GnosisSafeCreate(multisig);
    }
}
