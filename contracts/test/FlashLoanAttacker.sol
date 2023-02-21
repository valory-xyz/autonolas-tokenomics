// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/ITokenomics.sol";
import "../interfaces/ITreasury.sol";

/// @title FlashLoanAttacker - Smart contract to simulate the flash loan attack to get instant top-ups
contract FlashLoanAttacker {
    
    constructor() {}

    /// @dev Simulate a flash loan attack via donation and checkpoint.
    /// @param tokenomics Tokenomics address.
    /// @param treasury Treasury address.
    /// @param serviceId Service Id.
    /// @param success True if the attack is successful.
    function flashLoanAttackTokenomics(address tokenomics, address treasury, uint256 serviceId)
        external payable returns (bool success)
    {
        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = serviceId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = msg.value;

        // Donate to services
        ITreasury(treasury).depositServiceDonationsETH{value: msg.value}(serviceIds, amounts);

        // Call the checkpoint
        ITokenomics(tokenomics).checkpoint();

        success = true;
    }
}