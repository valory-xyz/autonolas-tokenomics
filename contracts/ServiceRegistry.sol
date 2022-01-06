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
        // Service activity state
        bool active;
    }

    // Selector of the Gnosis Safe setup function
    bytes4 private constant _GNOSIS_SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Agent Registry
    address public immutable agentRegistry;
    // Gnosis Safe
    address payable public immutable gnosisSafeL2;
    // Gnosis Safe Factory
    address public immutable gnosisSafeProxyFactory;
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

    // Only the owner of the service is authorized to update it
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
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param operatorSlots Range of min-max operator slots.
    /// @param threshold Signers threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated or 0 is created for the first time.
    /// @return Service Id of the newly created or modified service.
    function _setServiceData(address owner, string memory name, string memory description, uint256[] memory agentIds,
        uint256[] memory agentNumSlots, uint256[] memory operatorSlots, uint256 threshold, uint256 serviceId)
        private
        returns (uint256)
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
        service.deadline = block.timestamp + AGENT_INSTANCE_REGISTRATION_TIMEOUT;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];

        // The service is initiated (but not yet active)
        _mapOwnerServices[owner][serviceId] = true;
        return serviceId;
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

        serviceId = _setServiceData(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold, 0);
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
        _setServiceData(owner, name, description, agentIds, agentNumSlots, operatorSlots, threshold, serviceId);
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
        address paymentToken, uint256 payment, address payable paymentReceiver)
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
        gParams.nonce = serviceId;
        service.multisig = _createGnosisSafeProxy(gParams);

        return service.multisig;
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) public view returns(bool) {
        return _mapServices[serviceId].owner != address(0);
    }
}
