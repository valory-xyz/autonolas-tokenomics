// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DefaultTargetProcessorL1} from "./DefaultTargetProcessorL1.sol";
import {FxBaseRootTunnel} from "fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";
import "../interfaces/IToken.sol";

interface IBridge {
    // Source: https://github.com/maticnetwork/pos-portal/blob/master/flat/RootChainManager.sol#L2173
    /**
     * @notice Move tokens from root to child chain
     * @dev This mechanism supports arbitrary tokens as long as its predicate has been registered and the token is mapped
     * @param user address of account that should receive this deposit on child chain
     * @param rootToken address of token that is being deposited
     * @param depositData bytes data that is sent to predicate and child token contracts to handle deposit
     */
    function depositFor(address user, address rootToken, bytes calldata depositData) external;
}

contract PolygonTargetProcessorL1 is DefaultTargetProcessorL1, FxBaseRootTunnel {
    // _checkpointManager: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#prerequisites
    // _l1TokenRelayer is RootChainManagerProxy (0xA0c68C638235ee32657e8f720a23ceC1bFc77C77)
    // _l1MessageRelayer is fxRoot
    // _predicate is Predicate (0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf): https://github.com/maticnetwork/pos-portal/blob/master/flat/ERC20Predicate.sol

    address public immutable predicate;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _checkpointManager,
        address _predicate
    )
        DefaultTargetProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
        FxBaseRootTunnel(_checkpointManager, _l1MessageRelayer)
    {
        if (_checkpointManager == address(0) || _predicate == address(0)) {
            revert();
        }

        predicate = _predicate;
    }

    // TODO Where does the unspent gas go?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory,
        uint256 transferAmount
    ) internal override {
        // Check for the transferAmount > 0
        if (transferAmount > 0) {
            // Deposit OLAS
            // Approve tokens for the predicate bridge contract
            // Source: https://github.com/maticnetwork/pos-portal/blob/5fbd35ba9cdc8a07bf32d81d6d1f4ce745feabd6/flat/RootChainManager.sol#L2218
            IToken(olas).approve(predicate, transferAmount);

            // Transfer OLAS to the staking dispenser contract across the bridge
            IBridge(l1TokenRelayer).depositFor(l2TargetDispenser, olas, abi.encode(transferAmount));
        }

        // Assemble data payload
        bytes memory data = abi.encode(targets, stakingAmounts);

        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/FxRoot.sol#L29
        // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#root-tunnel-contract
        // Send message to L2
        _sendMessageToChild(data);

        emit MessageSent(0, targets, stakingAmounts, transferAmount);
    }

    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseRootTunnel.sol#L175
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#root-tunnel-contract
    /**
     * @notice Process message received from Child Tunnel
     * @dev function needs to be implemented to handle message as per requirement
     * This is called by receiveMessage function.
     * Since it is called via a system call, any event will not be emitted during its execution.
     * @param data bytes message that was sent from Child Tunnel
     */
    function _processMessageFromChild(bytes memory data) internal override {
        emit MessageReceived(l2TargetDispenser, l2TargetChainId, data);

        // Process the data
        _receiveMessage(data);
    }
}