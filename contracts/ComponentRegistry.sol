// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRegistry.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is ERC721Enumerable, Ownable, ReentrancyGuard {
    // Possible differentiation of component types
    enum ComponentType {CTYPE0, CTYPE1}

    struct Component {
        // Developer of the component
        address developer;
        // IPFS hash of the component
        string componentHash; // can be obtained via mapping, consider for optimization
        // Description of the component
        string description;
        // Set of component dependencies
        uint256[] dependencies;
        // Component activity
        bool active;
        // Component type
        ComponentType componentType;
    }

    // Base URI
    string public _BASEURI;
    // Component counter
    uint256 private _tokenIds;
    // Component manager
    address private _manager;
    // Map of token Id => component
    mapping(uint256 => Component) private _mapTokenIdComponent;
    // Map of IPFS hash => token Id
    mapping(string => uint256) private _mapHashTokenId;

    // name = "agent components", symbol = "MECHCOMP"
    constructor(string memory _name, string memory _symbol, string memory _bURI) ERC721(_name, _symbol) {
        _BASEURI = _bURI;
    }

    /// @dev Changes the component manager.
    /// @param newManager Address of a new component manager.
    function changeManager(address newManager) public onlyOwner {
        _manager = newManager;
    }

    /// @dev Sets the component data.
    /// @param tokenId Token / component Id.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies.
    function _setComponentInfo(uint256 tokenId, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Component memory component;
        component.developer = developer;
        component.componentHash = componentHash;
        component.description = description;
        component.dependencies = dependencies;
        component.active = true;
        _mapTokenIdComponent[tokenId] = component;
        _mapHashTokenId[componentHash] = tokenId;
    }

    /// @dev Creates component.
    /// @param owner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component.
    function create(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
        nonReentrant
        returns (uint256)
    {
        // Only the manager has a privilege to create a component
        require(_manager == msg.sender, "create: MANAGER_ONLY");

        // Checks for non-empty strings
        // How can we check for garbage hashes?
        require(bytes(componentHash).length > 0, "create: EMPTY_HASH");
        require(bytes(description).length > 0, "create: NO_DESCRIPTION");

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[componentHash] == 0, "create: HASH_EXISTS");
        
        // Check for dependencies validity: must be already allocated, must not repeat
        uint256 lastId = 0;
        for (uint256 iDep = 0; iDep < dependencies.length; iDep++) {
            require(dependencies[iDep] > lastId && dependencies[iDep] <= _tokenIds,
                "create: WRONG_COMPONENT_ID");
            lastId = dependencies[iDep];
        }

        // Mint token and initialize the component
        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        _setComponentInfo(newTokenId, developer, componentHash, description, dependencies);
        _safeMint(owner, newTokenId);

        return newTokenId;
    }

    /// @dev Check for the token / component existence.
    /// @param tokenId Token Id.
    /// @return true if the component exists, false otherwise.
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    /// @dev Gets the component info.
    /// @param tokenId Token Id.
    /// @return developer The component developer.
    /// @return componentHash The component IPFS hash.
    /// @return description The component description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 tokenId)
        public
        view
        returns (address developer, string memory componentHash, string memory description, uint256 numDependencies,
            uint256[] memory dependencies)
    {
        require(_exists(tokenId), "getComponentInfo: NO_COMPONENT");
        Component storage component = _mapTokenIdComponent[tokenId];
        return (component.developer, component.componentHash, component.description, component.dependencies.length,
            component.dependencies);
    }

    /// @dev Returns component base URI.
    /// @return base URI string.
    function _baseURI() internal view override returns (string memory) {
        return _BASEURI;
    }

    /// @dev Returns component base URI.
    /// @return base URI string.
    function getBaseURI() public view returns (string memory) {
        return _baseURI();
    }

    /// @dev Sets component base URI.
    /// @param bURI base URI string.
    function setBaseURI(string memory bURI) public onlyOwner {
        _BASEURI = bURI;
    }
}
