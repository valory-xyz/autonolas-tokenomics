// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

    /// @dev The contract is unpaused.
    error Unpaused();

    // @dev Reentrancy guard.
    error ReentrancyGuard();

    /// @dev Account address is incorrect.
    /// @param account Account address.
    error WrongAccount(address account);
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
    event MessagePosted(uint256 indexed sequence, address[] targets, uint256[] stakingIncentives, uint256 transferAmount);
    event MessageReceived(address indexed l1Relayer, uint256 indexed chainId, bytes data);
    event L2TargetDispenserUpdated(address indexed l2TargetDispenser);

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
    /// @return sequence Unique message sequence (if applicable) or the batch number.
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
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

        // Send the message to L2
        uint256 sequence = _sendMessage(targets, stakingIncentives, bridgePayload, transferAmount);

        // Increase the staking batch nonce
        stakingBatchNonce++;

        emit MessagePosted(sequence, targets, stakingIncentives, transferAmount);
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

        // Send the message to L2
        uint256 sequence = _sendMessage(targets, stakingIncentives, bridgePayload, transferAmount);

        // Increase the staking batch nonce
        stakingBatchNonce++;

        emit MessagePosted(sequence, targets, stakingIncentives, transferAmount);
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


// File contracts/staking/ArbitrumDepositProcessorL1.sol
interface IBridge {
    // Source: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/ethereum/gateway/L1ArbitrumGateway.sol#L238
    // Calling contract: L1ERC20Gateway
    // Doc: https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20
    // Addresses: https://docs.arbitrum.io/build-decentralized-apps/reference/useful-addresses
    /// @notice Deposit ERC20 token from Ethereum into Arbitrum.
    /// @dev L2 address alias will not be applied to the following types of addresses on L1:
    ///      - an externally-owned account
    ///      - a contract in construction
    ///      - an address where a contract will be created
    ///      - an address where a contract lived, but was destroyed
    /// @param _l1Token L1 address of ERC20
    /// @param _refundTo Account, or its L2 alias if it have code in L1, to be credited with excess gas refund in L2
    /// @param _to Account to be credited with the tokens in the L2 (can be the user's L2 account or a contract), not subject to L2 aliasing
    ///            This account, or its L2 alias if it have code in L1, will also be able to cancel the retryable ticket and receive callvalue refund
    /// @param _amount Token Amount
    /// @param _maxGas Max gas deducted from user's L2 balance to cover L2 execution
    /// @param _gasPriceBid Gas price for L2 execution
    /// @param _data encoded data from router and user
    /// @return res abi encoded inbox sequence number
    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory res);

    // Source: https://github.com/OffchainLabs/nitro-contracts/blob/67127e2c2fd0943d9d87a05915d77b1f220906aa/src/bridge/Inbox.sol#L432
    // Doc: https://docs.arbitrum.io/arbos/l1-to-l2-messaging
    /// @dev Gas limit and maxFeePerGas should not be set to 1 as that is used to trigger the RetryableData error
    /// @param to destination L2 contract address
    /// @param l2CallValue call value for retryable L2 message
    /// @param maxSubmissionCost Max gas deducted from user's L2 balance to cover base submission fee
    /// @param excessFeeRefundAddress gasLimit x maxFeePerGas - execution cost gets credited here on L2 balance
    /// @param callValueRefundAddress l2Callvalue gets credited here on L2 if retryable txn times out or gets cancelled
    /// @param gasLimit Max gas deducted from user's L2 balance to cover L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
    /// @param maxFeePerGas price bid for L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
    /// @param data ABI encoded data of L2 message
    /// @return unique message number of the retryable transaction
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256);

    // Source: https://github.com/OffchainLabs/nitro-contracts/blob/67127e2c2fd0943d9d87a05915d77b1f220906aa/src/bridge/Outbox.sol#L78
    /// @notice When l2ToL1Sender returns a nonzero address, the message was originated by an L2 account
    ///         When the return value is zero, that means this is a system message
    /// @dev the l2ToL1Sender behaves as the tx.origin, the msg.sender should be validated to protect against reentrancies
    function l2ToL1Sender() external view returns (address);
}

