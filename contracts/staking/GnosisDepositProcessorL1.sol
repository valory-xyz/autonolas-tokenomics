// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultDepositProcessorL1.sol";
import "../interfaces/IToken.sol";

interface IBridge {
    //function relayTokens(address token, address receiver, uint256 value) external;
    //function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external;

    // Contract: Omnibridge Multi-Token Mediator Proxy
    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/components/common/TokensRelayer.sol#L80
    // Flattened: https://vscode.blockscan.com/gnosis/0x2dbdcc6cad1a5a11fd6337244407bc06162aaf92
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
    function relayTokensAndCall(address token, address receiver, uint256 amount, bytes memory payload) external;

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    function messageSender() external returns (address);
}

contract GnosisDepositProcessorL1 is DefaultDepositProcessorL1 {
    // processMessageFromForeign selector (Gnosis chain)
    //bytes4 public constant PROCESS_MESSAGE_FROM_FOREIGN = bytes4(keccak256(bytes("processMessageFromForeign(bytes)")));

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId
    ) DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId) {}

    // TODO Where does the unspent gas go?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory,
        uint256 transferAmount
    ) internal override {
        // TODO Check for the transferAmount > 0
        // Deposit OLAS
        // Approve tokens for the bridge contract
        IToken(olas).approve(l1TokenRelayer, transferAmount);

        // Transfer OLAS to the staking dispenser contract across the bridge
        //IBridge(l1TokenRelayer).relayTokens(olas, l2TargetDispenser, transferAmount);

        // Assemble AMB data payload
        //bytes memory data = abi.encode(PROCESS_MESSAGE_FROM_FOREIGN, targets, stakingAmounts);

        // Extract gas limit from the payload
        // uint256 gasLimit = abi.decode(payload, (uint256));
        // Send message to L2
        //IBridge(l1MessageRelayer).requireToPassMessage(l2TargetDispenser, data, MESSAGE_GAS_LIMIT);

        // Inspired by: https://gnosisscan.io/address/0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d#writeProxyContract#F16
        bytes memory data = abi.encode(targets, stakingAmounts);
        IBridge(l1MessageRelayer).relayTokensAndCall(olas, l2TargetDispenser, transferAmount, data);

        emit MessageSent(0, targets, stakingAmounts, transferAmount);
    }

    /// @dev Processes a message received from the AMB Contract Proxy (Foreign) contract.
    /// @param data Bytes message sent from the AMB Contract Proxy (Foreign) contract.
    function processMessageFromHome(bytes memory data) external {
        emit MessageReceived(l2TargetDispenser, l2TargetChainId, data);

        // Get L2 dispenser address
        address l2Dispenser = IBridge(l1MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, l2Dispenser, data);
    }
}