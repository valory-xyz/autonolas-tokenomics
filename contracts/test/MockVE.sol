// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Mocking contract of voting escrow.
contract MockVE {
    address[] public accounts;
    uint256 balance = 50 ether;
    uint256 supply = 100 ether;
    uint256 weightedBalance = 10_000 ether;

    /// @dev Simulates a lock for the specified account.
    function createLock(address account) external {
        accounts.push(account);
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
    function getVotes(address) external view returns (uint256) {
        return weightedBalance;
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
