// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ProxyMinter.sol";

contract ComponentRegistry is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    // Possible differentiation of component types
    enum ComponentType {COMPONENT, AGENT}

    struct Component {
        address developer;
        string componentHash; // can be obtained via mapping, consider for optimization
        string description;
        uint256[] dependencies;
        bool active;
        ComponentType componentType;
    }

    Counters.Counter private _tokenIds;
    address private _minter;
    address private immutable _proxyMinter;
    mapping (uint256 => Component) private _mapTokenIdComponent;
    mapping (string => uint256) private _mapHashTokenId;

    constructor() ERC721("AgentComponents", "MECHCOMP") {
        _tokenIds.increment();
    }

    // Change the minter
    function changeMinter(address newMinter) public onlyOwner {
        require(_minter == msg.sender);
        _minter = newMinter;
    }

    // Set the component information
    function _setComponentInfo(uint256 tokenId, address developer, string memory componentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Component storage component;
        component.developer = developer;
        component.componentHash = componentHash;
        component.description = description;
        component.dependencies = dependencies;
        component.active = true;
        _mapTokenIdComponent[tokenId] = component;
    }

    // Mint component according to developer's address and component parameters
    function createComponent(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        external
    {
        // Only the minter has a privilege to create a component
        require(_minter == msg.sender);

        // Check for the existent IPFS hashes
        require(_mapHashTokenId[componentHash] == 0, "The component with this hash already exists!");

        // Check for dependencies validity
        bool depValid = true;
        uint256 iDep = 0;
        for (; iDep < dependencies.length; iDep++) {
            if(dependencies[iDep] > _tokenIds.current()) {
                depValid = false;
                break;
            }
        }
        require(depValid == true, "The component with token ID " + dependencies[iDep] + " does not exist!");

        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();
        _safeMint(owner, newTokenId);
        _setComponentInfo(newTokenId, developer, componentHash, description, dependencies);
    }

    // Same as above for the same developer and owner
    function createComponent(address owner, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        public
    {
        createComponent(owner, componentHash, description, dependencies);
    }

    // Function to call the minter with the
    // Need to use delegatecall or other more optimal ways
    function mintComponent(address owner, address developer, string memory componentHash, string memory description,
        uint256[] memory dependencies)
        public
    {
        ProxyMinter proxyMinter = ProxyMinter(_proxyMinter);
        proxyMinter.mintComponent(owner, developer, componentHash, description, dependencies);
    }

    // In order to burn, the inactive component needs to propagate its state to dependent components
    function _burn(uint256 tokenId)
        internal
        override
    {
        require(ownerOf(tokenId) == msg.sender, "You have no priviledge to burn this token");
        // The functionality will follow
    }
}
