// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "./AgentRegistry.sol";
import "./interfaces/IRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is IMultihash, Ownable {
    event CreateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event UpdateServiceTransaction(address owner, string name, uint256 threshold, uint256 serviceId);
    event RegisterInstanceTransaction(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateSafeWithAgents(uint256 serviceId, address[] agentInstances, uint256 threshold);
    event ActivateService(address owner, uint256 serviceId);
    event DeactivateService(address owner, uint256 serviceId);
    event DestroyService(address owner, uint256 serviceId);

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
        // owner of the service and viability state: no owner - no service or deleted
        address owner;
        address proxyContract;
        // Multisig address for agent instances
        address multisig;
        string name;
        string description;
        // IPFS hash pointing to the config metadata
        Multihash configHash;
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
        // Canonical agent Ids for the service
        uint256[] agentIds;
        // Canonical agent Id => Number of agent instances.
        mapping(uint256 => uint256) mapAgentSlots;
        // Actual agent instance addresses. Canonical agent Id => Set of agent instance addresses.
        mapping(uint256 => address[]) mapAgentInstances;
        // Agent instance address => operator address
        mapping(address => address) mapAgentInstancesOperators;
        // Config hash per agent
//        mapping(uint256 => Multihash) mapAgentHash;
        // Service activity state
        bool active;
    }

    // Selector of the Gnosis Safe setup function
    bytes4 internal constant _GNOSIS_SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Default timeout window for getting the agent instances registered for the service (21 days)
    uint256 private constant _AGENT_INSTANCE_REGISTRATION_TIMEOUT = 1814400;
    // Agent Registry
    address public immutable agentRegistry;
    // Gnosis Safe
    address payable public immutable gnosisSafeL2;
    // Gnosis Safe Factory
    address public immutable gnosisSafeProxyFactory;
    // Service counter
    uint256 private _serviceIds;
    // Actual number of services
    uint256 private _actualNumServices;
    // Service Manager
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of owner address => set of service Ids that belong to that owner
    mapping (address => uint256[]) private _mapOwnerSetServices;
    // Map of agent instance addres => if engaged with a service
    mapping (address => bool) private _mapAllAgentInstances;

    constructor(address _agentRegistry, address payable _gnosisSafeL2, address _gnosisSafeProxyFactory) {
        agentRegistry = _agentRegistry;
        gnosisSafeL2 = _gnosisSafeL2;
        gnosisSafeProxyFactory = _gnosisSafeProxyFactory;
    }

    // Only the manager has a privilege to update a service
    modifier onlyManager {
        require(_manager == msg.sender, "serviceManager: MANAGER_ONLY");
        _;
    }

    // Only the owner of the service is authorized to manipulate it
    modifier onlyServiceOwner(address owner, uint256 serviceId) {
        require(owner != address(0) && _mapServices[serviceId].owner == owner, "serviceOwner: SERVICE_NOT_FOUND");
        _;
    }

    // Check for the service existence
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
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    function initialChecks(string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, uint256[] memory agentNumSlots)
        private
        view
    {
        // Checks for non-empty strings
        require(bytes(name).length > 0, "initCheck: EMPTY_NAME");
        require(bytes(description).length > 0, "initCheck: NO_DESCRIPTION");
        require(configHash.hashFunction == 0x12 && configHash.size == 0x20, "initCheck: WRONG_HASH");

        // Checking for non-empty arrays and correct number of values in them
        require(agentIds.length > 0 && agentIds.length == agentNumSlots.length, "initCheck: AGENTS_SLOTS");

        // Check for canonical agent Ids existence and for duplicate Ids
        uint256 lastId = 0;
        for (uint256 i = 0; i < agentIds.length; i++) {
            require(agentIds[i] > lastId && IRegistry(agentRegistry).exists(agentIds[i]),
                "initCheck: WRONG_AGENT_ID");
            lastId = agentIds[i];
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
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        noRegisteredAgentInstance(serviceId)
    {
        // Service must be active
        require(_mapServices[serviceId].active, "deactivate: SERVICE_INACTIVE");

        _mapServices[serviceId].active = false;
        emit DeactivateService(owner, serviceId);
    }

    /// @dev Destroys the service instance.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    function destroy(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        Service storage service = _mapServices[serviceId];
        // There must be no registered agent instances while the termination block is infinite
        // or the termination block need to be less than the current block (expired)
        // or the service is inactive in a first place
        require(service.active == false ||
            (service.terminationBlock == 0 && _mapServices[serviceId].numAgentInstances == 0) ||
            (service.terminationBlock > 0 && service.terminationBlock < block.number), "destroy: SERVICE_ACTIVE");

        service.owner = address(0);

        // Need to update the set of owner service Ids
        uint256 numServices = _mapOwnerSetServices[owner].length;
        for (uint256 i = 0; i < numServices; i++) {
            if (_mapOwnerSetServices[owner][i] == serviceId) {
                // Pop the destroyed service Id
                _mapOwnerSetServices[owner][i] = _mapOwnerSetServices[owner][numServices - 1];
                _mapOwnerSetServices[owner].pop();
                break;
            }
        }

        // Reduce the actual number of services
        _actualNumServices--;

        emit DestroyService(owner, serviceId);
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param agentIds Canonical agent Ids.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param size Size of a canonical agent ids set.
    function _setServiceData(Service storage service, string memory name, string memory description,
        Multihash memory configHash, uint256 threshold, uint256[] memory agentIds, uint256[] memory agentNumSlots,
        uint size)
        private
    {
        // Updating high-level data components of the service
        // Note that the deadline is not updated here since there is a different function for that
        service.name = name;
        service.description = description;
        service.configHash = configHash;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        // Add canonical agent Ids for the service and the slots map
        for (uint256 i = 0; i < size; i++) {
            service.agentIds.push(agentIds[i]);
            service.mapAgentSlots[agentIds[i]] = agentNumSlots[i];
            service.maxNumAgentInstances += agentNumSlots[i];
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
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function createService(address owner, string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, uint256[] memory agentNumSlots, uint256 threshold)
        external
        onlyManager
        returns (uint256 serviceId)
    {
        // Check for the non-empty owner address
        require(owner != address(0), "createService: EMPTY_OWNER");

        // Execute initial checks
        initialChecks(name, description, configHash, agentIds, agentNumSlots);

        // Check that there are no zero number of slots for a specific canonical agent id
        for (uint256 i = 0; i < agentIds.length; i++) {
            require(agentNumSlots[i] > 0, "createService: EMPTY_SLOTS");
        }

        // Create a new service Id
        _serviceIds++;
        serviceId = _serviceIds;

        // Set high-level data components of the service instance
        Service storage service = _mapServices[serviceId];
        service.owner = owner;
        service.deadline = block.timestamp + _AGENT_INSTANCE_REGISTRATION_TIMEOUT;

        // Set service data
        _setServiceData(service, name, description, configHash, threshold, agentIds, agentNumSlots, agentIds.length);

        // Add service to the set of services for the owner
        _mapOwnerSetServices[owner].push(serviceId);

        // Increment the total number of services
        _actualNumServices++;

        emit CreateServiceTransaction(owner, name, threshold, serviceId);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentNumSlots Agent instance number of slots correspondent to canonical agent Ids.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    function updateService(address owner, string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, uint256[] memory agentNumSlots, uint256 threshold, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        noRegisteredAgentInstance(serviceId)
    {
        // Execute initial checks
        initialChecks(name, description, configHash, agentIds, agentNumSlots);

        // Collect non-zero canonical agent ids and slots, remove any canonical agent Ids from the slots map
        Service storage service = _mapServices[serviceId];
        uint256[] memory newAgentIds = new uint256[](agentIds.length);
        uint256[] memory newAgentNumSlots = new uint256[](agentIds.length);
        uint256 size;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentNumSlots[i] == 0) {
                service.mapAgentSlots[agentIds[i]] = 0;
            } else {
                newAgentIds[size] = agentIds[i];
                newAgentNumSlots[size] = agentNumSlots[i];
                size++;
            }
        }

        // Set service data
        _setServiceData(service, name, description, configHash, threshold, newAgentIds, newAgentNumSlots, size);

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
        // TODO Need to check for the operator to be EOA?
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
        service.mapAgentInstances[agentId].push(agent);
        service.mapAgentInstancesOperators[agent] = operator;
        service.numAgentInstances++;
        _mapAllAgentInstances[agent] = true;

        emit RegisterInstanceTransaction(operator, serviceId, agent, agentId);
    }

    /// @dev Creates Gnosis Safe proxy.
    /// @param gParams Structure with parameters to setup Gnosis Safe.
    /// @return Address of the created proxy.
    function _createGnosisSafeProxy(GnosisParams memory gParams) private returns (address) {
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
    function _getAgentInstances(Service storage service) private view returns (address[] memory agentInstances) {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 agentId = service.agentIds[i];
            for (uint256 j = 0; j < service.mapAgentInstances[agentId].length; j++) {
                agentInstances[count] = service.mapAgentInstances[agentId][j];
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
    function exists(uint256 serviceId) public view returns (bool) {
        return _mapServices[serviceId].owner != address(0);
    }

    /// @dev Gets the total number of services in the contract.
    /// @return actualNumServices Actual number of services.
    /// @return maxServiceId Max serviceId number.
    function totalSupply() public view returns (uint256 actualNumServices, uint256 maxServiceId) {
        actualNumServices = _actualNumServices;
        maxServiceId = _serviceIds;
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
    /// @return threshold Agent instance signers threshold.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentIds Set of service canonical agents.
    /// @return agentNumSlots Set of numbers of agent instances for each canonical agent Id.
    /// @return numAgentInstances Number of registered agent instances.
    /// @return agentInstances Set of agent instances currently registered for the service.
    /// @return active True if the service is active.
    function getServiceInfo(uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (address owner, string memory name, string memory description, uint256 threshold, uint256 numAgentIds,
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
        threshold = service.threshold;
        numAgentIds = service.agentIds.length;
        agentIds = service.agentIds;
        active = service.active;
    }

    /// @dev Lists all the instances of a given canonical agent Id if the service.
    /// @param serviceId Service Id.
    /// @param agentId Canonical agent Id.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Set of agent instances for a specified canonical agent Id.
    function getInstancesForAgentId(uint256 serviceId, uint256 agentId)
        public
        view
        serviceExists(serviceId)
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        Service storage service = _mapServices[serviceId];
        numAgentInstances = service.mapAgentInstances[agentId].length;
        agentInstances = new address[](numAgentInstances);
        for (uint256 i = 0; i < numAgentInstances; i++) {
            agentInstances[i] = service.mapAgentInstances[agentId][i];
        }
    }
}