/// @title ArbitrumDepositProcessorL1 - Smart contract for sending tokens and data via Arbitrum bridge from L1 to L2 and processing data received from L2.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ArbitrumDepositProcessorL1 is DefaultDepositProcessorL1 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 160;
    // L1 ERC20 Gateway address
    address public immutable l1ERC20Gateway;
    // L1 Outbox relayer address
    address public immutable outbox;
    // L1 Bridge relayer address
    address public immutable bridge;

    /// @dev ArbitrumDepositProcessorL1 constructor.
    /// @param _olas OLAS token address.
    /// @param _l1Dispenser L1 tokenomics dispenser address.
    /// @param _l1TokenRelayer L1 token relayer router bridging contract address (L1ERC20GatewayRouter).
    /// @param _l1MessageRelayer L1 message relayer bridging contract address (Inbox).
    /// @param _l2TargetChainId L2 target chain Id.
    /// @param _l1ERC20Gateway Actual L1 token relayer bridging contract address.
    /// @param _outbox L1 Outbox relayer contract address.
    /// @param _bridge L1 Bridge repalyer contract address that finalizes the call from L2 to L1
    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _l1ERC20Gateway,
        address _outbox,
        address _bridge
    )
        DefaultDepositProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId)
    {
        // Check for zero contract addresses
        if (_l1ERC20Gateway == address(0) || _outbox == address(0) || _bridge == address(0)) {
            revert ZeroAddress();
        }

        l1ERC20Gateway = _l1ERC20Gateway;
        outbox = _outbox;
        bridge = _bridge;
    }

    /// @inheritdoc DefaultDepositProcessorL1
    /// @notice bridgePayload is composed of the following parameters:
    ///         - refundAccount: address of a refund account for the excess of funds paid for the message transaction.
    ///                          Note if refundAccount is zero address, it is defaulted to the msg.sender;
    ///         - gasPriceBid: gas price bid of a sending L1 chain;
    ///         - maxSubmissionCostToken: Max gas deducted from user's L2 balance to cover token base submission fee;
    ///         - gasLimitMessage: Max gas deducted from user's L2 balance to cover L2 message execution
    ///         - maxSubmissionCostMessage: Max gas deducted from user's L2 balance to cover message base submission fee.
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal override returns (uint256 sequence) {
        // Check for the bridge payload length
        if (bridgePayload.length != BRIDGE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(BRIDGE_PAYLOAD_LENGTH, bridgePayload.length);
        }

        // Decode the staking contract supplemental payload required for bridging tokens
        (address refundAccount, uint256 gasPriceBid, uint256 maxSubmissionCostToken, uint256 gasLimitMessage,
            uint256 maxSubmissionCostMessage) = abi.decode(bridgePayload, (address, uint256, uint256, uint256, uint256));

        // If refundAccount is zero, default to msg.sender
        if (refundAccount == address(0)) {
            refundAccount = msg.sender;
        }

        // Check for the tx param limits
        // See the function description for the magic values of 1
        if (gasPriceBid < 2 || gasLimitMessage < 2 || maxSubmissionCostMessage == 0) {
            revert ZeroValue();
        }

        // Calculate token and message transfer cost
        // Reference: https://docs.arbitrum.io/arbos/l1-to-l2-messaging#submission
        uint256[] memory cost = new uint256[](2);
        if (transferAmount > 0) {
            if (maxSubmissionCostToken == 0) {
                revert ZeroValue();
            }

            // Calculate token transfer gas cost
            cost[0] = maxSubmissionCostToken + TOKEN_GAS_LIMIT * gasPriceBid;
        }

        // Calculate cost for the message transfer
        cost[1] = maxSubmissionCostMessage + gasLimitMessage * gasPriceBid;
        // Get the total cost
        uint256 totalCost = cost[0] + cost[1];

        // Check fot msg.value to cover the total cost
        if (totalCost > msg.value) {
            revert LowerThan(msg.value, totalCost);
        }

        if (transferAmount > 0) {
            // Approve tokens for the bridge contract
            IToken(olas).approve(l1ERC20Gateway, transferAmount);

            // Construct the data for IBridge consisting of 2 pieces:
            // uint256 maxSubmissionCost: Max gas deducted from user's L2 balance to cover base submission fee
            // bytes memory extraData: empty data
            bytes memory submissionCostData = abi.encode(maxSubmissionCostToken, "");

            // Transfer OLAS to the staking dispenser contract across the bridge
            IBridge(l1TokenRelayer).outboundTransferCustomRefund{value: cost[0]}(olas, refundAccount,
                l2TargetDispenser, transferAmount, TOKEN_GAS_LIMIT, gasPriceBid, submissionCostData);
        }

        // Assemble message data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives));

        // Send a message to the staking dispenser contract on L2 to reflect the transferred OLAS amount
        sequence = IBridge(l1MessageRelayer).createRetryableTicket{value: cost[1]}(l2TargetDispenser, 0,
            maxSubmissionCostMessage, refundAccount, refundAccount, gasLimitMessage, gasPriceBid, data);
    }

    /// @dev Process message received from L2.
    /// @param data Bytes message data sent from L2.
    function receiveMessage(bytes memory data) external {
        // Check L1 Relayer address
        if (msg.sender != bridge) {
            revert TargetRelayerOnly(msg.sender, bridge);
        }

        // Get L2 target dispenser address
        address l2Dispenser = IBridge(outbox).l2ToL1Sender();

        // Process the data
        _receiveMessage(l1MessageRelayer, l2Dispenser, data);
    }
}
