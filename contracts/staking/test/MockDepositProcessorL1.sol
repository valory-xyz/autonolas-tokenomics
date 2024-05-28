// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultDepositProcessorL1, IToken} from "../DefaultDepositProcessorL1.sol";

contract MockDepositProcessorL1 is DefaultDepositProcessorL1 {
    address public constant MOCK_ADDRESS = address(1);

    /// @dev MockDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    constructor(
        address _olas,
        address _l1Dispenser
    ) DefaultDepositProcessorL1(_olas, _l1Dispenser, MOCK_ADDRESS, MOCK_ADDRESS, 1) {}

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory,
        uint256 transferAmount
    ) internal override returns (uint256 sequence) {

        bytes memory data;

        // Transfer OLAS together with message, or just a message
        if (transferAmount > 0) {
            // Approve tokens for the bridge contract
            IToken(olas).approve(l1TokenRelayer, transferAmount);

            data = abi.encode(targets, stakingIncentives);
        } else {
            // Assemble AMB data payload
            data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives));
        }

        sequence = stakingBatchNonce;
        emit MessagePosted(sequence, targets, stakingIncentives, transferAmount);
    }

    /// @dev Process message received from L2.
    /// @param data Bytes message data sent from L2.
    function receiveMessage(bytes memory data) external {
        // Process the data
        _receiveMessage(MOCK_ADDRESS, MOCK_ADDRESS, data);
    }
}