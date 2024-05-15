// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBridgeErrors {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Only `owner` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param owner Required sender address as an owner.
    error OwnerOnly(address sender, address owner);

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Zero value when it has to be different from zero.
    error ZeroValue();

    /// @dev Provided incorrect data length.
    /// @param expected Expected minimum data length.
    /// @param provided Provided data length.
    error IncorrectDataLength(uint256 expected, uint256 provided);

    /// @dev Received lower value than the expected one.
    /// @param provided Provided value is lower.
    /// @param expected Expected value.
    error LowerThan(uint256 provided, uint256 expected);

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Target bridge relayer is incorrect.
    /// @param provided Provided relayer address.
    /// @param expected Expected relayer address.
    error TargetRelayerOnly(address provided, address expected);

    /// @dev Message sender from another chain is incorrect.
    /// @param provided Provided message sender address.
    /// @param expected Expected message sender address.
    error WrongMessageSender(address provided, address expected);

    /// @dev Chain Id originating the call is incorrect.
    /// @param provided Provided chain Id.
    /// @param expected Expected chain Id.
    error WrongChainId(uint256 provided, uint256 expected);

    /// @dev Target and its corresponding amount are not found in the queue.
    /// @param target Target address.
    /// @param amount Token amount.
    /// @param batchNonce Reference batch nonce.
    error TargetAmountNotQueued(address target, uint256 amount, uint256 batchNonce);

    /// @dev Insufficient token balance.
    /// @param provided Provided balance.
    /// @param expected Expected available amount.
    error InsufficientBalance(uint256 provided, uint256 expected);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param amount Token amount.
    error TransferFailed(address token, address from, address to, uint256 amount);

    /// @dev Delivery hash has been already processed.
    /// @param deliveryHash Delivery hash.
    error AlreadyDelivered(bytes32 deliveryHash);

    /// @dev Wrong amount received / provided.
    /// @param provided Provided amount.
    /// @param expected Expected amount.
    error WrongAmount(uint256 provided, uint256 expected);

    /// @dev Provided token address is incorrect.
    /// @param provided Provided token address.
    /// @param expected Expected token address.
    error WrongTokenAddress(address provided, address expected);

    /// @dev The contract is paused.
    error Paused();

    // Reentrancy guard
    error ReentrancyGuard();
}


// File contracts/staking/DefaultDepositProcessorL1.sol
interface IDispenser {
    function syncWithheldAmount(uint256 chainId, uint256 amount) external;
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
    event MessagePosted(uint256 indexed sequence, address[] targets, uint256[] stakingAmounts, uint256 transferAmount);
    event MessageReceived(address indexed l1Relayer, uint256 indexed chainId, bytes data);

    // receiveMessage selector to be executed on L2
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // Token transfer gas limit for L2
    // This is safe as the value is approximately 3 times bigger than observed ones on numerous chains
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

    /// @dev DefaultDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
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
    /// @notice Message is sent to the target dispenser contract to reflect transferred OLAS and staking amounts.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridging relayer.
    /// @param transferAmount Actual total OLAS amount to be transferred.
    /// @return sequence Unique message sequence (if applicable) or the batch number.
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal virtual returns (uint256 sequence);

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

        // Extract the amount of OLAS to sync
        (uint256 amount) = abi.decode(data, (uint256));

        // Sync withheld tokens in the dispenser contract
        IDispenser(l1Dispenser).syncWithheldAmount(l2TargetChainId, amount);
    }

    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingAmount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(
        address target,
        uint256 stakingAmount,
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
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[0] = stakingAmount;

        // Send the message to L2
        uint256 sequence = _sendMessage(targets, stakingAmounts, bridgePayload, transferAmount);

        // Increase the staking batch nonce
        stakingBatchNonce++;

        emit MessagePosted(sequence, targets, stakingAmounts, transferAmount);
    }


    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) external virtual payable {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != l1Dispenser) {
            revert ManagerOnly(l1Dispenser, msg.sender);
        }

        // Send the message to L2
        uint256 sequence = _sendMessage(targets, stakingAmounts, bridgePayload, transferAmount);

        // Increase the staking batch nonce
        stakingBatchNonce++;

        emit MessagePosted(sequence, targets, stakingAmounts, transferAmount);
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


