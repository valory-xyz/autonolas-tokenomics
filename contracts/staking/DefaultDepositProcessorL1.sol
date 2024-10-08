// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IBridgeErrors} from "../interfaces/IBridgeErrors.sol";

interface IDispenser {
    function syncWithheldAmount(uint256 chainId, uint256 amount, bytes32 batchHash) external;
}

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title DefaultDepositProcessorL1 - Smart contract for sending tokens and data via arbitrary bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract DefaultDepositProcessorL1 is IBridgeErrors {
    event MessagePosted(uint256 indexed sequence, address[] targets, uint256[] stakingIncentives,
        uint256 transferAmount, bytes32 indexed batchHash);
    event MessageReceived(address indexed l1Relayer, uint256 indexed chainId, bytes data);
    event L2TargetDispenserUpdated(address indexed l2TargetDispenser);
    event LeftoversRefunded(address indexed sender, uint256 leftovers);

    // receiveMessage selector to be executed on L2
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // Token transfer gas limit for L2
    // This is safe as the value is practically bigger than observed ones on numerous chains
    uint256 public constant TOKEN_GAS_LIMIT = 300_000;
    // Message transfer gas limit for L2
    uint256 public constant MESSAGE_GAS_LIMIT = 2_000_000;
    // OLAS token address
    address public immutable olas;
    // L1 tokenomics dispenser address
    address public immutable l1Dispenser;
    // L1 token relayer bridging contract address
    address public immutable l1TokenRelayer;
    // L1 message relayer bridging contract address
    address public immutable l1MessageRelayer;
    // L2 target chain Id
    uint256 public immutable l2TargetChainId;
    // L2 target dispenser address, set by the deploying owner
    address public l2TargetDispenser;
    // Contract owner until the time when the l2TargetDispenser is set
    address public owner;
    // Nonce for each staking batch
    uint256 public stakingBatchNonce;

    // Processed batch hashes
    mapping(bytes32 => bool) public processedHashes;

    /// @dev DefaultDepositProcessorL1 constructor.
    /// @param _olas OLAS token address on L1.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address.
    /// @param _l1MessageRelayer L1 message relayer bridging contract address.
    /// @param _l2TargetChainId L2 target chain Id.
    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId
    ) {
        // Check for zero addresses
        if (_l1Dispenser == address(0) || _l1TokenRelayer == address(0) || _l1MessageRelayer == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_l2TargetChainId == 0) {
            revert ZeroValue();
        }

        // Check for overflow value
        if (_l2TargetChainId > MAX_CHAIN_ID) {
            revert Overflow(_l2TargetChainId, MAX_CHAIN_ID);
        }

        olas = _olas;
        l1Dispenser = _l1Dispenser;
        l1TokenRelayer = _l1TokenRelayer;
        l1MessageRelayer = _l1MessageRelayer;
        l2TargetChainId = _l2TargetChainId;
        owner = msg.sender;
    }

    /// @dev Sends message to the L2 side via a corresponding bridge.
    /// @notice Message is sent to the target dispenser contract to reflect transferred OLAS and staking incentives.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual total OLAS amount to be transferred.
    /// @param batchHash Unique batch hash for each message transfer.
    /// @return sequence Unique message sequence (if applicable) or the batch hash converted to number.
    /// @return leftovers ETH leftovers from unused msg.value.
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory bridgePayload,
        uint256 transferAmount,
        bytes32 batchHash
    ) internal virtual returns (uint256 sequence, uint256 leftovers);

    /// @dev Receives a message on L1 sent from L2 target dispenser side to sync withheld OLAS amount on L2.
    /// @param l1Relayer L1 source relayer.
    /// @param l2Dispenser L2 target dispenser that originated the message.
    /// @param data Message data payload sent from L2.
    function _receiveMessage(address l1Relayer, address l2Dispenser, bytes memory data) internal virtual {
        // Check L1 Relayer address to be the msg.sender, where applicable
        if (l1Relayer != l1MessageRelayer) {
            revert TargetRelayerOnly(msg.sender, l1MessageRelayer);
        }

        // Check L2 dispenser address originating the message on L2
        if (l2Dispenser != l2TargetDispenser) {
            revert WrongMessageSender(l2Dispenser, l2TargetDispenser);
        }

        emit MessageReceived(l2TargetDispenser, l2TargetChainId, data);

        // Extract the amount of OLAS to sync and a batch hash
        (uint256 amount, bytes32 batchHash) = abi.decode(data, (uint256, bytes32));

        // Check that the batch hash has not yet being processed
        // Possible scenario: bridge failed to deliver from L2 to L1, maintenance function is called by the DAO,
        // and the bridge somehow re-delivers the same message that has already been processed
        if (processedHashes[batchHash]) {
            revert AlreadyDelivered(batchHash);
        }
        processedHashes[batchHash] = true;

        // Sync withheld tokens in the dispenser contract
        IDispenser(l1Dispenser).syncWithheldAmount(l2TargetChainId, amount, batchHash);
    }

    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingIncentive Corresponding staking incentive.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(
        address target,
        uint256 stakingIncentive,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external virtual payable {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != l1Dispenser) {
            revert ManagerOnly(l1Dispenser, msg.sender);
        }

        // Construct one-element arrays from targets and amounts
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory stakingIncentives = new uint256[](1);
        stakingIncentives[0] = stakingIncentive;

        // Get the batch hash
        uint256 batchNonce = stakingBatchNonce;
        bytes32 batchHash = keccak256(abi.encode(batchNonce, block.chainid, address(this)));

        // Send the message to L2
        (uint256 sequence, uint256 leftovers) = _sendMessage(targets, stakingIncentives, bridgePayload, transferAmount,
            batchHash);

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // If the call fails, ignore to avoid the attack that would prevent this function from executing
            // solhint-disable-next-line avoid-low-level-calls
            tx.origin.call{value: leftovers}("");

            emit LeftoversRefunded(tx.origin, leftovers);
        }

        // Increase the staking batch nonce
        stakingBatchNonce = batchNonce + 1;

        emit MessagePosted(sequence, targets, stakingIncentives, transferAmount, batchHash);
    }

    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external virtual payable {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != l1Dispenser) {
            revert ManagerOnly(l1Dispenser, msg.sender);
        }

        // Get the batch hash
        uint256 batchNonce = stakingBatchNonce;
        bytes32 batchHash = keccak256(abi.encode(batchNonce, block.chainid, address(this)));

        // Send the message to L2
        (uint256 sequence, uint256 leftovers) = _sendMessage(targets, stakingIncentives, bridgePayload, transferAmount,
            batchHash);

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // If the call fails, ignore to avoid the attack that would prevent this function from executing
            // solhint-disable-next-line avoid-low-level-calls
            tx.origin.call{value: leftovers}("");
        }

        // Increase the staking batch nonce
        stakingBatchNonce = batchNonce + 1;

        emit MessagePosted(sequence, targets, stakingIncentives, transferAmount, batchHash);
    }

    /// @dev Updated the batch hash of a failed message, if applicable.
    /// @param batchHash Unique batch hash for each message transfer.
    function updateHashMaintenance(bytes32 batchHash) external {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != l1Dispenser) {
            revert ManagerOnly(l1Dispenser, msg.sender);
        }

        // Check that the batch hash has not yet being processed
        // Possible scenario: bridge failed to deliver from L2 to L1, then after some time the bridge somehow
        // re-delivers the same message, and the maintenance function is called by the DAO as well,
        // that is not needed already anymore since the message was processed naturally via a recovered bridge
        if (processedHashes[batchHash]) {
            revert AlreadyDelivered(batchHash);
        }
        processedHashes[batchHash] = true;
    }

    /// @dev Sets L2 target dispenser address and zero-s the owner.
    /// @param l2Dispenser L2 target dispenser address.
    function _setL2TargetDispenser(address l2Dispenser) internal {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(owner, msg.sender);
        }

        // The L2 target dispenser must have a non zero address
        if (l2Dispenser == address(0)) {
            revert ZeroAddress();
        }
        l2TargetDispenser = l2Dispenser;

        // Revoke the owner role making the contract ownerless
        owner = address(0);

        emit L2TargetDispenserUpdated(l2Dispenser);
    }

    /// @dev Sets L2 target dispenser address.
    /// @param l2Dispenser L2 target dispenser address.
    function setL2TargetDispenser(address l2Dispenser) external virtual {
        _setL2TargetDispenser(l2Dispenser);
    }

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @return Number of supported decimals.
    function getBridgingDecimals() external pure virtual returns (uint256) {
        return 18;
    }
}