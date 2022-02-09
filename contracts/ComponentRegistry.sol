// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRegistry.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is IMultihash, ERC721Enumerable, Ownable, ReentrancyGuard {
    // Component parameters
    struct Component {
        // Developer of the component
        address developer;
        // IPFS hash of the component
        Multihash[] componentHashes; // can be obtained via mapping, consider for optimization
        // Description of the component
        string description;
        // Set of component dependencies
        uint256[] dependencies;
        // Component activity
        bool active;
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
    mapping(bytes32 => uint256) private _mapHashTokenId;

    // name = "agent components", symbol = "MECHCOMP"
    constructor(string memory _name, string memory _symbol, string memory _bURI) ERC721(_name, _symbol) {
        _BASEURI = _bURI;
    }

    // Only the manager has a privilege to manipulate an component
    modifier onlyManager {
        require(_manager == msg.sender, "componentManager: MANAGER_ONLY");
        _;
    }

    // Checks for supplied IPFS hash
    modifier checkHash(Multihash memory hashStruct) {
        // Check hash IPFS current standard validity
        require(hashStruct.hashFunction == 0x12 && hashStruct.size == 0x20, "checkHash: WRONG_HASH");
        // Check for the existent IPFS hashes
        require(_mapHashTokenId[hashStruct.hash] == 0, "checkHash: HASH_EXISTS");
        _;
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
    function _setComponentInfo(uint256 tokenId, address developer, Multihash memory componentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Component storage component = _mapTokenIdComponent[tokenId];
        component.developer = developer;
        component.componentHashes.push(componentHash);
        component.description = description;
        component.dependencies = dependencies;
        component.active = true;
        _mapHashTokenId[componentHash.hash] = tokenId;
    }

    /// @dev Creates component.
    /// @param owner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component.
    function create(address owner, address developer, Multihash memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
        onlyManager
        checkHash(componentHash)
        nonReentrant
        returns (uint256)
    {
        // Checks for owner and developer being not zero addresses
        require(owner != address(0) && developer != address(0), "create: ZERO_ADDRESS");

        // Checks for non-empty description
        require(bytes(description).length > 0, "create: NO_DESCRIPTION");
        
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

    /// @dev Updates the component hash.
    /// @param owner Owner of the component.
    /// @param tokenId Token Id.
    /// @param componentHash New IPFS hash of the component.
    function updateHash(address owner, uint256 tokenId, Multihash memory componentHash)
        external
        onlyManager
        checkHash(componentHash)
    {
        require(ownerOf(tokenId) == owner, "update: COMPONENT_NOT_FOUND");
        Component storage component = _mapTokenIdComponent[tokenId];
        component.componentHashes.push(componentHash);
    }

    /// @dev Check for the token / component existence.
    /// @param tokenId Token Id.
    /// @return true if the component exists, false otherwise.
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    /// @dev Gets the component info.
    /// @param tokenId Token Id.
    /// @return owner Owner of the component.
    /// @return developer The component developer.
    /// @return componentHash The primary component IPFS hash.
    /// @return description The component description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 tokenId)
        public
        view
        returns (address owner, address developer, Multihash memory componentHash, string memory description,
            uint256 numDependencies, uint256[] memory dependencies)
    {
        require(_exists(tokenId), "getComponentInfo: NO_COMPONENT");
        Component storage component = _mapTokenIdComponent[tokenId];
        return (ownerOf(tokenId), component.developer, component.componentHashes[0], component.description,
            component.dependencies.length, component.dependencies);
    }

    /// @dev Gets component hashes.
    /// @param tokenId Token Id.
    /// @return numHashes Number of hashes.
    /// @return componentHashes The list of component hashes.
    function getHashes(uint256 tokenId) public view returns (uint256 numHashes, Multihash[] memory componentHashes) {
        require(_exists(tokenId), "getHashes: NO_COMPONENT");
        Component storage component = _mapTokenIdComponent[tokenId];
        return (component.componentHashes.length, component.componentHashes);
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
