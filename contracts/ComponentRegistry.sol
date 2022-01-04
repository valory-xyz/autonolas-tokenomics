// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ComponentRegistry is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    // Possible differentiation of component types
    enum ComponentType {CTYPE0, CTYPE1}

    struct Component {
        address developer;
        string componentHash; // can be obtained via mapping, consider for optimization
        string description;
        uint256[] dependencies;
        bool active;
        ComponentType componentType;
    }

    string public _BASEURI;
    Counters.Counter private _tokenIds;
    address private _minter;
    mapping(uint256 => Component) private _mapTokenIdComponent;
    mapping(string => uint256) private _mapHashTokenId;
    mapping(uint256 => bool) private _mapDependencies;

    // name = "agent components", symbol = "MECHCOMP"
    constructor(string memory _name, string memory _symbol, string memory _bURI) ERC721(_name, _symbol) {
        require(bytes(_bURI).length > 0, "Base URI can not be empty");
        _BASEURI = _bURI;
    }

    // Change the minter
    function changeMinter(address newMinter) public onlyOwner {
        _minter = newMinter;
    }

    // Set the component information
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

    // Mint component according to developer's address and component parameters
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

    // Externalizing function to check for the token existence from a different contract
    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    // Returns base URI set in the constructor
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
        require(_exists(_tokenId), "getComponentInfo: NO_TOKENID");
        Component storage component = _mapTokenIdComponent[_tokenId];
        return (component.developer, component.componentHash, component.description, component.dependencies);
    }
}
