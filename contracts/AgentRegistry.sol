// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRegistry.sol";

/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistry is ERC721Enumerable, Ownable {
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
    uint256 private _tokenIds;
    // Agent manager
    address private _manager;
    // Map of token Id => component
    mapping(uint256 => Agent) private _mapTokenIdAgent;
    // Map of IPFS hash => token Id
    mapping(string => uint256) private _mapHashTokenId;

    // name = "agent", symbol = "MECH"
    constructor(string memory _name, string memory _symbol, string memory _bURI, address _componentRegistry)
        ERC721(_name, _symbol) {
        _BASEURI = _bURI;
        componentRegistry = _componentRegistry;
    }

    /// @dev Changes the agent manager.
    /// @param newManager Address of a new agent manager.
    function changeManager(address newManager) public onlyOwner {
        _manager = newManager;
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
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted agent.
    function create(address owner, address developer, string memory agentHash, string memory description,
        uint256[] memory dependencies)
        external
        returns (uint256)
    {
        // Only the manager has a privilege to create a component
        require(_manager == msg.sender, "create: MANAGER_ONLY");

        // Checks for non-empty strings and component dependency
        require(bytes(agentHash).length > 0, "create: EMPTY_HASH");
        require(bytes(description).length > 0, "create: NO_DESCRIPTION");
//        require(dependencies.length > 0, "Agent must have at least one component dependency");

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[agentHash] == 0, "create: HASH_EXISTS");

        // Check for dependencies validity: must be already allocated, must not repeat
        uint256 lastId = 0;
        for (uint256 iDep = 0; iDep < dependencies.length; iDep++) {
            require(dependencies[iDep] > lastId && IRegistry(componentRegistry).exists(dependencies[iDep]),
                "create: WRONG_COMPONENT_ID");
            lastId = dependencies[iDep];
        }

        // Mint token and initialize the component
        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        _safeMint(owner, newTokenId);
        _setAgentInfo(newTokenId, developer, agentHash, description, dependencies);

        return newTokenId;
    }

    /// @dev Check for the token / agent existence.
    /// @param tokenId Token Id.
    /// @return true if the agent exists, false otherwise.
    function exists (uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    /// @dev Gets the agent info.
    /// @param tokenId Token Id.
    /// @return developer The agent developer.
    /// @return agentHash The agent IPFS hash.
    /// @return description The agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getMechInfo(uint256 tokenId)
        public
        view
        returns (address developer, string memory agentHash, string memory description, uint256 numDependencies,
            uint256[] memory dependencies)
    {
        require(_exists(tokenId), "getComponentInfo: NO_AGENT");
        Agent storage agent = _mapTokenIdAgent[tokenId];
        return (agent.developer, agent.agentHash, agent.description, agent.dependencies.length, agent.dependencies);
    }

    /// @dev Returns agent base URI.
    /// @return base URI string.
    function _baseURI() internal view override returns (string memory) {
        return _BASEURI;
    }

    /// @dev Returns agent base URI.
    /// @return base URI string.
    function getBaseURI() public view returns (string memory) {
        return _baseURI();
    }

    /// @dev Sets agent base URI.
    /// @param bURI base URI string.
    function setBaseURI(string memory bURI) public onlyOwner {
        _BASEURI = bURI;
    }
}
