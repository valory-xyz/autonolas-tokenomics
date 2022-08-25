// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/// @dev Mocking the service registry functionality.
contract MockRegistry {
    enum UnitType {
        Component,
        Agent
    }

    address[] public accounts;

    constructor() {
        accounts.push(address(1));
        accounts.push(address(2));
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) external pure returns (bool) {
        if (serviceId > 0 && serviceId < 3) {
            return true;
        }
        return false;
    }

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(UnitType, uint256) external pure
        returns (uint256 numUnitIds, uint32[] memory unitIds)
    {
        unitIds = new uint32[](1);
        unitIds[0] = 1;
        numUnitIds = 1;
    }

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return account Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address account) {
        account = accounts[tokenId - 1];
    }

    /// @dev Changes the component / agent / service owner.
    function changeUnitOwner(uint256 tokenId, address newOwner) external {
        accounts[tokenId - 1] = newOwner;
    }

    /// @dev Gets the total supply of units.
    function totalSupply() external view returns(uint256) {
        return accounts.length;
    }

    /// @dev Gets service owners.
    function getUnitOwners() external view returns (address[] memory) {
        return accounts;
    }
}
