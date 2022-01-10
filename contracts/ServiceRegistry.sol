// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "./AgentRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is Ownable {
    using Counters for Counters.Counter;

    event CreateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event UpdateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event RegisterInstanceTransaction(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateSafeWithAgents(uint256 serviceId, address[] agentInstances, uint256 threshold);
    event ActivateService(address owner, uint256 serviceId);
    event DeactivateService(address owner, uint256 serviceId);

    struct Range {
        uint256 min;
        uint256 max;
    }

    struct Instance {
        address agent;
        address operator;
    }

    // Gnosis Safe parameters struct
    struct GnosisParams {
        address[] agentInstances;
        uint256 threshold;
        address to;
        bytes data;
        address fallbackHandler;
        address paymentToken;
        uint256 payment;
        address payable paymentReceiver;
        uint nonce;
    }

    // Service parameters
    struct Service {
        // owner of the service
        address owner;
        address proxyContract;
        // Multisig address for agent instances
        address multisig;
        string name;
        string description;
        // Deadline until which all agent instances must be registered for this service
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
        // Service activity state
        bool active;
    }

    // Selector of the Gnosis Safe setup function
    bytes4 private constant _GNOSIS_SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Default timeout window for getting the agent instances registered for the service
    uint256 private constant _AGENT_INSTANCE_REGISTRATION_TIMEOUT = 1000;
    // Agent Registry
    address public immutable agentRegistry;
    // Gnosis Safe
    address payable public immutable gnosisSafeL2;
    // Gnosis Safe Factory
    address public immutable gnosisSafeProxyFactory;
    // Service counter
    Counters.Counter private _serviceIds;
    // Service Manager
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of owner address => (map of service Ids from that owner => if the service is initialized)
    mapping (address => mapping(uint256 => bool)) private _mapOwnerServices;
    // Map of owner address => set of service Ids that belong to that owner
    mapping (address => uint256[]) private _mapOwnerSetServices;
    // Map of agent instance addres => if engaged with a service
    mapping (address => bool) private _mapAllAgentInstances;
    // Map for checking on unique canonical agent Ids
    mapping(uint256 => bool) private _mapAgentIds;

    constructor(address _agentRegistry, address payable _gnosisSafeL2, address _gnosisSafeProxyFactory) {
        agentRegistry = _agentRegistry;
        gnosisSafeL2 = _gnosisSafeL2;
        gnosisSafeProxyFactory = _gnosisSafeProxyFactory;
    }

    // Only the manager has a privilege to update a service
    modifier onlyManager {
        require(_manager == msg.sender, "manager: MANAGER_ONLY");
        _;
    }

    // Only the owner of the service is authorized to manipulate it
    modifier onlyServiceOwner(address owner, uint256 serviceId) {
        require(_mapOwnerServices[owner][serviceId] != false, "serviceOwner: SERVICE_NOT_FOUND");
        _;
    }

    // Check for the existance of the service
    modifier serviceExists(uint256 serviceId) {
        require(_mapServices[serviceId].owner != address(0), "serviceExists: NO_SERVICE");
        _;
    }

    // Check that there are no registered agent instances.
    modifier noRegisteredAgentInstance(uint256 serviceId)
    {
        require(_mapServices[serviceId].numAgentInstances == 0, "agentInstance: REGISTERED");
        _;
    }

    /// @dev Going through basic initial service checks.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    function initialChecks(string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots)
        private
    {
        // Checks for non-empty strings
        require(bytes(name).length > 0, "initCheck: EMPTY_NAME");
        require(bytes(description).length > 0, "initCheck: NO_DESCRIPTION");

        // Checking for non-empty arrays and correct number of values in them
        require(agentIds.length > 0 && agentIds.length == agentNumSlots.length, "initCheck: AGENTS_SLOTS");
        // Checking for correct operator slots array values
        require(operatorSlots.length == 2 && operatorSlots[0] > 0 && operatorSlots[0] < operatorSlots[1],
            "initCheck: OPERATOR_SLOTS");

        // Using state map to check for duplicate canonical agent Ids
        for (uint256 i = 0; i < agentIds.length; i++) {
            require(!_mapAgentIds[agentIds[i]], "initCheck: DUPLICATE_AGENT");
            _mapAgentIds[agentIds[i]] = true;
        }

        // Check for canonical agent Ids existence and setting checked values back to false
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        for (uint256 i = 0; i < agentIds.length; i++) {
            require(agReg.exists(agentIds[i]), "initCheck: AGENT_NOT_FOUND");
            _mapAgentIds[agentIds[i]] = false;
        }
    }

    /// @dev Changes the service manager.
    /// @param newManager Address of a new service manager.
    function changeManager(address newManager) public onlyOwner {
        _manager = newManager;
    }

    /// @dev Activates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function activate(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        // Service must be inactive
        require(!_mapServices[serviceId].active, "activate: SERVICE_ACTIVE");

        // Activate the service
        _mapServices[serviceId].active = true;
        emit ActivateService(owner, serviceId);
    }

    /// @dev Deactivates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function deactivate(address owner, uint256 serviceId)
        public
        onlyManager
        onlyServiceOwner(owner, serviceId)
        noRegisteredAgentInstance(serviceId)
    {
        // Service must be active
        require(_mapServices[serviceId].active, "deactivate: SERVICE_INACTIVE");

        _mapServices[serviceId].active = false;
        emit DeactivateService(owner, serviceId);
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param addAgentIdsSize Indexes of canonical agent Ids array: ones added in the beginning, those removed at end.
    /// @param addAgentIdsSize Number of canonical agent Ids to be added to the service.
    function _setServiceData(Service storage service, uint256[] memory agentIds, uint256[] memory agentNumSlots,
        uint256[] memory idxAgentIds, uint256 addAgentIdsSize)
        private
    {
        // TODO Shall there be a check for if the min operator slot is greater than one of the agent slot number?
        service.maxNumAgentInstances = 0;
        // Based on idxAgentIds array, add canonical agent Ids for the service and the slots map
        for (uint256 i = 0; i < addAgentIdsSize; i++) {
            service.agentIds.push(agentIds[idxAgentIds[i]]);
            service.mapAgentSlots[agentIds[idxAgentIds[i]]] = agentNumSlots[idxAgentIds[i]];
            service.maxNumAgentInstances += agentNumSlots[idxAgentIds[i]];
        }
        // Remove any canonical agent Ids from the slots map, if any
        for (uint256 i = addAgentIdsSize; i < agentIds.length; i++) {
            service.mapAgentSlots[agentIds[idxAgentIds[i]]] = 0;
        }

        // Check for the correct threshold: 2/3 number of agent instances + 1
        require(service.threshold > service.maxNumAgentInstances * 2 / 3 &&
            service.threshold <= service.maxNumAgentInstances,
            "serviceInfo: THRESHOLD");
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @return serviceId Created service Id.
    function createService(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold)
        external
        onlyManager
        returns (uint256 serviceId)
    {
        // Check for the non-empty address
        require(owner != address(0), "createService: EMPTY_OWNER");

        // Execute initial checks
        initialChecks(name, description, agentIds, agentNumSlots, operatorSlots);

        // Array of indexes when creating a new service is just the exact sequence of increasing indexes
        // Also, check that there are no zero number of slots for a specific
        uint256 addAgentIdsSize = agentIds.length;
        uint256[] memory idxAgentIds = new uint256[](addAgentIdsSize);
        for (uint256 i = 0; i < addAgentIdsSize; i++) {
            require(agentNumSlots[i] > 0, "createService: EMPTY_SLOTS");
            idxAgentIds[i] = i;
        }

        // Create a new service Id
        _serviceIds.increment();
        serviceId = _serviceIds.current();

        // Set high-level data components of the service instance
        Service storage service = _mapServices[serviceId];
        service.owner = owner;
        service.name = name;
        service.description = description;
        service.deadline = block.timestamp + _AGENT_INSTANCE_REGISTRATION_TIMEOUT;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];

        // Calculate the rest of service components
        _setServiceData(service, agentIds, agentNumSlots, idxAgentIds, addAgentIdsSize);

        // The service is initiated (but not yet active)
        _mapOwnerServices[service.owner][serviceId] = true;
        _mapOwnerSetServices[owner].push(serviceId);

        emit CreateServiceTransaction(owner, name, threshold, _serviceIds.current());
    }

    /// @dev Updates a service in a CRUD way.
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
        noRegisteredAgentInstance(serviceId)
    {
        // Execute initial checks
        initialChecks(name, description, agentIds, agentNumSlots, operatorSlots);

        // Separating into canonical agent Ids that have non-zero number of slots and those that have to be deleted
        // Creating one array of indexes - beginning with agents Ids to be added, ending with those to be deleted
        uint256 addAgentIdsSize;
        uint256 delAgentIdsSize = agentIds.length - 1;
        uint256[] memory idxAgentIds = new uint256[](agentIds.length);
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentNumSlots[i] == 0) {
                idxAgentIds[delAgentIdsSize] = i;
                delAgentIdsSize--;
            } else {
                idxAgentIds[addAgentIdsSize] = i;
                addAgentIdsSize++;
            }
        }

        // Obtaining existent service instance and updating its high-level data components
        // Note that deadline is not updated here since there is a different function for that
        Service storage service = _mapServices[serviceId];
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];

        // Calculate the rest of service components
        _setServiceData(service, agentIds, agentNumSlots, idxAgentIds, addAgentIdsSize);

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
        // Operator address must be different from agent instance one
        // Also, operator address must not be used as an agent instance anywhere else
        require(operator != agent && !_mapAllAgentInstances[operator], "registerAgent: WRONG_OPERATOR");

        Service storage service = _mapServices[serviceId];

        // The service has to be active to register agents
        require(service.active, "registerAgent: INACTIVE");

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

        emit RegisterInstanceTransaction(operator, serviceId, agent, agentId);
    }

    /// @dev Creates Gnosis Safe proxy.
    /// @param gParams Structure with parameters to setup Gnosis Safe.
    /// @return Address of the created proxy.
    function _createGnosisSafeProxy(GnosisParams memory gParams) private returns(address) {
        bytes memory safeParams = abi.encodeWithSelector(_GNOSIS_SAFE_SETUP_SELECTOR, gParams.agentInstances,
            gParams.threshold, gParams.to, gParams.data, gParams.fallbackHandler, gParams.paymentToken, gParams.payment,
            gParams.paymentReceiver);

        GnosisSafeProxyFactory gFactory = GnosisSafeProxyFactory(gnosisSafeProxyFactory);
        GnosisSafeProxy gProxy = gFactory.createProxyWithNonce(gnosisSafeL2, safeParams, gParams.nonce);
        return address(gProxy);
    }

    /// @dev Gets all agent instances
    /// @param agentInstances Pre-allocated list of agent instance addresses.
    /// @param service Service instance.
    function _getAgentInstances(Service storage service) private view returns(address[] memory agentInstances) {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 agentId = service.agentIds[i];
            for (uint256 j = 0; j < service.mapAgentInstances[agentId].length; j++) {
                agentInstances[count] = service.mapAgentInstances[agentId][j].agent;
                count++;
            }
        }
    }

    /// @dev Creates Gnosis Safe instance controlled by the service agent instances.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    /// @param paymentToken Token that should be used for the payment (0 is ETH)
    /// @param payment Value that should be paid
    /// @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    /// @return Address of the created Gnosis Sage multisig.
    function createSafe(address owner, uint256 serviceId, address to, bytes calldata data, address fallbackHandler,
        address paymentToken, uint256 payment, address payable paymentReceiver, uint256 nonce)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        returns (address)
    {
        Service storage service = _mapServices[serviceId];
        require(service.numAgentInstances == service.maxNumAgentInstances, "createSafe: NUM_INSTANCES");

        // Get all agent instances for the safe
        address[] memory agentInstances = _getAgentInstances(service);

        emit CreateSafeWithAgents(serviceId, agentInstances, service.threshold);

        // Getting the Gnosis Safe multisig proxy for agent instances
        GnosisParams memory gParams;
        gParams.agentInstances = agentInstances;
        gParams.threshold = service.threshold;
        gParams.to = to;
        gParams.data = data;
        gParams.fallbackHandler = fallbackHandler;
        gParams.paymentToken = paymentToken;
        gParams.payment = payment;
        gParams.paymentReceiver = paymentReceiver;
        gParams.nonce = nonce;
        service.multisig = _createGnosisSafeProxy(gParams);

        return service.multisig;
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) public view returns(bool) {
        return _mapServices[serviceId].owner != address(0);
    }

    /// @dev Gets the number of services.
    /// @param owner The owner of services.
    /// @return Number of owned services.
    function balanceOf(address owner) public view returns (uint256) {
        return _mapOwnerSetServices[owner].length;
    }

    /// @dev Gets the owner of the service.
    /// @param serviceId Service Id.
    /// @return Address of the service owner.
    function ownerOf(uint256 serviceId) public view serviceExists(serviceId) returns (address) {
        return _mapServices[serviceId].owner;
    }

    /// @dev Gets the set of service Ids for a specified owner.
    /// @param owner Address of the owner.
    /// @return A set of service Ids.
    function getServiceIdsOfOwner(address owner)
        public
        view
        returns (uint256[] memory)
    {
        require(_mapOwnerSetServices[owner].length > 0, "serviceIdsOfOwner: NO_SERVICES");
        return _mapOwnerSetServices[owner];
    }

    /// @dev Gets the high-level service information.
    /// @param serviceId Service Id.
    /// @return owner Address of the service owner.
    /// @return name Name of the service.
    /// @return description Description of the service.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentIds Set of service canonical agents.
    /// @return agentNumSlots Set of numbers of agent instances for each canonical agent Id.
    /// @return numAgentInstances Number of registered agent instances.
    /// @return agentInstances Set of agent instances currently registered for the contract.
    /// @return active True if the service is active.
    function getServiceInfo(uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (address owner, string memory name, string memory description, uint256 numAgentIds,
            uint256[] memory agentIds, uint256[] memory agentNumSlots, uint256 numAgentInstances,
            address[]memory agentInstances, bool active)
    {
        Service storage service = _mapServices[serviceId];
        agentNumSlots = new uint256[](service.agentIds.length);
        numAgentInstances = service.numAgentInstances;
        agentInstances = _getAgentInstances(service);
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            agentNumSlots[i] = service.mapAgentSlots[service.agentIds[i]];
        }
        owner = service.owner;
        name = service.name;
        description = service.description;
        numAgentIds = service.agentIds.length;
        agentIds = service.agentIds;
        active = service.active;
    }
}
