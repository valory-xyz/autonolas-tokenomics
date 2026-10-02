// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./DefaultTargetDispenserL2.sol";

interface IBridge {
    // Contract: AMB Contract Proxy Home
    // Source: https://github.com/omni/tokenbridge-contracts/blob/908a48107919d4ab127f9af07d44d47eac91547e/contracts/upgradeable_contracts/arbitrary_message/MessageDelivery.sol#L22
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    /// @dev Requests message relay to the opposite network
    /// @param target Executor address on the other side.
    /// @param data Calldata passed to the executor on the other side.
    /// @param maxGasLimit Gas limit used on the other network for executing a message.
    /// @return Message Id.
    function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external returns (bytes32);

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#security-considerations-for-receiving-a-call
    function messageSender() external returns (address);
}

/// @dev The direct withheld-amount sync is disabled; use the request/relay split.
error UseSyncSplit();

/// @dev No withheld-amount sync has been requested.
error NothingPending();

/// @title GnosisTargetDispenserL2 - Smart contract for processing tokens and data received on Gnosis L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract GnosisTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 32;

    /// @dev GnosisTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (AMBHomeProxy).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {}

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(
        uint256 amount,
        bytes memory bridgePayload,
        bytes32 batchHash
    ) internal override returns (uint256 sequence, uint256 leftovers) {
        uint256 gasLimitMessage;

        // Check for the bridge payload length
        if (bridgePayload.length == BRIDGE_PAYLOAD_LENGTH) {
            // Decode bridge payload
            gasLimitMessage = abi.decode(bridgePayload, (uint256));

            // Check the gas limit value for the maximum recommended one
            if (gasLimitMessage > MAX_GAS_LIMIT) {
                gasLimitMessage = MAX_GAS_LIMIT;
            }
        }

        // Check the gas limit value for the minimum recommended one
        if (gasLimitMessage < MIN_GAS_LIMIT) {
            gasLimitMessage = MIN_GAS_LIMIT;
        }

        // Assemble AMB data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount, batchHash));

        // Send message to L1
        bytes32 iMsg = IBridge(l2MessageRelayer).requireToPassMessage(l1DepositProcessor, data, gasLimitMessage);
        sequence = uint256(iMsg);

        leftovers = msg.value;
    }

    /// @dev A withheld-amount sync has been requested and is awaiting a permissionless relay.
    event WithheldAmountSyncRequested(bytes bridgePayload);

    /// @dev A sync is recorded and awaiting relay.
    bool public syncPending;
    /// @dev Bridge payload recorded at request time, used by the relay.
    bytes public pendingBridgePayload;

    /// @dev Disabled: a direct send reverts when called inside an AMB delivery (the AMB rejects
    ///      requireToPassMessage while processing an inbound message). Use the request/relay split.
    function syncWithheldAmount(bytes memory) external payable override {
        revert UseSyncSplit();
    }

    /// @dev Records a withheld-amount sync request. Sends nothing, so it is safe inside an AMB delivery.
    /// @notice Arming is owner-only (governance); the matching relay is permissionless by design, so governance
    ///         or anyone can complete it as soon as the AMB is idle. A request is a standing authorization until
    ///         relayed; the owner's only levers to retract it are pause() and migrate(). The amount synced is the
    ///         withheld amount at RELAY time, not at request time — any withheld-amount correction
    ///         (updateWithheldAmountMaintenance) must therefore ship atomically with, or before, the bridged
    ///         proposal that arms this request.
    /// @param bridgePayload Payload data for the bridge relayer, used by the relay step.
    function requestWithheldAmountSync(bytes memory bridgePayload) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        pendingBridgePayload = bridgePayload;
        syncPending = true;

        emit WithheldAmountSyncRequested(bridgePayload);
    }

    /// @dev Relays a previously requested withheld-amount sync to L1. Permissionless: the amount and
    ///      destination are the contract's own, so there is nothing for a caller to influence.
    /// @notice MessagePosted carries the relayer (msg.sender), which may be any address — off-chain monitoring
    ///         must not assume it is the owner or the bridge mediator.
    function relayWithheldAmountSync() external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // A sync must have been requested
        if (!syncPending) {
            revert NothingPending();
        }

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        syncPending = false;

        // Get withheld amount
        uint256 amount = withheldAmount;

        // Get bridging decimals and normalize, matching the base sync accounting
        uint256 bridgingDecimals = getBridgingDecimals();
        uint256 normalizedAmount = amount;
        if (bridgingDecimals < 18) {
            normalizedAmount = amount / (10 ** (18 - bridgingDecimals));
            normalizedAmount *= 10 ** (18 - bridgingDecimals);
        }

        // Check the normalized withheld amount to be greater than zero
        if (normalizedAmount == 0) {
            revert ZeroValue();
        }

        // Adjust the actual withheld amount (pure amount is always >= the normalized one)
        withheldAmount = amount - normalizedAmount;

        // Get the batch hash
        uint256 batchNonce = stakingBatchNonce;
        bytes32 batchHash = keccak256(abi.encode(batchNonce, block.chainid, address(this)));

        // Send the message to sync the normalized withheld amount (outside any AMB delivery)
        (uint256 sequence, uint256 leftovers) = _sendMessage(normalizedAmount, pendingBridgePayload, batchHash);

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // If the call fails, ignore to avoid the attack that would prevent this function from executing
            // solhint-disable-next-line avoid-low-level-calls
            msg.sender.call{value: leftovers}("");

            emit LeftoversRefunded(msg.sender, leftovers);
        }

        stakingBatchNonce = batchNonce + 1;

        emit MessagePosted(sequence, msg.sender, normalizedAmount, batchHash);

        _locked = 1;
    }

    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
    /// @param data Bytes message data sent from the AMB Contract Proxy (Home) contract.
    function receiveMessage(bytes memory data) external {
        // Get L1 deposit processor address
        address processor = IBridge(l2MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, processor, data);
    }
}
