// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultDepositProcessorL1, IToken} from "./DefaultDepositProcessorL1.sol";
import {FxBaseRootTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";

interface IBridge {
    // Source: https://github.com/maticnetwork/pos-portal/blob/master/flat/RootChainManager.sol#L2173
    // List of contracts: https://contracts.decentraland.org/links
    /// @notice Move tokens from root to child chain
    /// @dev This mechanism supports arbitrary tokens as long as its predicate has been registered and the token is mapped
    /// @param user address of account that should receive this deposit on child chain
    /// @param rootToken address of token that is being deposited
    /// @param depositData bytes data that is sent to predicate and child token contracts to handle deposit
    function depositFor(address user, address rootToken, bytes calldata depositData) external;
}

/// @title PolygonDepositProcessorL1 - Smart contract for sending tokens and data via Polygon bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract PolygonDepositProcessorL1 is DefaultDepositProcessorL1, FxBaseRootTunnel {
    event FxChildTunnelUpdated(address indexed fxChildTunnel);

    // ERC20 Predicate contract address
    address public immutable predicate;

    /// @dev PolygonDepositProcessorL1 constructor.
    /// @param _olas OLAS token address on L1.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address (RootChainManagerProxy).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (fxRoot).
    /// @param _l2TargetChainId L2 target chain Id.
    /// @param _checkpointManager Checkpoint manager contract for verifying L2 to L1 data (RootChainManagerProxy).
    /// @param _predicate ERC20 predicate contract to lock tokens on L1 before sending to L2.
    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _checkpointManager,
        address _predicate
    )
        DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
        FxBaseRootTunnel(_checkpointManager, _l1MessageRelayer)
    {
        // Check for zero addresses
        if (_checkpointManager == address(0) || _predicate == address(0)) {
            revert ZeroAddress();
        }

        predicate = _predicate;
    }

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory,
        uint256 transferAmount
    ) internal override returns (uint256 sequence) {
        // Check for the transferAmount > 0
        if (transferAmount > 0) {
            // Deposit OLAS
            // Approve tokens for the predicate bridge contract
            // Source: https://github.com/maticnetwork/pos-portal/blob/5fbd35ba9cdc8a07bf32d81d6d1f4ce745feabd6/flat/RootChainManager.sol#L2218
            IToken(olas).approve(predicate, transferAmount);

            // Transfer OLAS to L2 target dispenser contract across the bridge
            IBridge(l1TokenRelayer).depositFor(l2TargetDispenser, olas, abi.encode(transferAmount));
        }

        // Assemble data payload
        bytes memory data = abi.encode(targets, stakingIncentives);

        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/FxRoot.sol#L29
        // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#root-tunnel-contract
        // Send message to L2
        _sendMessageToChild(data);

        // Since there is no returned message sequence, use the staking batch nonce
        sequence = stakingBatchNonce;
    }

    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseRootTunnel.sol#L175
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#root-tunnel-contract
    /// @dev Process message received from the L2 Child Tunnel. This is called by receiveMessage function.
    /// @notice All the bridge relayer and sender verifications are performed in a parent receiveMessage() function.
    /// @param data Bytes message data sent from L2.
    function _processMessageFromChild(bytes memory data) internal override {
        // Process the data
        _receiveMessage(l1MessageRelayer, l2TargetDispenser, data);
    }

    /// @dev Sets l2TargetDispenser, aka fxChildTunnel.
    /// @param l2Dispenser L2 target dispenser address.
    function setFxChildTunnel(address l2Dispenser) public override {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (l2Dispenser == address(0)) {
            revert ZeroAddress();
        }

        // Set L1 deposit processor address
        fxChildTunnel = l2Dispenser;

        emit FxChildTunnelUpdated(l2Dispenser);
    }

    /// @dev Sets L2 target dispenser address.
    /// @param l2Dispenser L2 target dispenser address.
    function setL2TargetDispenser(address l2Dispenser) external override {
        setFxChildTunnel(l2Dispenser);
        _setL2TargetDispenser(l2Dispenser);
    }
}