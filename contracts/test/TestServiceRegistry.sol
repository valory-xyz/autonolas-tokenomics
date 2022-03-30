// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "../ServiceRegistry.sol";
import "../interfaces/IMultisig.sol";

contract TestServiceRegistry is ServiceRegistry {
    uint256 private _controlValue;

    constructor(string memory _name, string memory _symbol, address _agentRegistry)
        ServiceRegistry(_name, _symbol, _agentRegistry) {}

    // Create a safe contract with the parameters passed and check it via GnosisSafeL2
    function createCheckSafe(
        address[] memory owners,
        uint256 threshold,
        address multisigMaster,
        bytes memory data
    ) public
    {
        // Craete a safe multisig
        address multisig = IMultisig(multisigMaster).create(owners, threshold, data);
        address payable gAddress = payable(address(multisig));

        // Check the validity of safe
        GnosisSafeL2 gSafe = GnosisSafeL2(gAddress);
        require(gSafe.getThreshold() == threshold, "Threshold does not match");
        address[] memory gSafeInstances = gSafe.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            require(gSafeInstances[i] == owners[i], "Owners are wrong");
        }
    }

    // Function to test the governance execution
    function executeByGovernor(uint256 newValue) external onlyManager {
        _controlValue = newValue;
    }

    // Getter for a controlled value
    function getControlValue() public view returns (uint256) {
        return _controlValue;
    }
}
