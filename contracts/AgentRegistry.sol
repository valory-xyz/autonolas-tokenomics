// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ComponentRegistry.sol";

contract AgentRegistry is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    // Possible differentiation of component types
    enum AgentType {ATYPE0, ATYPE1}

    struct Agent {
        address developer;
        string agentHash; // can be obtained via mapping, consider for optimization
        string description;
        uint256[] dependencies;
        bool active;
        AgentType componentType;
    }

    address public immutable componentRegistry;
    string public _BASEURI;
    Counters.Counter private _tokenIds;
    address private _minter;
    mapping(uint256 => Agent) private _mapTokenIdAgent;
    mapping(string => uint256) private _mapHashTokenId;
    mapping(uint256 => bool) private _mapDependencies;

    // name = "agent", symbol = "MECH"
    constructor(string memory _name, string memory _symbol, string memory _bURI, address _componentRegistry)
        ERC721(_name, _symbol) {
        require(bytes(_bURI).length > 0, "Base URI can not be empty");
        _BASEURI = _bURI;
        componentRegistry = _componentRegistry;
    }

    // Change the minter
    function changeMinter(address newMinter) public onlyOwner {
        _minter = newMinter;
    }

    // Set the component information
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

    // Mint component according to developer's address and component parameters
    function createAgent(address owner, address developer, string memory agentHash, string memory description,
        uint256[] memory dependencies)
        external
        returns (bool)
    {
        // Only the minter has a privilege to create a component
        require(_minter == msg.sender);

        // Checks for non-empty strings
        require(bytes(agentHash).length > 0, "Component hash can not be empty");
        require(bytes(description).length > 0, "Description can not be empty");

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[agentHash] == 0, "The agent with this hash already exists!");

        // Check for dependencies validity: must be already allocated, must not repeat
        ComponentRegistry compRegistry = ComponentRegistry(componentRegistry);
        uint256 iDep = 0;
        while(iDep < dependencies.length) {
            if (_mapDependencies[dependencies[iDep]]) {
                dependencies[iDep] = dependencies[dependencies.length - 1];
                delete dependencies[dependencies.length - 1];
            } else {
                _mapDependencies[dependencies[iDep]] = true;
                iDep++;
            }
            require(compRegistry.exists(dependencies[iDep]), "The component is not found!");
        }

        // Revert the state of mapping to filter duplicate components to its original state
        for (iDep = 0; iDep < dependencies.length; iDep++) {
            _mapDependencies[dependencies[iDep]] = false;
        }

        // Mint token and initialize the component
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(owner, newTokenId);
        _setAgentInfo(newTokenId, developer, agentHash, description, dependencies);

        return true;
    }

    // Returns base URI set in the constructor
    function _baseURI() internal view override returns (string memory) {
        return _BASEURI;
    }

    // In order to burn, the inactive component needs to propagate its state to dependent components
    function _burn(uint256 tokenId) internal view override
    {
        require(ownerOf(tokenId) == msg.sender, "You have no priviledge to burn this token");
        // The functionality will follow in the following revisions
    }
}
