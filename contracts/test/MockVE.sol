// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @dev Mocking contract of voting escrow.
contract MockVE {
    uint256 public balance = 50 ether;
    uint256 public supply = 100 ether;
    uint256 public weightedBalance = 10_000 ether;
    mapping(address => uint256) public accountWeightedBalances;

    /// @dev Simulates a lock for the specified account.
    function createLock(address account) external {
        accountWeightedBalances[account] = weightedBalance;
    }

    /// @dev Gets the account balance at a specific block number.
    function balanceOfAt(address, uint256) external view returns (uint256){
        return balance;
    }

    /// @dev Gets total token supply at a specific block number.
    function totalSupplyAt(uint256) external view returns (uint256) {
        return supply;
    }

    /// @dev Gets weighted account balance.
    function getVotes(address account) external view returns (uint256) {
        return accountWeightedBalances[account];
    }

    /// @dev Sets the new balance.
    function setBalance(uint256 newBalance) external {
        balance = newBalance;
    }

    /// @dev Sets the new total supply.
    function setSupply(uint256 newSupply) external {
        supply = newSupply;
    }

    /// @dev Sets the new weighted balance.
    function setWeightedBalance(uint256 newWeightedBalance) external {
        weightedBalance = newWeightedBalance;
    }
}
