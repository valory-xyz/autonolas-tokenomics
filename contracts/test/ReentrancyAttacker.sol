// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ServiceRegistry interface
interface ITokenomics {
    /// @dev Claims rewards for the owner of components / agents.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success
    function claimOwnerIncentives(uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Deposits service donations in ETH.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable;
}

contract ReentrancyAttacker {
    bool public attackMode = true;
    bool public badAction;
    bool public attackOnClaimOwnerIncentives;
    bool public attackOnDepositETHFromServices;
    bool public transferStatus;

    address public dispenser;
    address public treasury;

    constructor(address _dispenser, address _treasury) {
        dispenser = _dispenser;
        treasury = _treasury;
    }
    
    /// @dev wallet
    receive() external payable {
        if (attackOnClaimOwnerIncentives) {
            uint256[] memory unitTypes = new uint256[](2);
            (unitTypes[0], unitTypes[1]) = (0, 1);
            uint256[] memory unitIds = new uint256[](2);
            (unitIds[0], unitIds[1]) = (1, 1);
            ITokenomics(dispenser).claimOwnerIncentives(unitTypes, unitIds);
        } else if (attackOnDepositETHFromServices) {
            // If this condition is entered, the reentrancy is possible
            attackOnDepositETHFromServices = false;
        } else if (attackMode) {
            // Just reject the payment without the attack
            revert();
        }
        attackOnClaimOwnerIncentives = false;
        badAction = true;
    }

    /// @dev Sets the attack mode.
    /// @notice If false, the receive atcs as a normal one.
    function setAttackMode(bool _attackMode) external {
        attackMode = _attackMode;
    }


    /// @dev Lets the attacker call back its contract to get back to the claimOwnerIncentives() function.
    function badClaimOwnerIncentives(bool attack, uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnClaimOwnerIncentives = true;
        }
        return ITokenomics(dispenser).claimOwnerIncentives(unitTypes, unitIds);
    }

    /// @dev Attack via a blacklisting check that calls again the Treasury depositServiceDonationsETH() function.
    function isDonatorBlacklisted(address) external returns (bool status) {
        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        ITokenomics(treasury).depositServiceDonationsETH(serviceIds, amounts);
        return false;
    }

    /// @dev Allowance simulation function.
    function allowance(address, address) external pure returns (uint256) {
        return 10_000 ether;
    }

    /// @dev Sets the ability or inability to transfer.
    function setTransfer(bool success) external {
        transferStatus = success;
    }

    /// @dev Transfer function that fails.
    function transfer(address, uint256) external view returns (bool) {
        return transferStatus;
    }

    /// @dev Transfer from function that fails.
    function transferFrom(address, address, uint256) external view returns (bool) {
        return transferStatus;
    }
}