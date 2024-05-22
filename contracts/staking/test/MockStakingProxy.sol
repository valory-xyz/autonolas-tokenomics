// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IToken {
    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Mocking the service staking proxy.
contract MockStakingProxy {
    address public immutable token;
    uint256 public balance;

    constructor(address _token) {
        token = _token;
    }

    function deposit(uint256 amount) external {
        IToken(token).transferFrom(msg.sender, address(this), amount);
        balance += amount;
    }
}
