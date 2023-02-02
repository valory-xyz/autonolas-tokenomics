// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

 error TransferFailed(address token, address from, address to, uint256 value);

/// @dev Mocking the service registry functionality.
contract MockRegistry {
    enum UnitType {
        Component,
        Agent
    }

    uint256 public constant SPECIAL_CASE_ID = 100;
    address[] public accounts;

    constructor() {
        accounts.push(address(1));
        accounts.push(address(2));
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) external pure returns (bool) {
        if (serviceId > 0 && serviceId < 3 || serviceId == SPECIAL_CASE_ID) {
            return true;
        }
        return false;
    }

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(UnitType, uint256 serviceId) external pure
        returns (uint256 numUnitIds, uint32[] memory unitIds)
    {
        unitIds = new uint32[](1);
        unitIds[0] = 1;
        numUnitIds = 1;

        // A special case to check the scenario when there are no unit Ids in the service
        if (serviceId == SPECIAL_CASE_ID) {
            numUnitIds = 0;
        }
    }

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return account Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address account) {
        // Return a default owner of a special case
        if (tokenId == SPECIAL_CASE_ID) {
            account = accounts[0];
        } else {
            account = accounts[tokenId - 1];
        }
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

    /// @dev Gets the value of slashed funds from the service registry.
    /// @return amount Drained amount.
    function slashedFunds() external view returns (uint256 amount) {
        amount = address(this).balance / 10;
    }

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount) {
        // Amount to drain is simulated to be 1/10th of the account balance
        amount = address(this).balance / 10;
        (bool result, ) = msg.sender.call{value: amount}("");
        if (!result) {
            revert TransferFailed(address(0), address(this), msg.sender, amount);
        }
    }

    /// @dev For drain testing.
    receive() external payable {
    }

}
