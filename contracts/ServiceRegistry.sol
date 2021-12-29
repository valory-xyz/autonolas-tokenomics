// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is Ownable {
    using Counters for Counters.Counter;

    event CreateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event UpdateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event RegisterInstanceTransaction(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateSafeWithAgents(uint256 serviceId, address[] agentInstances, uint256 threshold);

    struct Range {
        uint256 min;
        uint256 max;
    }

    struct Instance {
        address agent;
        address operator;
    }

    // Service parameters
    struct Service {
        // owner of the service
        address owner;
        address proxyContract;
        string name;
        string description;
        // Deadline for all the agent instances registration for this service
        uint256 deadline;
        // Service termination block, if set > 0
        uint256 terminationBlock;
        // Agent instance signers threshold
        uint256 threshold;
        // Total number of agent instances
        uint256 maxNumAgentInstances;
        // Actual number of agent instances
        uint256 numAgentInstances;
        // Range of min-max number of operator slots
        Range operatorSlots;
        // Canonical agent Ids for the service
        uint256[] agentIds;
        // Canonical agent Id => Number of agent instances.
        mapping(uint256 => uint256) mapAgentSlots;
        // Actual agent instance addresses. Canonical agent Id => Set of agent instance addresses.
        mapping(uint256 => Instance[]) mapAgentInstances;
        // Config hash per agent
//        mapping(uint256 => string) mapAgentHash;
        bool active;
    }

    address public immutable agentRegistry;
    Counters.Counter private _serviceIds;
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of owner address => (map of service Ids from that owner => how many times service has been updated)
    mapping (address => mapping(uint256 => uint256)) private _mapOwnerServices;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
    }

    modifier onlyManager {
        // Only the manager has a privilege to update a service
        require(_manager == msg.sender, "manager: MANAGER_ONLY");
        _;
    }

    modifier onlyServiceOwner(address owner, uint256 serviceId) {
        // Only the owner of the service is authorized to update it
        require(_mapOwnerServices[owner][serviceId] != 0, "serviceOwner: SERVICE_NOT_FOUND");
        _;
    }

    modifier serviceExists(uint256 serviceId) {
        require(_mapServices[serviceId].owner != address(0), "serviceExists: NO_SERVICE");
        _;
    }

    /// @dev Changes the service manager.
    /// @param newManager Address of a new service manager.
    function changeManager(address newManager) public onlyOwner {
        _manager = newManager;
    }

    /// @dev Sets the service parameters.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentSlots Agent instance slots by canonical agent Id. Passed as a (key, value) array sequence.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated or 0 is created for the first time.
    function _setServiceInfo(address owner, string memory name, string memory description, uint256[] memory agentSlots,
        uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        private
    {
        // Checks for non-empty strings
        require(bytes(name).length > 0, "serviceInfo: EMPTY_NAME");
        require(bytes(description).length > 0, "serviceInfo: NO_DESCRIPTION");

        // Checking for non-empty and correct number of arrays
        require(agentSlots.length > 1 && agentSlots.length % 2 == 0, "serviceInfo: AGENTS_SLOTS");
        require(operatorSlots.length == 2 && operatorSlots[0] > 0 && operatorSlots[0] < operatorSlots[1],
            "serviceInfo: OPERATOR_SLOTS");

        // Delete existent service if updating one
        bool update = false;
        if (serviceId == 0) {
            _serviceIds.increment();
            serviceId = _serviceIds.current();
        } else {
            delete _mapServices[serviceId];
            update = true;
        }

        // TODO Shall there be a check for if the min operator slot is greater than one of the agent slot number?
        // Get agent slots and check for the data validity
        Service storage service = _mapServices[serviceId];
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        for (uint256 i = 0; i < agentSlots.length; i += 2) {
            require(service.mapAgentSlots[agentSlots[i]] == 0, "serviceInfo: DUPLICATE_AGENT");
            require(agentSlots[i + 1] > 0, "serviceInfo: SLOTS_NUMBER");
            require(agReg.exists(agentSlots[i]), "serviceInfo: AGENT_NOT_FOUND");
            service.mapAgentSlots[agentSlots[i]] = agentSlots[i + 1];
            service.agentIds.push(agentSlots[i]);
            service.maxNumAgentInstances += agentSlots[i + 1];
        }

        // Check for the correct threshold: 2/3 number of agent instances + 1
        require(threshold > service.maxNumAgentInstances * 2 / 3 && threshold <= service.maxNumAgentInstances,
            "serviceInfo: THRESHOLD");

        service.owner = owner;
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];

        // If the service is updated, record its update number, else initiate with 1
        if (update) {
            _mapOwnerServices[owner][serviceId]++;
        } else {
            _mapOwnerServices[owner][serviceId] = 1;
        }
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentSlots Agent instance slots by canonical agent Id. Passed as a (key, value) array sequence.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    function createService(address owner, string memory name, string memory description, uint256[] memory agentSlots,
        uint256[] memory operatorSlots, uint256 threshold)
        external
        onlyManager
    {
        // Check for the non-empty address
        require(owner != address(0), "createService: EMPTY_OWNER");

        _setServiceInfo(owner, name, description, agentSlots, operatorSlots, threshold, 0);

        emit CreateServiceTransaction(owner, name, threshold, _serviceIds.current());
    }

    /// @dev Updates a service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentSlots Agent instance slots by canonical agent Id. Passed as a (key, value) array sequence.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function updateService(address owner, string memory name, string memory description, uint256[] memory agentSlots,
        uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        // TODO Need to make sure the updated service is not active!
        // Also, registration of agents should only be able for active services.
        // Once a service is active it should not be possible to update it.

        _setServiceInfo(owner, name, description, agentSlots, operatorSlots, threshold, serviceId);

        emit UpdateServiceTransaction(owner, name, threshold, serviceId);
    }

    /// @dev Sets service registration window time.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Service Id to be updated.
    /// @param time Registration time limit
    function setRegistrationWindow(address owner, uint256 serviceId, uint256 time)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        _mapServices[serviceId].deadline = block.timestamp + time;
    }

    /// @dev Sets service termination block.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Service Id to be updated.
    /// @param blockNum Termination block. If 0 is passed then there is no termination.
    function setTerminationBlock(address owner, uint256 serviceId, uint256 blockNum)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        _mapServices[serviceId].terminationBlock = blockNum;
    }

    /// @dev Registers agent instance.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to be updated.
    /// @param agent Address of the agent instance.
    /// @param agentId Canonical Id of the agent.
    function registerAgent(address operator, uint256 serviceId, address agent, uint256 agentId)
        external
        onlyManager
        serviceExists(serviceId)
    {
        Service storage service = _mapServices[serviceId];

        // Check if there is an empty slot for the agent instance in this specific service
        require(service.mapAgentInstances[agentId].length < service.mapAgentSlots[agentId],
            "registerAgent: SLOTS_FILLED");

        // Add agent instance and operator
        service.mapAgentInstances[agentId].push(Instance(agent, operator));
        service.numAgentInstances++;

        emit RegisterInstanceTransaction(operator, serviceId, agent, agentId);
    }

    /// @dev Creates Safe instance controlled by the service agent instances.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function createSafe(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        Service storage service = _mapServices[serviceId];
        require(service.numAgentInstances == service.maxNumAgentInstances, "createSafe: NUM_INSTANCES");

        // Get all agent instances for the safe
        address[] memory agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 agentId = service.agentIds[i];
            for (uint256 j = 0; j < service.mapAgentInstances[agentId].length; j++) {
                agentInstances[count] = service.mapAgentInstances[agentId][j].agent;
                count++;
            }
        }

        emit CreateSafeWithAgents(serviceId, agentInstances, service.threshold);

        // Gnosis Safe call
    }

    function exists(uint256 serviceId) public view returns(bool) {
        return _mapServices[serviceId].owner != address(0);
    }
}
