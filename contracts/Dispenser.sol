// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./GenericTokenomics.sol";
import "./interfaces/ITokenomics.sol";
import "./interfaces/ITreasury.sol";

/// @title Dispenser - Smart contract for incentives
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Dispenser is GenericTokenomics {
    event ReceivedETH(address indexed sender, uint256 amount);

    // Mapping account => last incentive block for staking
    mapping(address => uint256) public mapLastRewardEpochs;

    /// @dev Dispenser constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    constructor(address _olas, address _tokenomics, address _treasury)
        GenericTokenomics(_olas, _tokenomics, _treasury, SENTINEL_ADDRESS, address(this), TokenomicsRole.Dispenser)
    {
    }

    /// @dev Claims incentives for the owner of components / agents.
    /// @notice `msg.sender` must be the owner of components / agents they are passing, otherwise the function will revert.
    /// @notice If not all `unitIds` belonging to `msg.sender` were provided, they will be untouched and keep accumulating.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success True if the claim is successful and has at least one non-zero incentive.
    function claimOwnerIncentives(uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp, bool success)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Calculate incentives
        (reward, topUp) = ITokenomics(tokenomics).accountOwnerIncentives(msg.sender, unitTypes, unitIds);
        // Request treasury to transfer funds to msg.sender if reward > 0 or topUp > 0
        if ((reward + topUp) > 0) {
            success = ITreasury(treasury).withdrawToAccount(msg.sender, reward, topUp);
        }

        _locked = 1;
    }

    /// @dev Claims incentives for a staker address.
    /// @return reward Reward amount in ETH.
    /// @return topUp Top-up amount in OLAS.
    /// @return success True if the claim is successful and has at least one non-zero incentive.
    function claimStakingIncentives() external returns (uint256 reward, uint256 topUp, bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Starting epoch number where the last time incentives were not yet claimed
        uint256 startEpochNumber = mapLastRewardEpochs[msg.sender];
        uint256 endEpochNumber;
        // Get the reward and epoch number up to which the reward was calculated
        (reward, topUp, endEpochNumber) = ITokenomics(tokenomics).getStakingIncentives(msg.sender, startEpochNumber);
        // Update the latest epoch number from which reward will be calculated the next time
        mapLastRewardEpochs[msg.sender] = endEpochNumber;

        // Request treasury to transfer funds to msg.sender if reward > 0 or topUp > 0
        if ((reward + topUp) > 0) {
            success = ITreasury(treasury).withdrawToAccount(msg.sender, reward, topUp);
        }

        _locked = 1;
    }
}
