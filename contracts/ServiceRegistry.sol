// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "./AgentRegistry.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is IErrors, IStructs, Ownable, ERC721Enumerable, ReentrancyGuard {
    event Deposit(address sender, uint256 amount);
    event CreateService(address owner, string name, uint256 threshold, uint256 serviceId);
    event UpdateService(address owner, string name, uint256 threshold, uint256 serviceId);
    event RegisterInstance(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateSafeWithAgents(uint256 serviceId, address[] agentInstances, uint256 threshold);
    event ActivateRegistration(address owner, uint256 deadline, uint256 serviceId);
    event DestroyService(address owner, uint256 serviceId);
    event TerminateService(address owner, uint256 serviceId);
    event OperatorSlashed(uint256 amount, address operator, uint256 serviceId);
    event OperatorUnbond(uint256 refund, address operator, uint256 serviceId);
    event RewardService(uint256 serviceId, uint256 amount);

    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        ExpiredRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded,
        TerminatedUnbonded
    }

    struct AgentInstance {
        // Address of an agent instance
        address instance;
        // Canonical agent Id
        uint256 id;
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
        // Registration activation deposit
        uint256 securityDeposit;
        // Reward balance
        uint256 rewardBalance;
        address proxyContract;
        // Multisig address for agent instances
        address multisig;
        // Service name
        string name;
        // Service description
        string description;
        // IPFS hashes pointing to the config metadata
        Multihash[] configHashes;
        // Deadline until which all agent instances must be registered for this service
        uint256 registrationDeadline;
        // Agent instance signers threshold: must no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint256 threshold;
        // Total number of agent instances
        uint256 maxNumAgentInstances;
        // Actual number of agent instances
        uint256 numAgentInstances;
        // Canonical agent Ids for the service
        uint256[] agentIds;
        // Canonical agent Id => number of agent instances and correspondent instance registration bond
        mapping(uint256 => AgentParams) mapAgentParams;
        // Actual agent instance addresses. Canonical agent Id => Set of agent instance addresses.
        mapping(uint256 => address[]) mapAgentInstances;
        // Operator address => set of registered agent instance addresses
        mapping(address => AgentInstance[]) mapOperatorsAgentInstances;
        // Map of operator address => agent instance bonding / escrow balance
        // TODO Consider merging with another operator-related data structure
        mapping (address => uint256) mapOperatorsBalances;
        // Config hash per agent
//        mapping(uint256 => Multihash) mapAgentHash;
        // Service state
        ServiceState state;
    }

    // Selector of the Gnosis Safe setup function
    bytes4 internal constant _GNOSIS_SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Minimum deadline in blocks for registering agent instances (4 hours now to reduce test time)
    // TODO make this configurable via governance
    uint256 private _MIN_REGISTRATION_DEADLINE = 1095;
    // Agent Registry
    address public immutable agentRegistry;
    // Gnosis Safe
    address payable public immutable gnosisSafeL2;
    // Gnosis Safe Factory
    address public immutable gnosisSafeProxyFactory;
    // Service counter
    uint256 private _serviceIds;
    // The amount of funds slashed
    uint256 public slashedFunds;
    // Service Manager
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of agent instance address => service id it is registered with and operator address that supplied the instance
    mapping (address => OperatorServiceId) private _mapAllAgentInstances;
    // Map of canonical agent Id => set of service Ids that incorporate this canonical agent Id
    // Updated during the service deployment via createSafe() function
    mapping (uint256 => uint256[]) private _mapAgentIdSetServices;
    // Map of component Id => set of service Ids that incorporate canonical agents built on top of that component Id
    mapping (uint256 => uint256[]) private _mapComponentIdSetServices;

    constructor(string memory _name, string memory _symbol, address _agentRegistry, address payable _gnosisSafeL2,
        address _gnosisSafeProxyFactory) ERC721(_name, _symbol) {
        agentRegistry = _agentRegistry;
        gnosisSafeL2 = _gnosisSafeL2;
        gnosisSafeProxyFactory = _gnosisSafeProxyFactory;
    }

    // Only the manager has a privilege to manipulate a service
    modifier onlyManager {
        if (_manager != msg.sender) {
            revert ManagerOnly(msg.sender, _manager);
        }
        _;
    }

    // Only the owner of the service is authorized to manipulate it
    modifier onlyServiceOwner(address owner, uint256 serviceId) {
        if (owner == address(0) || !_exists(serviceId) || ownerOf(serviceId) != owner) {
            revert ServiceNotFound(serviceId);
        }
        _;
    }

    // Check for the service existence
    modifier serviceExists(uint256 serviceId) {
        if (!_exists(serviceId)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _;
    }

    /// @dev Fallback function
    fallback() external payable {
        revert WrongFunction();
    }

    /// @dev Receive function
    receive() external payable {
        revert WrongFunction();
    }

    /// @dev Going through basic initial service checks.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    function initialChecks(string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, AgentParams[] memory agentParams)
        private
        view
    {
        // Checks for non-empty strings
        if(bytes(name).length == 0 || bytes(description).length == 0) {
            revert EmptyString();
        }

        // Check for the hash format
        if (configHash.hashFunction != 0x12 || configHash.size != 0x20) {
            revert WrongHash(configHash.hashFunction, 0x12, configHash.size, 0x20);
        }

        // Checking for non-empty arrays and correct number of values in them
        if (agentIds.length == 0 || agentParams.length == 0 || agentIds.length != agentParams.length) {
            revert WrongAgentsData(agentIds.length, agentParams.length);
        }

        // Check for canonical agent Ids existence and for duplicate Ids
        uint256 lastId = 0;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentIds[i] <= lastId || !IRegistry(agentRegistry).exists(agentIds[i])) {
                revert WrongAgentId(agentIds[i]);
            }
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
    /// @param deadline Agent instance registration deadline.
    function activateRegistration(address owner, uint256 serviceId, uint256 deadline)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        nonReentrant
        payable
    {
        Service storage service = _mapServices[serviceId];
        // Service must be inactive
        if (service.state != ServiceState.PreRegistration) {
            revert ServiceMustBeInactive(serviceId);
        }

        if (msg.value != service.securityDeposit) {
            revert IncorrectRegistrationDepositValue(msg.value, service.securityDeposit, serviceId);
        }

        // Activate the agent instance registration and set the registration deadline
        uint256 minDeadline = block.number + _MIN_REGISTRATION_DEADLINE;
        if (deadline <= minDeadline) {
            revert RegistrationDeadlineIncorrect(deadline, minDeadline, serviceId);
        }
        service.state = ServiceState.ActiveRegistration;
        service.registrationDeadline = deadline;
        emit ActivateRegistration(owner, deadline, serviceId);
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param size Size of a canonical agent ids set.
    function _setServiceData(Service storage service, string memory name, string memory description, uint256 threshold,
        uint256[] memory agentIds, AgentParams[] memory agentParams, uint size)
        private
    {
        // Updating high-level data components of the service
        // Note that the deadline is not updated here since there is a different function for that
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        uint256 securityDeposit;

        // Add canonical agent Ids for the service and the slots map
        for (uint256 i = 0; i < size; i++) {
            service.agentIds.push(agentIds[i]);
            service.mapAgentParams[agentIds[i]] = agentParams[i];
            service.maxNumAgentInstances += agentParams[i].slots;
            // Security deposit is the maximum of the canonical agent registration bond
            if (agentParams[i].bond > securityDeposit) {
                securityDeposit = agentParams[i].bond;
            }
        }
        service.securityDeposit = securityDeposit;

        // Check for the correct threshold: no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint256 checkThreshold = service.maxNumAgentInstances * 2 + 1;
        if (checkThreshold % 3 == 0) {
            checkThreshold = checkThreshold / 3;
        } else {
            checkThreshold = checkThreshold / 3 + 1;
        }
        if(service.threshold < checkThreshold || service.threshold > service.maxNumAgentInstances) {
            revert WrongThreshold(service.threshold, checkThreshold, service.maxNumAgentInstances);
        }
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function createService(address owner, string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, AgentParams[] memory agentParams, uint256 threshold)
        external
        onlyManager
        returns (uint256 serviceId)
    {
        // Check for the non-empty owner address
        if (owner == address(0)) {
            revert ZeroAddress();
        }

        // Execute initial checks
        initialChecks(name, description, configHash, agentIds, agentParams);

        // Check that there are no zero number of slots for a specific canonical agent id and no zero registration bond
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0 || agentParams[i].bond == 0) {
                revert ZeroValue();
            }
        }

        // Create a new service Id
        _serviceIds++;
        serviceId = _serviceIds;

        // Set high-level data components of the service instance
        Service storage service = _mapServices[serviceId];
        // Fist hash is always pushed, since the updated one has to be checked additionally
        service.configHashes.push(configHash);

        // Set service data
        _setServiceData(service, name, description, threshold, agentIds, agentParams, agentIds.length);

        // Mint the service instance to the owner
        _safeMint(owner, serviceId);

        service.state = ServiceState.PreRegistration;

        emit CreateService(owner, name, threshold, serviceId);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    function update(address owner, string memory name, string memory description, Multihash memory configHash,
        uint256[] memory agentIds, AgentParams[] memory agentParams, uint256 threshold, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        Service storage service = _mapServices[serviceId];
        if (service.state != ServiceState.PreRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Execute initial checks
        initialChecks(name, description, configHash, agentIds, agentParams);

        // Collect non-zero canonical agent ids and slots / costs, remove any canonical agent Ids from the params map
        uint256[] memory newAgentIds = new uint256[](agentIds.length);
        AgentParams[] memory newAgentParams = new AgentParams[](agentIds.length);
        uint256 size;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0) {
                delete service.mapAgentParams[agentIds[i]];
            } else {
                newAgentIds[size] = agentIds[i];
                newAgentParams[size] = agentParams[i];
                size++;
            }
        }
        // Set of canonical agent Ids has to be completely overwritten (push-based)
        delete service.agentIds;
        // Check if the previous hash is the same / hash was not updated
        if (service.configHashes[service.configHashes.length - 1].hash != configHash.hash) {
            service.configHashes.push(configHash);
        }

        // Set service data
        _setServiceData(service, name, description, threshold, newAgentIds, newAgentParams, size);

        emit UpdateService(owner, name, threshold, serviceId);
    }

    /// @dev Sets agent instance registration deadline.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Service Id to be updated.
    /// @param deadline Registration deadline.
    function setRegistrationDeadline(address owner, uint256 serviceId, uint256 deadline)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
    {
        Service storage service = _mapServices[serviceId];
        // Registration deadline can be changed for the active-registration state when no agent are registered yet...
        if (service.state == ServiceState.ActiveRegistration && service.numAgentInstances == 0) {
            // Needs to be greater than the minimum required registration deadline
            uint256 minDeadline = block.number + _MIN_REGISTRATION_DEADLINE;
            if (deadline <= minDeadline) {
                revert RegistrationDeadlineIncorrect(deadline, minDeadline, serviceId);
            }
        // ... Or, during the finished-registration state to shorten the registration time
        } else if (service.state == ServiceState.FinishedRegistration) {
            // Deadline must not be smaller than the current block
            if (deadline < block.number) {
                revert RegistrationDeadlineIncorrect(deadline, block.number, serviceId);
            }
            // Deadline can only be shortened compared to the previous value
            if (deadline >= service.registrationDeadline) {
                revert RegistrationDeadlineChangeRedundant(deadline, service.registrationDeadline, serviceId);
            }
        } else {
            revert WrongServiceState(uint256(service.state), serviceId);
        }
        service.registrationDeadline = deadline;
    }

    /// @dev Terminates the service.
    /// @param owner Owner of the service.
    /// @param serviceId Service Id to be updated.
    function terminate(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        nonReentrant
    {
        Service storage service = _mapServices[serviceId];
        // Check if the service is already terminated
        if (service.state == ServiceState.PreRegistration || service.state == ServiceState.TerminatedBonded ||
            service.state == ServiceState.TerminatedUnbonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }
        // Define the state of the service depending on the number of bonded agent instances
        if (service.numAgentInstances > 0) {
            service.state = ServiceState.TerminatedBonded;
        } else {
            service.state = ServiceState.TerminatedUnbonded;
        }

        emit TerminateService(owner, serviceId);

        // Return registration deposit back to the owner
        uint256 refund = service.securityDeposit;
        // By design, the refund is always a non-zero value, so no check is needed here fo that
        (bool result, ) = owner.call{value: refund}("");
        if (!result) {
            // TODO When ERC20 token is used, change to the address of a token
            revert TransferFailed(address(0), address(this), owner, refund);
        }
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
        if (service.state != ServiceState.TerminatedUnbonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        _burn(serviceId);

        emit DestroyService(owner, serviceId);
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    function unbond(address operator, uint256 serviceId)
        external
        onlyManager
        nonReentrant
        returns (uint256 refund)
    {
        Service storage service = _mapServices[serviceId];
        // Service can only be in the terminated-bonded state or expired-registration in order to proceed
        if (service.state != ServiceState.TerminatedBonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the operator and unbond all its agent instances
        AgentInstance[] memory agentInstances = service.mapOperatorsAgentInstances[operator];
        uint256 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert OperatorHasNoInstances(operator, serviceId);
        }

        // Subtract number of unbonded agent instances
        service.numAgentInstances -= numAgentsUnbond;
        if (service.numAgentInstances == 0) {
            service.state = ServiceState.TerminatedUnbonded;
        }

        // Calculate registration refund and free all agent instances
        refund = 0;
        for (uint256 i = 0; i < numAgentsUnbond; i++) {
            refund += service.mapAgentParams[agentInstances[i].id].bond;
            // Since the service is done, there's no need to clean-up the service-related data, just the state variables
            delete _mapAllAgentInstances[agentInstances[i].instance];
        }

        // Calculate the refund
        uint256 balance = service.mapOperatorsBalances[operator];
        // This situation is possible if the operator was slashed for the agent instance misbehavior
        if (refund > balance) {
            refund = balance;
        }

        // Refund the operator
        if (refund > 0) {
            // Operator's balance is essentially zero after the refund
            service.mapOperatorsBalances[operator] = 0;
            // Send the refund
            (bool result, ) = operator.call{value: refund}("");
            if (!result) {
                // TODO When ERC20 token is used, change to the address of a token
                revert TransferFailed(address(0), address(this), operator, refund);
            }
        }

        emit OperatorUnbond(refund, operator, serviceId);
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
        nonReentrant
        payable
    {
        // Operator address must be different from agent instance one
        // Also, operator address must not be used as an agent instance anywhere else
        // TODO Need to check for the agent address to be EOA
        if (operator == agent || _mapAllAgentInstances[operator].serviceId > 0) {
            revert WrongOperator(serviceId);
        }

        Service storage service = _mapServices[serviceId];

        // The service has to be active to register agents
        if (service.state != ServiceState.ActiveRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check if the agent instance is already engaged with another service
        if (_mapAllAgentInstances[agent].serviceId > 0) {
            revert AgentInstanceRegistered(_mapAllAgentInstances[agent].serviceId);
        }

        // Check if the deadline for registering agent instances is still valid
        if (service.registrationDeadline <= block.number) {
            revert RegistrationTimeout(service.registrationDeadline, block.number, serviceId);
        }

        // Check if canonical agent Id exists in the service
        if (service.mapAgentParams[agentId].slots == 0) {
            revert AgentNotInService(agentId, serviceId);
        }

        // Check if there is an empty slot for the agent instance in this specific service
        if (service.mapAgentInstances[agentId].length == service.mapAgentParams[agentId].slots) {
            revert AgentInstancesSlotsFilled(serviceId);
        }

        if (msg.value < service.mapAgentParams[agentId].bond) {
            revert InsufficientAgentBondingValue(msg.value, service.mapAgentParams[agentId].bond, agentId, serviceId);
        }

        // Update operator's bonding / escrow balance
        service.mapOperatorsBalances[operator] += msg.value;
        emit Deposit(operator, msg.value);

        // Add agent instance and operator and set the instance engagement
        service.mapAgentInstances[agentId].push(agent);
        service.mapOperatorsAgentInstances[operator].push(AgentInstance(agent, agentId));
        service.numAgentInstances++;
        _mapAllAgentInstances[agent] = OperatorServiceId(operator, serviceId);

        // If the service agent instance capacity is reached, the service becomes finished-registration
        if (service.numAgentInstances == service.maxNumAgentInstances) {
            service.state = ServiceState.FinishedRegistration;
        }

        emit RegisterInstance(operator, serviceId, agent, agentId);
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    function slash(address[] memory agentInstances, uint256[] memory amounts, uint256 serviceId)
        public
        serviceExists(serviceId)
    {
        // Check for the array size
        if (agentInstances.length != amounts.length) {
            revert WrongAgentsData(agentInstances.length, amounts.length);
        }
        Service storage service = _mapServices[serviceId];
        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != service.multisig) {
            revert OnlyOwnServiceMultisig(msg.sender, service.multisig, serviceId);
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            OperatorServiceId memory operatorServiceId = _mapAllAgentInstances[agentInstances[i]];

            // Slash the balance of the operator, make sure it does not go below zero
            uint256 balance = service.mapOperatorsBalances[operatorServiceId.operator];
            if (amounts[i] >= balance) {
                // We can't add to the slashed amount more than the balance
                slashedFunds += balance;
                balance = 0;
            } else {
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            service.mapOperatorsBalances[operatorServiceId.operator] = balance;

            emit OperatorSlashed(amounts[i], operatorServiceId.operator, operatorServiceId.serviceId);
        }
    }

    /// @dev Gets the service payment / reward.
    /// @param serviceId Service Id.
    /// @return rewardBalance Actual reward balance of a service Id.
    function reward(uint256 serviceId)
        public
        payable
        serviceExists(serviceId)
        nonReentrant
        returns (uint256 rewardBalance)
    {
        rewardBalance = _mapServices[serviceId].rewardBalance;
        rewardBalance += msg.value;
        _mapServices[serviceId].rewardBalance = rewardBalance;
        emit RewardService(serviceId, msg.value);
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

    /// @dev Update the map of components / canonical agent Id => service id.
    /// @param serviceId Service Id.
    function _updateComponentAgentServiceConnection(uint256 serviceId) private {
        Service storage service = _mapServices[serviceId];
        // Loop over canonical agent Ids of the service
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 agentId = service.agentIds[i];
            // Add serviceId to the corresponding set. No need to check for duplicates since servieId is unique
            // and agentIds are unique for each serviceId
            _mapAgentIdSetServices[agentId].push(serviceId);

            // Get component dependencies of a current agent Id
            (, uint256[] memory dependencies) = IRegistry(agentRegistry).getDependencies(agentId);
            // Loop over component Ids
            for (uint256 j = 0; j < dependencies.length; j++) {
                uint256 componentId = dependencies[j];
                // Get the set of service Ids correspondent to the current component Id
                uint256[] memory idServicesInComponents = _mapComponentIdSetServices[componentId];
                uint256 k;
                // Loop over all the service Ids
                for (k = 0; k < idServicesInComponents.length; k++) {
                    // Skip if this serviceId is already in the set (for example, from another agentId extraction)
                    if (idServicesInComponents[k] == serviceId) {
                        break;
                    }
                }
                // Add service Id if not in the set of services for components yet
                if (k == idServicesInComponents.length) {
                    _mapComponentIdSetServices[componentId].push(serviceId);
                }
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
    /// @return Address of the created multisig.
    function createSafe(address owner, uint256 serviceId, address to, bytes calldata data, address fallbackHandler,
        address paymentToken, uint256 payment, address payable paymentReceiver, uint256 nonce)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        returns (address)
    {
        Service storage service = _mapServices[serviceId];
        if (service.state != ServiceState.FinishedRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Get all agent instances for the safe
        address[] memory agentInstances = _getAgentInstances(service);

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

        emit CreateSafeWithAgents(serviceId, agentInstances, service.threshold);

        _updateComponentAgentServiceConnection(serviceId);

        service.state = ServiceState.Deployed;

        return service.multisig;
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) public view returns (bool) {
        return _exists(serviceId);
    }

    /// @dev Gets the high-level service information.
    /// @param serviceId Service Id.
    /// @return owner Address of the service owner.
    /// @return name Name of the service.
    /// @return description Description of the service.
    /// @return configHash The most recent IPFS hash pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentIds Set of service canonical agents.
    /// @return agentParams Set of numbers of agent instances for each canonical agent Id.
    /// @return numAgentInstances Number of registered agent instances.
    /// @return agentInstances Set of agent instances currently registered for the service.
    /// @return multisig Agent instances multisig address.
    function getServiceInfo(uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (address owner, string memory name, string memory description, Multihash memory configHash,
            uint256 threshold, uint256 numAgentIds, uint256[] memory agentIds, AgentParams[] memory agentParams,
            uint256 numAgentInstances, address[] memory agentInstances, address multisig)
    {
        Service storage service = _mapServices[serviceId];
        agentParams = new AgentParams[](service.agentIds.length);
        numAgentInstances = service.numAgentInstances;
        agentInstances = _getAgentInstances(service);
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            agentParams[i] = service.mapAgentParams[service.agentIds[i]];
        }
        owner = ownerOf(serviceId);
        name = service.name;
        description = service.description;
        uint256 configHashesSize = service.configHashes.length - 1;
        configHash = service.configHashes[configHashesSize];
        threshold = service.threshold;
        numAgentIds = service.agentIds.length;
        agentIds = service.agentIds;
        multisig = service.multisig;
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

    /// @dev Gets service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of component hashes.
    function getConfigHashes(uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (uint256 numHashes, Multihash[] memory configHashes)
    {
        Service storage service = _mapServices[serviceId];
        return (service.configHashes.length, service.configHashes);
    }

    /// @dev Gets the agent instance registration deadline block number.
    /// @return registrationDeadline Registration deadline.
    function getRegistrationDeadline(uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (uint256 registrationDeadline)
    {
        registrationDeadline = _mapServices[serviceId].registrationDeadline;
    }

    /// @dev Gets the minimum registration deadline block number.
    /// @return minDeadline Minimum deadline.
    function getMinRegistrationDeadline() public view returns (uint256 minDeadline) {
        minDeadline = _MIN_REGISTRATION_DEADLINE;
    }

    /// @dev Gets the set of service Ids that contain specified agent Id.
    /// @param agentId Agent Id.
    /// @return numServiceIds Number of service Ids.
    /// @return serviceIds Set of service Ids.
    function getServiceIdsCreatedWithAgentId(uint256 agentId)
        public
        view
        returns (uint256 numServiceIds, uint256[] memory serviceIds)
    {
        serviceIds = _mapAgentIdSetServices[agentId];
        numServiceIds = serviceIds.length;
    }

    /// @dev Gets the set of service Ids that contain specified component Id (through the agent Id).
    /// @param componentId Component Id.
    /// @return numServiceIds Number of service Ids.
    /// @return serviceIds Set of service Ids.
    function getServiceIdsCreatedWithComponentId(uint256 componentId)
        public
        view
        returns (uint256 numServiceIds, uint256[] memory serviceIds)
    {
        serviceIds = _mapComponentIdSetServices[componentId];
        numServiceIds = serviceIds.length;
    }

    /// @dev Gets the service state.
    /// @param serviceId Service Id.
    /// @return state State of the service.
    function getServiceState(uint256 serviceId) public view returns (ServiceState state) {
        Service storage service = _mapServices[serviceId];
        state = service.state;

        // The expired state is not recorded explicitly and needs to be checked additionally
        if (state == ServiceState.ActiveRegistration && block.number > service.registrationDeadline) {
            state = ServiceState.ExpiredRegistration;
        }
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId)
        public
        view
        serviceExists(serviceId)
        returns (uint256 balance)
    {
        balance = _mapServices[serviceId].mapOperatorsBalances[operator];
    }
}
