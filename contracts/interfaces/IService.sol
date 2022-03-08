// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IMultihash.sol";

/**
 * @dev Required interface for the service manipulation.
 */
interface IService is IMultihash {
    /**
     * @dev Activates the ``serviceId`` of the ``owner``.
     */
    function activateRegistration(address owner, uint256 serviceId) external;

    /**
     * @dev Deactivates the ``serviceId`` of the ``owner``.
     */
    function deactivateRegistration(address owner, uint256 serviceId) external;

    /**
     * @dev Destroys the ``serviceId`` instance of the ``owner``.
     */
    function destroy(address owner, uint256 serviceId) external;

    /**
     * @dev Creates the service with specified parameters.
     */
    function createService(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        uint256[] memory agentNumSlots,
        uint256 threshold
    ) external returns (uint256 serviceId);

    /**
     * @dev Updates the ``serviceId`` service with specified parameters.
     */
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

    /**
     * @dev Sets service registration window time.
     */
    function setRegistrationDeadline(address owner, uint256 serviceId, uint256 deadline) external;

    /**
     * @dev Sets service termination block.
     */
    function setTerminationBlock(address owner, uint256 serviceId, uint256 blockNum) external;

    /**
     * @dev Registers ``agent`` instance by the ``operator`` for the canonical ``agentId`` of the ``serviceId`` service.
     */
    function registerAgent(address operator, uint256 serviceId, address agent, uint256 agentId) external;

    /**
     * @dev Creates safe for the ``serviceId`` service based on registered agent instances and provided parameters.
     */
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
