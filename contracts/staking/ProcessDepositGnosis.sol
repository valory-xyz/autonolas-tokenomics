// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    function _depositTokens(bytes memory payload, uint256 transferAmount) internal {
        // Approve tokens for the bridge contract
        IOLAS(olas).approve(omniBridge, transferAmount);

        // Transfer OLAS to the staking dispenser contract across the bridge
        IOmniBridge(omniBridge).relayTokens(olas, l2TargetDispenser, transferAmount);
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function deposit(address target, uint256 stakingAmount, bytes memory payload, uint256 transferAmount) external payable {
        // Deposit OLAS
        _depositTokens(payload, transferAmount);

        // Send a message to the staking dispenser contract to reflect the transferred OLAS amount
        uint256 transferNonce = stakingContractNonces[target];

        // TODO Send message via a native bridge
        address[] memory targets = new address[](1);
        targets[i] = target;
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[i] = stakingAmount;
        //_sendMessage(targets, stakingAmounts, transferNonce);

        // TODO: Make sure the sync is always performed on L2 for the case if the same staking contract is used
        // twice or more in the same tx: maybe use block.timestamp
        stakingContractNonces[target] = transferNonce + 1;
    }

    function depositBatch(
        address[] memory targets,
        uint256[] memory stakingAmount,
        bytes[] memory payloads,
        uint256 transferAmount
    ) external payable {
        // Deposit OLAS
        _depositTokens(payload, transferAmount);

        // Send a message to the staking dispenser contract to reflect the transferred OLAS amount
        uint256 transferNonce = stakingContractNonces[target];
        // TODO Send message via a native bridge
        //_sendMessage(targets, stakingAmounts, transferNonce);

        // TODO: Make sure the sync is always performed on L2 for the case if the same staking contract is used
        // twice or more in the same tx: maybe use block.timestamp
        stakingContractNonces[target] = transferNonce + 1;
    }
}