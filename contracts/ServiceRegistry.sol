// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is Ownable {
    using Counters for Counters.Counter;

    struct Range {
        uint256 min;
        uint256 max;
    }

    // Service parameters
    struct Service {
        address owner;
        address proxyContract;
        string name;
        string description;
        uint256 threshold;
        // Total number of agent instances
        uint256 numAgentInstances;
        Range operatorSlots;
        // Canonical agent Ids
        uint256[] agents;
        // Agent instance numbers corresponding to each canonical agent Ids
        mapping(uint256 => uint256) mapAgentSlots;
        // Actual agent instance addresses
        mapping(uint256 => address[]) mapAgentInstances;
        // Config hash per agent
//        mapping(uint256 => string) mapAgentHash;
        bool active;
    }

    address public immutable agentRegistry;
    Counters.Counter private _serviceIds;
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of owner address => set of service Ids from that owner
    mapping (address => uint256[]) private _mapOwnerServices;

    constructor(address _agentRegistry) {
        agentRegistry = _agentRegistry;
    }

    /// @dev Changes the service manager.
    /// @param newManager Address of a new service manager.
    function changeServiceManager(address newManager) public onlyOwner {
        _manager = newManager;
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
    {
        // Only the manager has a privilege to register a service
        require(_manager == msg.sender, "createService: MANAGER_ONLY");

        // Checks for non-empty strings
        require(bytes(name).length > 0, "createService: EMPTY_NAME");
        require(bytes(description).length > 0, "createService: NO_DESCRIPTION");

        // Checking for non-empty and correct number of arrays
        require(agentSlots.length > 1 && agentSlots.length % 2 == 0, "createService: AGENTS_SLOTS");
        require(operatorSlots.length == 2 && operatorSlots[0] > 0 && operatorSlots[0] < operatorSlots[1],
            "createService: OPERATOR_SLOTS");

        // Get agent slots and check for the data validity
        _serviceIds.increment();
        Service storage service = _mapServices[_serviceIds.current()];
        AgentRegistry agReg = AgentRegistry(agentRegistry);
        for (uint256 i = 0; i < agentSlots.length; i += 2) {
            require (service.mapAgentSlots[agentSlots[i]] == 0, "createService: DUPLICATE_AGENT");
            require (agReg.exists(agentSlots[i]), "createService: AGENT_NOT_FOUND");
            service.mapAgentSlots[agentSlots[i]] = agentSlots[i + 1];
            service.numAgentInstances += agentSlots[i + 1];
        }

        // Check for the correct threshold: 2/3 number of agent instances + 1
        require(threshold > service.numAgentInstances * 2 / 3 && threshold <= service.numAgentInstances,
            "createService: THRESHOLD");

        service.owner = owner;
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.operatorSlots.min = operatorSlots[0];
        service.operatorSlots.max = operatorSlots[1];
        _mapOwnerServices[owner].push(_serviceIds.current());
    }


}
