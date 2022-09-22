// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "hardhat/console.sol";

// ServiceRegistry interface
interface ITokenomics {
    /// @dev Withdraws rewards for owners of components / agents.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success
    function withdrawOwnerRewards() external returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Withdraws rewards for a staker.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    function withdrawStakingRewards() external returns (uint256 reward, uint256 topUp, bool success);

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external;
}

contract ReentrancyAttacker {
    bool public badAction;
    bool public attackOnWithdrawOwnerRewards;
    bool public attackOnWithdrawStakingRewards;
    bool public attackOnDepositETHFromServices;

    address dispenser;
    address treasury;

    constructor(address _dispenser, address _treasury) {
        dispenser = _dispenser;
        treasury = _treasury;
    }
    
    /// @dev wallet
    receive() external payable {
        if (attackOnWithdrawOwnerRewards) {
            console.log("Hello, going to reenter");
            ITokenomics(dispenser).withdrawOwnerRewards();
            console.log("After the attack");
        } else if (attackOnWithdrawStakingRewards) {
            ITokenomics(dispenser).withdrawStakingRewards();
        } else if (attackOnDepositETHFromServices) {
            ITokenomics(treasury).depositETHFromServices(new uint256[](0), new uint256[](0));
        } else {
            // Just reject the payment
            revert();
        }
        console.log("After attack 2");
        attackOnWithdrawOwnerRewards = false;
        attackOnWithdrawStakingRewards = false;
        attackOnDepositETHFromServices = false;
        badAction = true;
    }

    /// @dev Lets the attacker call back its contract to get back to the withdrawOwnerRewards() function.
    function badWithdrawOwnerRewards(bool attack) external returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnWithdrawOwnerRewards = true;
        }
        return ITokenomics(dispenser).withdrawOwnerRewards();
    }

    /// @dev Lets the attacker call back its contract to get back to the withdrawStakingRewards() function.
    function badWithdrawStakingRewards(bool attack) external returns (uint256 reward, uint256 topUp, bool success)
    {
        if (attack) {
            attackOnWithdrawStakingRewards = true;
        }
        return ITokenomics(dispenser).withdrawOwnerRewards();
    }

    /// @dev Lets the attacker call back its contract to get back to the depositETHFromServices() function.
    function badDepositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external payable
    {
        attackOnDepositETHFromServices = true;
        return ITokenomics(treasury).depositETHFromServices(serviceIds, amounts);
    }
}