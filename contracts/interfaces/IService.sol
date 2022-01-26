// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IService {
    function activate(address owner, uint256 serviceId) external;

    function deactivate(address owner, uint256 serviceId) external;

    function destroy(address owner, uint256 serviceId) external;

    function createService(
        address owner,
        string memory name,
        string memory description,
        string memory configHash,
        uint256[] memory agentIds,
        uint256[] memory agentNumSlots,
        uint256 threshold
    ) external returns (uint256 serviceId);

    function updateService(
        address owner,
        string memory name,
        string memory description,
        string memory configHash,
        uint256[] memory agentIds,
        uint256[] memory agentNumSlots,
        uint256 threshold,
        uint256 serviceId
    ) external;

    function setRegistrationWindow(address owner, uint256 serviceId, uint256 time) external;

    function setTerminationBlock(address owner, uint256 serviceId, uint256 blockNum) external;

    function registerAgent(address operator, uint256 serviceId, address agent, uint256 agentId) external;

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
