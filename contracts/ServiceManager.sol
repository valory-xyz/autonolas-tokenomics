// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IService.sol";
import "./interfaces/IMultihash.sol";

/// @title Service Manager - Periphery smart contract for managing services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is IMultihash, Ownable {
    event GnosisSafeCreate(address multisig);

    address public immutable serviceRegistry;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Threshold for a multisig composed by agents.
    function serviceCreate(address owner, string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, uint256[] memory agentNumSlots, uint256 threshold)
        public
        returns (uint256)
    {
        return IService(serviceRegistry).createService(owner, name, description, configHash, agentIds, agentNumSlots,
            threshold);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function serviceUpdate(string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, uint256[] memory agentNumSlots, uint256 threshold, uint256 serviceId)
        public
    {
        IService(serviceRegistry).update(msg.sender, name, description, configHash, agentIds, agentNumSlots,
            threshold, serviceId);
    }

    /// @dev Sets agent instance registration window time.
    /// @param serviceId Correspondent service Id.
    /// @param deadline Registration deadline.
    function serviceSetRegistrationDeadline(uint256 serviceId, uint256 deadline) public {
        IService(serviceRegistry).setRegistrationDeadline(msg.sender, serviceId, deadline);
    }

    /// @dev Sets service termination block.
    /// @param serviceId Correspondent service Id.
    /// @param blockNum Termination block. If 0 is passed then there is no termination.
    function serviceSetTerminationBlock(uint256 serviceId, uint256 blockNum) public {
        IService(serviceRegistry).setTerminationBlock(msg.sender, serviceId, blockNum);
    }

    /// @dev Registers the agent instance.
    /// @param serviceId Service Id to be updated.
    /// @param agent Address of the agent instance.
    /// @param agentId Canonical Id of the agent.
    function serviceRegisterAgent(uint256 serviceId, address agent, uint256 agentId) public {
        IService(serviceRegistry).registerAgent(msg.sender, serviceId, agent, agentId);
    }

    /// @dev Creates Safe instance controlled by the service agent instances.
    /// @param serviceId Correspondent service Id.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    /// @param paymentToken Token that should be used for the payment (0 is ETH)
    /// @param payment Value that should be paid
    /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    /// @return multisig Address of the created Gnosis Sage multisig.
    function serviceCreateSafe(uint256 serviceId, address to, bytes calldata data, address fallbackHandler,
        address paymentToken, uint256 payment, address payable paymentReceiver, uint256 nonce)
        public
        returns (address multisig)
    {
        multisig = IService(serviceRegistry).createSafe(msg.sender, serviceId, to, data, fallbackHandler,
            paymentToken, payment, paymentReceiver, nonce);
        emit GnosisSafeCreate(multisig);
    }

    /// @dev Activates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    function serviceActivateRegistration(uint256 serviceId) public {
        IService(serviceRegistry).activateRegistration(msg.sender, serviceId);
    }

    /// @dev Deactivates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    function serviceDeactivateRegistration(uint256 serviceId) public {
        IService(serviceRegistry).deactivateRegistration(msg.sender, serviceId);
    }

    /// @dev Destroys the service instance and frees up its storage.
    /// @param serviceId Correspondent service Id.
    function serviceDestroy(uint256 serviceId) public {
        IService(serviceRegistry).destroy(msg.sender, serviceId);
    }
}
