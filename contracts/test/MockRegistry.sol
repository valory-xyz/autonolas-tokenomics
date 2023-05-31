// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

 error TransferFailed(address token, address from, address to, uint256 value);

/// @dev Mocking the service registry functionality.
contract MockRegistry {
    enum UnitType {
        Component,
        Agent
    }

    uint256 public constant NON_DEPLOYED_SERVICE_ID = 100;
    uint256 public constant NUM_UNITS = 30;
    address[] public accounts;

    constructor() {
        for (uint256 i = 1; i <= NUM_UNITS; ++i) {
            accounts.push(address(uint160(i)));
        }
    }

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) external pure returns (bool) {
        if (serviceId > 0 && serviceId < 50 || serviceId == NON_DEPLOYED_SERVICE_ID) {
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
        numUnitIds = 1;
        unitIds = new uint32[](1);
        unitIds[0] = 1;

        // A special case to check the scenario when there are no unit Ids in the service
        if (serviceId == NON_DEPLOYED_SERVICE_ID) {
            numUnitIds = 0;
        } else if (serviceId > 2) {
            numUnitIds = serviceId;
            unitIds = new uint32[](numUnitIds);
            for (uint32 i = 0; i < numUnitIds; ++i) {
                unitIds[i] = i + 1;
            }
        }
    }

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return account Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address account) {
        // Return a default owner of a special case
        if (tokenId == NON_DEPLOYED_SERVICE_ID) {
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
