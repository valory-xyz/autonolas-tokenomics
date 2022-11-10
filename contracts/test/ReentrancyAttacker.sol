// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

    /// @dev Claims rewards for a staker address.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function claimStakingIncentives() external returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint32[] memory serviceIds, uint96[] memory amounts) external payable;
}

contract ReentrancyAttacker {
    bool public attackMode = true;
    bool public badAction;
    bool public attackOnClaimOwnerIncentives;
    bool public attackOnClaimStakingIncentives;
    bool public attackOnDepositETHFromServices;

    address dispenser;
    address treasury;

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
        } else if (attackOnClaimStakingIncentives) {
            ITokenomics(dispenser).claimStakingIncentives();
        } else if (attackOnDepositETHFromServices) {
            // If this condition is entered, the reentrancy is possible
            attackOnDepositETHFromServices = false;
        } else if (attackMode) {
            // Just reject the payment without the attack
            revert();
        }
        attackOnClaimOwnerIncentives = false;
        attackOnClaimStakingIncentives = false;
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

    /// @dev Lets the attacker call back its contract to get back to the claimStakingIncentives() function.
    function badClaimStakingIncentives(bool attack) external returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnClaimStakingIncentives = true;
        }
        return ITokenomics(dispenser).claimStakingIncentives();
    }

    /// @dev Lets the attacker call back its contract to get back to the depositETHFromServices() function.
    function badDepositETHFromServices(uint32[] memory serviceIds, uint96[] memory amounts) external payable
    {
        attackOnDepositETHFromServices = true;
        ITokenomics(treasury).depositETHFromServices{value: msg.value}(serviceIds, amounts);
    }

    /// @dev Simulates a failure for the treasury function.
    function allocateRewards(uint96, uint96, uint96) external pure returns (bool success) {
        success = false;
    }
}