// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./WormholeMessagePassing.sol";

interface IOmniBridge {
    function relayTokens(address token, address receiver, uint256 value) external;
}

contract ProcessDepositArbitrum is WormholeMessagePassing {
    address public immutable olas;
    address public immutable omniBridge;

    // TODO: nonce must start from 1 in order to be identified on L2 side (otherwise 0 is both nonce and not found)
    mapping(address => uint256) public stakingContractNonces;

    constructor(
        address _olas,
        address _omniBridge,
        address _l2TargetDispenser,
        address _wormholeRelayer,
        uint256 _wormholeTargetChain
    ) WormholeMessagePassing(_l2TargetDispenser, _wormholeRelayer, _wormholeTargetChain) {
        if (_olas == address(0) || _omniBridge == address(0)) {
            revert();
        }

        olas = _olas;
        omniBridge = _omniBridge;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function deposit(address target, uint256 amount, bytes memory payload) payable {
        // Approve tokens for the bridge contract
        IOLAS(olas).approve(omniBridge, amount);

        // Transfer OLAS to the staking dispenser contract across the bridge
        IOmniBridge(omniBridge).relayTokens(olas, l2TargetDispenser, amount);

        // Send a message to the staking dispenser contract to reflect the transferred OLAS amount
        uint256 transferNonce = stakingContractNonces[target];
        _sendMessage(target, amount, transferNonce);

        // TODO: Make sure the sync is always performed on L2 for the case if the same staking contract is used
        // twice or more in the same tx: maybe use block.timestamp
        stakingContractNonces[target] = transferNonce + 1;
    }
}