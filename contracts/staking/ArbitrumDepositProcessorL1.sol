// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DefaultDepositProcessorL1, IToken} from "./DefaultDepositProcessorL1.sol";

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

        // Check for the max message gas limit
        if (gasLimitMessage > MESSAGE_GAS_LIMIT) {
            revert Overflow(gasLimitMessage, MESSAGE_GAS_LIMIT);
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