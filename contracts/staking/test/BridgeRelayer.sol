// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "hardhat/console.sol";

//interface IBridgeRelayer {
//    function receiveMessage(bytes memory data) external payable;
//}

interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Mocking the universal bridge relayer.
contract BridgeRelayer {
    address public immutable token;
    address public arbitrumDepositProcessorL1;
    address public arbitrumTargetDispenserL2;

    constructor(address _token) {
        token = _token;
    }

    function setArbitrumAddresses(address _arbitrumDepositProcessorL1, address _arbitrumTargetDispenserL2) external {
        arbitrumDepositProcessorL1 = _arbitrumDepositProcessorL1;
        arbitrumTargetDispenserL2 = _arbitrumTargetDispenserL2;
    }

    // !!!!!!!!!!!!!!!!!!!!! ARBITRUM FUNCTIONS !!!!!!!!!!!!!!!!!!!!!
    // Source: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/ethereum/gateway/L1ArbitrumGateway.sol#L238
    // Calling contract: L1ERC20Gateway
    // Doc: https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20
    // Addresses: https://docs.arbitrum.io/build-decentralized-apps/reference/useful-addresses
    // @notice Deposit ERC20 token from Ethereum into Arbitrum.
    // @dev L2 address alias will not be applied to the following types of addresses on L1:
    //      - an externally-owned account
    //      - a contract in construction
    //      - an address where a contract will be created
    //      - an address where a contract lived, but was destroyed
    // @param l1Token L1 address of ERC20
    // @param refundTo Account, or its L2 alias if it have code in L1, to be credited with excess gas refund in L2
    // @param to Account to be credited with the tokens in the L2 (can be the user's L2 account or a contract), not subject to L2 aliasing
    //            This account, or its L2 alias if it have code in L1, will also be able to cancel the retryable ticket and receive callvalue refund
    // @param amount Token Amount
    // @param maxGas Max gas deducted from user's L2 balance to cover L2 execution
    // @param gasPriceBid Gas price for L2 execution
    // @param data encoded data from router and user
    // @return res abi encoded inbox sequence number
    function outboundTransferCustomRefund(
        address l1Token,
        address,
        address to,
        uint256 amount,
        uint256,
        uint256,
        bytes calldata
    ) external payable returns (bytes memory) {
        IToken(l1Token).transferFrom(msg.sender, address(this), amount);
        IToken(l1Token).transfer(to, amount);
        return "";
    }

    // Source: https://github.com/OffchainLabs/nitro-contracts/blob/67127e2c2fd0943d9d87a05915d77b1f220906aa/src/bridge/Inbox.sol#L432
    // Doc: https://docs.arbitrum.io/arbos/l1-to-l2-messaging
    // @dev Gas limit and maxFeePerGas should not be set to 1 as that is used to trigger the RetryableData error
    // @param to destination L2 contract address
    // @param l2CallValue call value for retryable L2 message
    // @param maxSubmissionCost Max gas deducted from user's L2 balance to cover base submission fee
    // @param excessFeeRefundAddress gasLimit x maxFeePerGas - execution cost gets credited here on L2 balance
    // @param callValueRefundAddress l2Callvalue gets credited here on L2 if retryable txn times out or gets cancelled
    // @param gasLimit Max gas deducted from user's L2 balance to cover L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
    // @param maxFeePerGas price bid for L2 execution. Should not be set to 1 (magic value used to trigger the RetryableData error)
    // @param data ABI encoded data of L2 message
    // @return unique message number of the retryable transaction
    function createRetryableTicket(
        address to,
        uint256,
        uint256,
        address,
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external payable returns (uint256) {
        (bool success, ) = to.call(data);

        if (success) {
            return 0;
        } else {
            return 1;
        }
    }

    // Source: https://github.com/OffchainLabs/nitro-contracts/blob/67127e2c2fd0943d9d87a05915d77b1f220906aa/src/bridge/Outbox.sol#L78
    /// @notice When l2ToL1Sender returns a nonzero address, the message was originated by an L2 account
    ///         When the return value is zero, that means this is a system message
    /// @dev the l2ToL1Sender behaves as the tx.origin, the msg.sender should be validated to protect against reentrancies
    function l2ToL1Sender() external view returns (address) {
        return arbitrumTargetDispenserL2;
    }

    // Source (Go) and interface: https://docs.arbitrum.io/build-decentralized-apps/precompiles/reference#arbsys
    // Source for the possible utility contract: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/arbitrum/L2ArbitrumMessenger.sol#L30
    // Docs: https://docs.arbitrum.io/arbos/l2-to-l1-messaging
    /// @notice Send a transaction to L1
    /// @dev it is not possible to execute on the L1 any L2-to-L1 transaction which contains data
    /// to a contract address without any code (as enforced by the Bridge contract).
    /// @param destination recipient address on L1
    /// @param data (optional) calldata for L1 contract call
    /// @return a unique identifier for this L2-to-L1 transaction.
    function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256) {
        (bool success, ) = destination.call(data);

        if (success) {
            return 0;
        } else {
            return 1;
        }
    }
}
