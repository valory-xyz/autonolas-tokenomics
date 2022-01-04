// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ComponentRegistry.sol";

/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistry is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    // Possible differentiation of component types
    enum AgentType {ATYPE0, ATYPE1}

    struct Agent {
        // Developer of the agent
        address developer;
        // IPFS hash of the agent
        string agentHash; // can be obtained via mapping, consider for optimization
        // Description of the agent
        string description;
        // Set of component dependencies
        uint256[] dependencies;
        // Agent activity
        bool active;
        // Agent type
        AgentType componentType;
    }

    // Component registry
    address public immutable componentRegistry;
    // Base URI
    string public _BASEURI;
    // Agent counter
    Counters.Counter private _tokenIds;
    // Agent minter
    address private _minter;
    // Map of token Id => component
    mapping(uint256 => Agent) private _mapTokenIdAgent;
    // Map of IPFS hash => token Id
    mapping(string => uint256) private _mapHashTokenId;
    // Map for checking on unique token Ids
    mapping(uint256 => bool) private _mapDependencies;

    // name = "agent", symbol = "MECH"
    constructor(string memory _name, string memory _symbol, string memory _bURI, address _componentRegistry)
        ERC721(_name, _symbol) {
        require(bytes(_bURI).length > 0, "Base URI can not be empty");
        _BASEURI = _bURI;
        componentRegistry = _componentRegistry;
    }

    /// @dev Changes the agent minter.
    /// @param newMinter Address of a new agent minter.
    function changeMinter(address newMinter) public onlyOwner {
        _minter = newMinter;
    }

    /// @dev Set the agent data.
    /// @param tokenId Token / agent Id.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies.
    function _setAgentInfo(uint256 tokenId, address developer, string memory agentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Agent memory agent;
        agent.developer = developer;
        agent.agentHash = agentHash;
        agent.description = description;
        agent.dependencies = dependencies;
        agent.active = true;
        _mapTokenIdAgent[tokenId] = agent;
        _mapHashTokenId[agentHash] = tokenId;
    }

    /// @dev Creates agent.
    /// @param owner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies.
    /// @return The minted id of the agent.
    function createAgent(address owner, address developer, string memory agentHash, string memory description,
        uint256[] memory dependencies)
        external
        returns (uint256)
    {
        // Only the minter has a privilege to create a component
        require(_minter == msg.sender, "createAgent: MINTER_ONLY");

        // Checks for non-empty strings and component dependency
        require(bytes(agentHash).length > 0, "createAgent: EMPTY_HASH");
        require(bytes(description).length > 0, "createAgent: NO_DESCRIPTION");
//        require(dependencies.length > 0, "Agent must have at least one component dependency");

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[agentHash] == 0, "createAgent: HASH_EXISTS");

        // Check for dependencies validity: must be already allocated, must not repeat
        uint256 uCounter;
        uint256[] memory uniqueDependencies = new uint256[](dependencies.length);
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        for (uint256 iDep = 0; iDep < dependencies.length; iDep++) {
            require(dependencies[iDep] > 0, "createAgent: NO_COMPONENT_ID");
            if (_mapDependencies[dependencies[iDep]]) {
                continue;
            } else {
                require(compRegistry.exists(dependencies[iDep]), "The component is not found!");
                _mapDependencies[dependencies[iDep]] = true;
                uniqueDependencies[uCounter] = dependencies[iDep];
                uCounter++;
            }
        }

        // Revert the state of mapping to filter duplicate components to its original state
        // Allocate array with precise number of unique dependencies
        uint256[] memory finalDependencies = new uint256[](uCounter);
        for (uint256 iDep = 0; iDep < uCounter; iDep++) {
            _mapDependencies[uniqueDependencies[iDep]] = false;
            finalDependencies[iDep] = uniqueDependencies[iDep];
        }

        // Mint token and initialize the component
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(owner, newTokenId);
        _setAgentInfo(newTokenId, developer, agentHash, description, finalDependencies);

        return newTokenId;
    }

    /// @dev Check for the token / agent existence.
    /// @param _tokenId Token Id.
    /// @return true if the agent exists, false otherwise.
    function exists (uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    /// @dev Returns base URI that was set in the constructor.
    /// @return base URI string.
    function _baseURI() internal view override returns (string memory) {
        return _BASEURI;
    }

    /// @dev Gets the agent info.
    /// @param _tokenId Token Id.
    /// @return developer The agent developer.
    /// @return agentHash The agent IPFS hash.
    /// @return description The agent description.
    /// @return dependencies The list of component dependencies.
    function getAgentInfo(uint256 _tokenId)
        public
        view
        returns (address developer, string memory agentHash, string memory description, uint256[] memory dependencies)
    {
        require(_exists(_tokenId), "getComponentInfo: NO_AGENT");
        Agent storage agent = _mapTokenIdAgent[_tokenId];
        return (agent.developer, agent.agentHash, agent.description, agent.dependencies);
    }
}
