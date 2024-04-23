// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "hardhat/console.sol";

interface IBridgeRelayer {
    function receiveMessage(bytes memory data) external payable;
    function onTokenBridged(address, uint256, bytes calldata data) external;
}

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
    address public gnosisDepositProcessorL1;
    address public gnosisTargetDispenserL2;
    address public optimismDepositProcessorL1;
    address public optimismTargetDispenserL2;

    address public sender;

    constructor(address _token) {
        token = _token;
    }

    function setArbitrumAddresses(address _arbitrumDepositProcessorL1, address _arbitrumTargetDispenserL2) external {
        arbitrumDepositProcessorL1 = _arbitrumDepositProcessorL1;
        arbitrumTargetDispenserL2 = _arbitrumTargetDispenserL2;
    }

    function setGnosisAddresses(address _gnosisDepositProcessorL1, address _gnosisTargetDispenserL2) external {
        gnosisDepositProcessorL1 = _gnosisDepositProcessorL1;
        gnosisTargetDispenserL2 = _gnosisTargetDispenserL2;
    }

    function setOptimismAddresses(address _optimismDepositProcessorL1, address _optimismTargetDispenserL2) external {
        optimismDepositProcessorL1 = _optimismDepositProcessorL1;
        optimismTargetDispenserL2 = _optimismTargetDispenserL2;
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


    // !!!!!!!!!!!!!!!!!!!!! GNOSIS FUNCTIONS !!!!!!!!!!!!!!!!!!!!!
    // Contract: AMB Contract Proxy Foreign
    // Source: https://github.com/omni/tokenbridge-contracts/blob/908a48107919d4ab127f9af07d44d47eac91547e/contracts/upgradeable_contracts/arbitrary_message/MessageDelivery.sol#L22
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    /// @dev Requests message relay to the opposite network
    /// @param target Executor address on the other side.
    /// @param data Calldata passed to the executor on the other side.
    /// @return Message Id.
    function requireToPassMessage(address target, bytes memory data, uint256) external returns (bytes32) {
        sender = msg.sender;
        (bool success, ) = target.call(data);

        if (success) {
            return bytes32(0);
        } else {
            revert();
        }
    }

    // Contract: Omnibridge Multi-Token Mediator Proxy
    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/components/common/TokensRelayer.sol#L80
    // Flattened: https://vscode.blockscan.com/gnosis/0x2dbdcc6cad1a5a11fd6337244407bc06162aaf92
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
    function relayTokensAndCall(address l1Token, address receiver, uint256 amount, bytes memory payload) external {
        IToken(l1Token).transferFrom(msg.sender, address(this), amount);
        IToken(l1Token).transfer(receiver, amount);
        IBridgeRelayer(receiver).onTokenBridged(address(0), 0, payload);
    }

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#security-considerations-for-receiving-a-call
    function messageSender() external view returns (address) {
        return sender;
    }


    // !!!!!!!!!!!!!!!!!!!!! OPTIMISM FUNCTIONS !!!!!!!!!!!!!!!!!!!!!
    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/L1/L1StandardBridge.sol#L188
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/standard-bridge#architecture
    // @custom:legacy
    // @notice Deposits some amount of ERC20 tokens into a target account on L2.
    //
    // @param l1Token     Address of the L1 token being deposited.
    // @param l2Token     Address of the corresponding token on L2.
    // @param to          Address of the recipient on L2.
    // @param amount      Amount of the ERC20 to deposit.
    // @param minGasLimit Minimum gas limit for the deposit message on L2.
    // @param extraData   Optional data to forward to L2. Data supplied here will not be used to
    //                     execute any code on L2 and is only emitted as extra data for the
    //                     convenience of off-chain tooling.
    function depositERC20To(
        address l1Token,
        address,
        address to,
        uint256 amount,
        uint32,
        bytes calldata
    ) external {
        IToken(l1Token).transferFrom(msg.sender, address(this), amount);
        IToken(l1Token).transfer(to, amount);
    }

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L259
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging
    // @notice Sends a message to some target address on the other chain. Note that if the call
    //         always reverts, then the message will be unrelayable, and any ETH sent will be
    //         permanently locked. The same will occur if the target on the other chain is
    //         considered unsafe (see the _isUnsafeTarget() function).
    //
    // @param target      Target contract or wallet address.
    // @param message     Message to trigger the target address with.
    // @param minGasLimit Minimum gas limit that the message can be executed with.
    function sendMessage(
        address target,
        bytes calldata message,
        uint32
    ) external payable {
        sender = msg.sender;
        (bool success, ) = target.call(message);

        if (!success) {
            revert();
        }
    }

    // Source: https://github.com/ethereum-optimism/optimism/blob/65ec61dde94ffa93342728d324fecf474d228e1f/packages/contracts-bedrock/contracts/universal/CrossDomainMessenger.sol#L422
    // Doc: https://docs.optimism.io/builders/app-developers/bridging/messaging#accessing-msgsender
    // @notice Retrieves the address of the contract or wallet that initiated the currently
    //         executing message on the other chain. Will throw an error if there is no message
    //         currently being executed. Allows the recipient of a call to see who triggered it.
    //
    // @return Address of the sender of the currently executing message on the other chain.
    function xDomainMessageSender() external view returns (address) {
        return sender;
    }
}
