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
        // Service is active
        bool active;
        // Update locker
        bool updateLocked;
    }

    // Agent Registry
    address public immutable agentRegistry;
    // Service counter
    Counters.Counter private _serviceIds;
    // Default timeout window for getting the agent instances registered for the service
    uint256 private constant AGENT_INSTANCE_REGISTRATION_TIMEOUT = 1000;
    // Service Manager
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of owner address => (map of service Ids from that owner => if the service is initialized)
    mapping (address => mapping(uint256 => bool)) private _mapOwnerServices;
    // Map of agent instance addres => if engaged with a service
    mapping (address => bool) private _mapAllAgentInstances;
    // Map for checking on unique canonical agent Ids
    mapping(uint256 => bool) private _mapAgentIds;

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
        require(_mapOwnerServices[owner][serviceId] != false, "serviceOwner: SERVICE_NOT_FOUND");
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
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated or 0 is created for the first time.
    function _setServiceInfo(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        private
    {
        // Checks for non-empty strings
        require(bytes(name).length > 0, "serviceInfo: EMPTY_NAME");
        require(bytes(description).length > 0, "serviceInfo: NO_DESCRIPTION");

        // Checking for non-empty and correct number of arrays
        require(agentIds.length > 0 && agentIds.length == agentNumSlots.length,
            "serviceInfo: AGENTS_SLOTS");
        require(operatorSlots.length == 2 && operatorSlots[0] > 0 && operatorSlots[0] < operatorSlots[1],
            "serviceInfo: OPERATOR_SLOTS");

        // Check for canonical agent ids uniqueness and the data validity
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        for (uint256 i = 0; i < agentIds.length; i++) {
            require(!_mapAgentIds[agentIds[i]], "serviceInfo: DUPLICATE_AGENT");
            require(agentNumSlots[i] > 0, "serviceInfo: SLOTS_NUMBER");
            require(agReg.exists(agentIds[i]), "serviceInfo: AGENT_NOT_FOUND");
            _mapAgentIds[agentIds[i]] = true;
        }

        // Create a new service
        if (serviceId == 0) {
            _serviceIds.increment();
            serviceId = _serviceIds.current();
        }

        // TODO Shall there be a check for if the min operator slot is greater than one of the agent slot number?
        Service storage service = _mapServices[serviceId];
        service.maxNumAgentInstances = 0;
        service.agentIds = agentIds;
        for (uint256 i = 0; i < agentIds.length; i++) {
            service.mapAgentSlots[agentIds[i]] = agentNumSlots[i];
            service.maxNumAgentInstances += agentNumSlots[i];
            // Undo checking for duplicate canonical agent Ids
            _mapAgentIds[agentIds[i]] = false;
        }

        // Check for the correct threshold: 2/3 number of agent instances + 1
        require(threshold > service.maxNumAgentInstances * 2 / 3 && threshold <= service.maxNumAgentInstances,
            "serviceInfo: THRESHOLD");

        service.owner = owner;
        service.name = name;
        service.description = description;
        service.numAgentInstances = 0;
        service.deadline = block.timestamp + AGENT_INSTANCE_REGISTRATION_TIMEOUT;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];

        // The service is initiated (but not yet active)
        _mapOwnerServices[owner][serviceId] = true;
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    function createService(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold)
        external
        onlyManager
    {
        // Check for the non-empty address
        require(owner != address(0), "createService: EMPTY_OWNER");

        _setServiceInfo(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold, 0);

        emit CreateServiceTransaction(owner, name, threshold, _serviceIds.current());
    }

    /// @dev Updates a service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function updateService(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        // Once a service is active it should not be possible to update it.
        // TODO Need testing on that once that logic of activating services is in place
        require(!_mapServices[serviceId].active, "updateService: SERVICE_ACTIVE");

        // Check if the update is possible
        require(!_mapServices[serviceId].updateLocked, "updateService: UPDATE_LOCKED");

        _setServiceInfo(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold, serviceId);

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
        // TODO registration of agents should only be available for active services.
        Service storage service = _mapServices[serviceId];

        // Check if the agent instance is already engaged with another service
        require(!_mapAllAgentInstances[agent], "registerAgent: REGISTERED");

        // Check if the time window for registering agent instances is still active
        require(service.deadline > block.timestamp, "registerAgent: TIMEOUT");

        // Check if canonical agent Id exists in the service
        require(service.mapAgentSlots[agentId] > 0, "registerAgent: NO_AGENT");

        // Check if there is an empty slot for the agent instance in this specific service
        require(service.mapAgentInstances[agentId].length < service.mapAgentSlots[agentId],
            "registerAgent: SLOTS_FILLED");

        // Add agent instance and operator and set the instance engagement
        service.mapAgentInstances[agentId].push(Instance(agent, operator));
        service.numAgentInstances++;
        _mapAllAgentInstances[agent] = true;

        // TODO might be not needed if the service needs to be active before the possibility to register agent instances
        // then, the possibility to update will be locked there
        // Lock the possibility to update the service
        service.updateLocked = true;

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

    /// @dev Activates the service and its sensitive components.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function activate(address owner, uint256 serviceId)
    external
    onlyManager
    onlyServiceOwner(owner, serviceId)
    {
        Service storage service = _mapServices[serviceId];
        // Lock the possibility to update the service
        service.updateLocked = true;
    }

    /// @dev Deactivates the service and its sensitive components.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function deactivate(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        // Until deactivated, the service can't be updated
        // TODO Until it is decided whether the service deactivation cancels all the agent instances or not,
        // it is safer to clear them out. Otherwise there is a possibility to register the agent instance
        // that is not needed for the updated service in the registerAgent() function
        // TODO Also, how will the operator be notified if its agent instance is not used anymore?
        Service storage service = _mapServices[serviceId];
        // Clear agent instances that are not longer used
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            // Deactivate all agent instances for a specific canonical agent
            for (uint256 j = 0; j < service.mapAgentInstances[service.agentIds[i]].length; j++) {
                _mapAllAgentInstances[service.mapAgentInstances[service.agentIds[i]][j].agent] = false;
                // Here the hook for operator notification about instance inactivity can be inserted
                // operator = service.mapAgentInstances[service.agentIds[i]][j].operator
            }
            // Remove instances from their associated canonical agent Ids
            delete service.mapAgentInstances[service.agentIds[i]];
            // Set to zero the number of agent instance slots for each canonical agent Id
            service.mapAgentSlots[service.agentIds[i]] = 0;
        }

        // Unlock the possibility to update the service
        service.updateLocked = false;
    }

    function exists(uint256 serviceId) public view returns(bool) {
        return _mapServices[serviceId].owner != address(0);
    }
}
