// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./DefaultTargetProcessorL1.sol";
import "../interfaces/IToken.sol";

interface IBridge {
    // Source: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/ethereum/gateway/L1ArbitrumGateway.sol#L238
    // Calling contract: L1ERC20Gateway
    // Doc: https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20
    // Addresses: https://docs.arbitrum.io/build-decentralized-apps/reference/useful-addresses
    /**
     * @notice Deposit ERC20 token from Ethereum into Arbitrum.
     * @dev L2 address alias will not be applied to the following types of addresses on L1:
     *      - an externally-owned account
     *      - a contract in construction
     *      - an address where a contract will be created
     *      - an address where a contract lived, but was destroyed
     * @param _l1Token L1 address of ERC20
     * @param _refundTo Account, or its L2 alias if it have code in L1, to be credited with excess gas refund in L2
     * @param _to Account to be credited with the tokens in the L2 (can be the user's L2 account or a contract), not subject to L2 aliasing
                  This account, or its L2 alias if it have code in L1, will also be able to cancel the retryable ticket and receive callvalue refund
     * @param _amount Token Amount
     * @param _maxGas Max gas deducted from user's L2 balance to cover L2 execution
     * @param _gasPriceBid Gas price for L2 execution
     * @param _data encoded data from router and user
     * @return res abi encoded inbox sequence number
     */
    //  * @param maxSubmissionCost Max gas deducted from user's L2 balance to cover base submission fee
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
    /**
     * @dev Gas limit and maxFeePerGas should not be set to 1 as that is used to trigger the RetryableData error
     * @param to destination L2 contract address
     * @param l2CallValue call value for retryable L2 message
     * @param maxSubmissionCost Max gas deducted from user's L2 balance to cover base submission fee
     * @param excessFeeRefundAddress gasLimit x maxFeePerGas - execution cost gets credited here on L2 balance
     * @param callValueRefundAddress l2Callvalue gets credited here on L2 if retryable txn times out or gets cancelled
     * @param gasLimit Max gas deducted from user's L2 balance to cover L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
     * @param maxFeePerGas price bid for L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
     * @param data ABI encoded data of L2 message
     * @return unique message number of the retryable transaction
     */
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

    // Source: https://github.com/OffchainLabs/nitro-contracts/blob/67127e2c2fd0943d9d87a05915d77b1f220906aa/src/bridge/Outbox.sol#L123
    // Docs: https://docs.arbitrum.io/arbos/l2-to-l1-messaging
    /**
     * @notice Executes a messages in an Outbox entry.
     * @dev Reverts if dispute period hasn't expired, since the outbox entry
     *      is only created once the rollup confirms the respective assertion.
     * @dev it is not possible to execute any L2-to-L1 transaction which contains data
     *      to a contract address without any code (as enforced by the Bridge contract).
     * @param proof Merkle proof of message inclusion in send root
     * @param index Merkle path to message
     * @param l2Sender sender if original message (i.e., caller of ArbSys.sendTxToL1)
     * @param to destination address for L1 contract call
     * @param l2Block l2 block number at which sendTxToL1 call was made
     * @param l1Block l1 block number at which sendTxToL1 call was made
     * @param l2Timestamp l2 Timestamp at which sendTxToL1 call was made
     * @param value wei in L1 message
     * @param data abi-encoded L1 message data
     */
    function executeTransaction(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external;
}

error TargetRelayerOnly(address messageSender, address l1MessageRelayer);

contract ArbitrumTargetProcessorL1 is DefaultTargetProcessorL1 {
    // receiveMessage selector (Arbitrum chain)
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));

    address immutable outbox;

    constructor(
        address _olas,
        address _l1Dispenser,
        address _l1TokenRelayer,
        address _l1MessageRelayer,
        uint256 _l2TargetChainId,
        address _outbox
    ) DefaultTargetProcessorL1(_olas, _l1Dispenser, _l1TokenRelayer, _l1MessageRelayer, _l2TargetChainId) {
        if (_outbox == address(0)) {
            revert();
        }

        outbox = _outbox;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory bridgePayload,
        uint256 transferAmount
    ) internal override {
        // Decode the staking contract supplemental payload required for bridging tokens
        (address refundAccount, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost) =
            abi.decode(bridgePayload, (address, uint256, uint256, uint256));

        // Construct the data for IBridge consisting of 2 pieces:
        // uint256 maxSubmissionCost: Max gas deducted from user's L2 balance to cover base submission fee
        // bytes extraData: “0x”
        bytes memory submissionCostData = abi.encode(maxSubmissionCost, "0x");

        // Approve tokens for the bridge contract
        IToken(olas).approve(l1TokenRelayer, transferAmount);

        // Transfer OLAS to the staking dispenser contract across the bridge
        IBridge(l1TokenRelayer).outboundTransferCustomRefund(olas, refundAccount, l2TargetDispenser, transferAmount,
            maxGas, gasPriceBid, submissionCostData);

        // Assemble data payload
        bytes memory data = abi.encode(RECEIVE_MESSAGE, targets, stakingAmounts);

        // TODO Shall separate between two maxGas and gasPriceBid for bothe token and data calls or calculate for both?
        // Send a message to the staking dispenser contract on L2 to reflect the transferred OLAS amount
        uint256 sequence = IBridge(l1MessageRelayer).createRetryableTicket(l2TargetDispenser, 0, maxSubmissionCost,
            refundAccount, refundAccount, maxGas, gasPriceBid, data);

        emit MessageSent(sequence, targets, stakingAmounts, transferAmount);
    }

    /// @dev Processes a message received from the L2 target dispenser contract.
    /// @param data Bytes message sent from L2.
    function receiveMessage(bytes memory data) external {
        // TODO msg.sender seems to be the Outbox or address(this). So this is not compatible with the checks
        // Check L1 Relayer address
        if (msg.sender != outbox) {
            revert TargetRelayerOnly(msg.sender, outbox);
        }

        // TODO Is l2Dispenser somehow obtained or extract it via the data decoding (the need encoding on L2)?
        // TODO Since this is the finalization call, it is safe to call it by anyone
//        if (l2Dispenser != l2TargetDispenser) {
//            revert WrongMessageSender(l2Dispenser, l2TargetDispenser);
//        }
//
//        if (l2TargetChainId != chainId) {
//            revert();
//        }

        emit MessageReceived(l2TargetDispenser, l2TargetChainId, data);

        // Process the data
        _receiveMessage(data);
    }

    // The data must ultimately match the call to the receiveMessage() function
    function executeTransactionHelper(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        bytes calldata data
    ) external {
        IBridge(outbox).executeTransaction(proof, index, l2Sender, to, l2Block, l1Block, l2Timestamp, 0, data);
    }
}