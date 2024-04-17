// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IToken{
    function mint(address account, uint256 amount) external;
}

interface IDepositProcessor {
    function sendMessage(address target, uint256 stakingAmount, bytes memory bridgePayload,
        uint256 transferAmount) external;
}

/// @title MockServiceStakingDispenser - Smart contract for mocking the service staking part of a Dispenser contract
contract MockServiceStakingDispenser {
    address public immutable token;

    constructor(address _token) {
        token = _token;
    }

    /// @dev Mints a specified amount and sends to staking dispenser on L2.
    /// @param stakingTarget Service staking target address on L2.
    /// @param stakingAmount Token amount to stake.
    /// @param depositProcessor Deposit processor bridge mediator.
    /// @param bridgePayload Bridge payload, if necessary.
    function mintAndSend(
        address stakingTarget,
        uint256 stakingAmount,
        address depositProcessor,
        bytes memory bridgePayload
    ) external {
        IToken(token).mint(depositProcessor, stakingAmount);
        IDepositProcessor(depositProcessor).sendMessage(stakingTarget, stakingAmount, bridgePayload, stakingAmount);
    }
}