// File contracts/staking/OptimismDepositProcessorL1.sol
interface IBridge {
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/L1/L1StandardBridge.sol#L188
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/standard-bridge#architecture
    /// @custom:legacy
    /// @notice Deposits some amount of ERC20 tokens into a target account on L2.
    ///
    /// @param _l1Token     Address of the L1 token being deposited.
    /// @param _l2Token     Address of the corresponding token on L2.
    /// @param _to          Address of the recipient on L2.
    /// @param _amount      Amount of the ERC20 to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2. Data supplied here will not be used to
    ///                     execute any code on L2 and is only emitted as extra data for the
    ///                     convenience of off-chain tooling.
    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L259
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging
    /// @notice Sends a message to some target address on the other chain. Note that if the call
    ///         always reverts, then the message will be unrelayable, and any ETH sent will be
    ///         permanently locked. The same will occur if the target on the other chain is
    ///         considered unsafe (see the _isUnsafeTarget() function).
    ///
    /// @param _target      Target contract or wallet address.
    /// @param _message     Message to trigger the target address with.
    /// @param _minGasLimit Minimum gas limit that the message can be executed with.
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _minGasLimit
    ) external payable;

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L422
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#accessing-msgsender
    /// @notice Retrieves the address of the contract or wallet that initiated the currently
    ///         executing message on the other chain. Will throw an error if there is no message
    ///         currently being executed. Allows the recipient of a call to see who triggered it.
    ///
    /// @return Address of the sender of the currently executing message on the other chain.
    function xDomainMessageSender() external view returns (address);
}

/// @title OptimismDepositProcessorL1 - Smart contract for sending tokens and data via Optimism bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract OptimismDepositProcessorL1 is DefaultDepositProcessorL1 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 64;
    // OLAS address on L2
    address public immutable olasL2;

    // https://docs.optimism.io/chain/addresses
    // _l1TokenRelayer is L1StandardBridgeProxy
    // _l1MessageRelayer is L1CrossDomainMessengerProxy

    /// @dev OptimismDepositProcessorL1 constructor.
    /// @param _olas OLAS token address on L1.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer bridging contract address (L1StandardBridgeProxy).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (L1CrossDomainMessengerProxy).
    /// @param _l2TargetChainId L2 target chain Id.
    /// @param _olasL2 OLAS token address on L2.
    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _olasL2
    )
        DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
    {
        // Check for zero address
        if (_olasL2 == address(0)) {
            revert ZeroAddress();
        }

        olasL2 = _olasL2;
    }

    /// @inheritdoc DefaultDepositProcessorL1
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal override returns (uint256 sequence) {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Check for the transferAmount > 0
        if (transferAmount > 0) {
            // Deposit OLAS
            // Approve tokens for the predicate bridge contract
            // Source: https://github.com/maticnetwork/pos-portal/blob/5fbd35ba9cdc8a07bf32d81d6d1f4ce745feabd6/flat/RootChainManager.sol#L2218
            IToken(olas).approve(l1TokenRelayer, transferAmount);

            // Transfer OLAS to L2 staking dispenser contract across the bridge
            IBridge(l1TokenRelayer).depositERC20To(olas, olasL2, l2TargetDispenser, transferAmount,
                uint32(TOKEN_GAS_LIMIT), "");
        }

        // Decode cost related data
        (uint256 cost, uint256 gasLimitMessage) = abi.decode(bridgePayload, (uint256, uint256));
        // Check for zero values
        if (cost == 0 || gasLimitMessage == 0) {
            revert ZeroValue();
        }

        // Check that provided msg.value is enough to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Assemble data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingAmounts));
        
        // Reference: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l1-to-l2-transactions-1
        // Send message to L2
        IBridge(l1MessageRelayer).sendMessage{value: cost}(l2TargetDispenser, data, uint32(gasLimitMessage));

        // Since there is no returned message sequence, use the staking batch nonce
        sequence = stakingBatchNonce;
    }

    /// @dev Process message received from L2.
    /// @param data Bytes message data sent from L2.
    function receiveMessage(bytes memory data) external payable {
        // Get L2 dispenser address
        address l2Dispenser = IBridge(l1MessageRelayer).xDomainMessageSender();

        // Process the data
        _receiveMessage(msg.sender, l2Dispenser, data);
    }
}
