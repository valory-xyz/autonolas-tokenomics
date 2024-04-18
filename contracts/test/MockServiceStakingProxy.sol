// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Mocking the service staking proxy.
contract MockServiceStakingProxy {
    uint256 public balance;

    function deposit(uint256 amount) external {
        balance += amount;
    }
}
