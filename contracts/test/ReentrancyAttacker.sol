// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// ServiceRegistry interface
interface ITokenomics {
    /// @dev Withdraws rewards for owners of components / agents.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success
    function claimOwnerRewards() external returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function claimStakingRewards() external returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint32[] memory serviceIds, uint96[] memory amounts) external payable;
}

contract ReentrancyAttacker {
    bool public attackMode = true;
    bool public badAction;
    bool public attackOnClaimOwnerRewards;
    bool public attackOnClaimStakingRewards;
    bool public attackOnDepositETHFromServices;

    address dispenser;
    address treasury;

    constructor(address _dispenser, address _treasury) {
        dispenser = _dispenser;
        treasury = _treasury;
    }
    
    /// @dev wallet
    receive() external payable {
        if (attackOnClaimOwnerRewards) {
            ITokenomics(dispenser).claimOwnerRewards();
        } else if (attackOnClaimStakingRewards) {
            ITokenomics(dispenser).claimStakingRewards();
        } else if (attackOnDepositETHFromServices) {
            // If this condition is entered, the reentrancy is possible
            attackOnDepositETHFromServices = false;
        } else if (attackMode) {
            // Just reject the payment without the attack
            revert();
        }
        attackOnClaimOwnerRewards = false;
        attackOnClaimStakingRewards = false;
        badAction = true;
    }

    /// @dev Sets the attack mode.
    /// @notice If false, the receive atcs as a normal one.
    function setAttackMode(bool _attackMode) external {
        attackMode = _attackMode;
    }


    /// @dev Lets the attacker call back its contract to get back to the claimOwnerRewards() function.
    function badClaimOwnerRewards(bool attack) external returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnClaimOwnerRewards = true;
        }
        return ITokenomics(dispenser).claimOwnerRewards();
    }

    /// @dev Lets the attacker call back its contract to get back to the claimStakingRewards() function.
    function badClaimStakingRewards(bool attack) external returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnClaimStakingRewards = true;
        }
        return ITokenomics(dispenser).claimStakingRewards();
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