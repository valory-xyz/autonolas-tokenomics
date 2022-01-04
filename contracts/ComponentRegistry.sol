// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

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
    Counters.Counter private _tokenIds;
    // Component minter
    address private _minter;
    // Map of token Id => component
    mapping(uint256 => Component) private _mapTokenIdComponent;
    // Map of IPFS hash => token Id
    mapping(string => uint256) private _mapHashTokenId;
    // Map for checking on unique token Ids
    mapping(uint256 => bool) private _mapDependencies;

    // name = "agent components", symbol = "MECHCOMP"
    constructor(string memory _name, string memory _symbol, string memory _bURI) ERC721(_name, _symbol) {
        require(bytes(_bURI).length > 0, "Base URI can not be empty");
        _BASEURI = _bURI;
    }

    /// @dev Changes the component minter.
    /// @param newMinter Address of a new component minter.
    function changeMinter(address newMinter) public onlyOwner {
        _minter = newMinter;
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
    /// @param dependencies Set of component dependencies.
    /// @return The minted id of the component.
    function createComponent(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
        returns (uint256)
    {
        // Only the minter has a privilege to create a component
        require(_minter == msg.sender, "createComponent: MINTER_ONLY");

        // Checks for non-empty strings
        // How can we check for garbage hashes?
        require(bytes(componentHash).length > 0, "createComponent: EMPTY_HASH");
        require(bytes(description).length > 0, "createComponent: NO_DESCRIPTION");

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[componentHash] == 0, "createComponent: HASH_EXISTS");
        
        // Check for dependencies validity: must be already allocated, must not repeat
        uint256 uCounter;
        uint256[] memory uniqueDependencies = new uint256[](dependencies.length);
        for (uint256 iDep = 0; iDep < dependencies.length; iDep++) {
            require(dependencies[iDep] > 0 && dependencies[iDep] <= _tokenIds.current(),
                "createComponent: NO_COMPONENT_ID");
            if (_mapDependencies[dependencies[iDep]]) {
                continue;
            } else {
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
        _setComponentInfo(newTokenId, developer, componentHash, description, finalDependencies);

        return newTokenId;
    }

    /// @dev Check for the token / component existence.
    /// @param _tokenId Token Id.
    /// @return true if the component exists, false otherwise.
    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    /// @dev Returns base URI that was set in the constructor.
    /// @return base URI string.
    function _baseURI() internal view override returns (string memory) {
        return _BASEURI;
    }

    /// @dev Gets the component info.
    /// @param _tokenId Token Id.
    /// @return developer The component developer.
    /// @return componentHash The component IPFS hash.
    /// @return description The component description.
    /// @return dependencies The list of component dependencies.
    function getComponentInfo(uint256 _tokenId)
        public
        view
        returns (address developer, string memory componentHash, string memory description,
            uint256[] memory dependencies)
    {
        require(_exists(_tokenId), "getComponentInfo: NO_COMPONENT");
        Component storage component = _mapTokenIdComponent[_tokenId];
        return (component.developer, component.componentHash, component.description, component.dependencies);
    }
}
