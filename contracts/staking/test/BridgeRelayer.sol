// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBridgeRelayer {
    function receiveMessage(bytes memory data) external payable;
    function onTokenBridged(address, uint256, bytes calldata data) external;
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external;
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable;
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
    address public polygonDepositProcessorL1;
    address public polygonTargetDispenserL2;
    address public wormholeDepositProcessorL1;
    address public wormholeTargetDispenserL2;

    address public wrongToken;
    address public sender;
    uint256 public nonce;

    enum Mode {
        Normal,
        WrongRelayer,
        WrongSender,
        WrongChainId,
        WrongToken,
        WrongNumTokens,
        WrongDeliveryHash
    }
    Mode public mode;

    constructor(address _token) {
        token = _token;
    }

    function setMode(Mode _mode) external {
        mode = _mode;
        nonce++;
    }

    function setWrongToken(address _wrongToken) external {
        wrongToken = _wrongToken;
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

    function setPolygonAddresses(address _polygonDepositProcessorL1, address _polygonTargetDispenserL2) external {
        polygonDepositProcessorL1 = _polygonDepositProcessorL1;
        polygonTargetDispenserL2 = _polygonTargetDispenserL2;
    }

    function setWormholeAddresses(address _wormholeDepositProcessorL1, address _wormholeTargetDispenserL2) external {
        wormholeDepositProcessorL1 = _wormholeDepositProcessorL1;
        wormholeTargetDispenserL2 = _wormholeTargetDispenserL2;
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
        destination = arbitrumDepositProcessorL1;
        (bool success, ) = destination.call(data);

        if (success) {
            return 0;
        } else {
            return 1;
        }
    }

    /// @dev Simulate the L2 dispenser de-aliased address such that after aliasing it's the same as address(this).
    function l1ToL2AliasedSender() external view returns (address) {
        // Get the l1AliasedDepositProcessor based on _l1DepositProcessor
        uint160 offset = uint160(0x1111000000000000000000000000000000001111);
        unchecked {
            return address(uint160(address(this)) - offset);
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
        (bool success, bytes memory returnData) = target.call(data);

        if (!success) {
            assembly {
                let returnDataSize := mload(returnData)
                revert(add(32, returnData), returnDataSize)
            }
        }
        return bytes32(0);
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
        if (mode == Mode.WrongSender) {
            return address(1);
        } else {
            return sender;
        }
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


    // !!!!!!!!!!!!!!!!!!!!! POLYGON FUNCTIONS !!!!!!!!!!!!!!!!!!!!!
    // Source: https://github.com/maticnetwork/pos-portal/blob/master/flat/RootChainManager.sol#L2173
    /// @notice Move tokens from root to child chain
    /// @dev This mechanism supports arbitrary tokens as long as its predicate has been registered and the token is mapped
    /// @param user address of account that should receive this deposit on child chain
    /// @param rootToken address of token that is being deposited
    /// @param depositData bytes data that is sent to predicate and child token contracts to handle deposit
    function depositFor(address user, address rootToken, bytes calldata depositData) external {
        uint256 amount = abi.decode(depositData, (uint256));
        IToken(rootToken).transferFrom(msg.sender, address(this), amount);
        IToken(rootToken).transfer(user, amount);
    }


    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/FxRoot.sol#L29
    function sendMessageToChild(address receiver, bytes calldata data) external {
        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L36
        IBridgeRelayer(receiver).processMessageFromRoot(0, msg.sender, data);
    }


    // !!!!!!!!!!!!!!!!!!!!! WORMHOLE FUNCTIONS !!!!!!!!!!!!!!!!!!!!!
    // @notice VaaKey identifies a wormhole message
    //
    // @custom:member chainId Wormhole chain ID of the chain where this VAA was emitted from
    // @custom:member emitterAddress Address of the emitter of the VAA, in Wormhole bytes32 format
    // @custom:member sequence Sequence number of the VAA
    struct VaaKey {
        uint16 chainId;
        bytes32 emitterAddress;
        uint64 sequence;
    }

    struct TokenReceived {
        bytes32 tokenHomeAddress;
        uint16 tokenHomeChain;
        address tokenAddress; // wrapped address if tokenHomeChain !== this chain, else tokenHomeAddress (in evm address format)
        uint256 amount;
        uint256 amountNormalized; // if decimals > 8, normalized to 8 decimal places
    }

    struct TransferWithPayload {
        uint8 payloadID;
        uint256 amount;
        bytes32 tokenAddress;
        uint16 tokenChain;
        bytes32 to;
        uint16 toChain;
        bytes32 fromAddress;
        bytes payload;
    }

    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint8 guardianIndex;
    }

    struct VM {
        uint8 version;
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
        uint32 guardianSetIndex;
        Signature[] signatures;
        bytes32 hash;
    }

    function transferTokensWithPayload(
        address l1Token,
        uint256 amount,
        uint16,
        bytes32 recipient,
        uint32,
        bytes memory
    ) external payable returns (uint64 sequence) {
        IToken(l1Token).transferFrom(msg.sender, address(this), amount);
        IToken(l1Token).transfer(address(uint160(uint256(recipient))), amount);
        sequence = 0;
    }
    
    // @notice Returns the price to request a relay to chain `targetChain`, using the default delivery provider
    //
    // @param targetChain in Wormhole Chain ID format
    // @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    // @param gasLimit gas limit with which to call `targetAddress`.
    // @return nativePriceQuote Price, in units of current chain currency, that the delivery provider charges to perform the relay
    // @return targetChainRefundPerGasUnused amount of target chain currency that will be refunded per unit of gas unused,
    //         if a refundAddress is specified.
    //         Note: This value can be overridden by the delivery provider on the target chain. The returned value here should be considered to be a
    //         promise by the delivery provider of the amount of refund per gas unused that will be returned to the refundAddress at the target chain.
    //         If a delivery provider decides to override, this will be visible as part of the emitted Delivery event on the target chain.
    function quoteEVMDeliveryPrice(uint16, uint256, uint256)
        external pure returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused) {
        nativePriceQuote = 1;
        targetChainRefundPerGasUnused = 1;
    }

    function messageFee() external pure returns (uint256) {
        return 0;
    }

    function chainId() external view returns (uint16) {
        if (mode == Mode.WrongChainId) {
            return 0;
        }
        return 1;
    }
    
    // @notice Publishes an instruction for the default delivery provider
    // to relay a payload and VAAs specified by `vaaKeys` to the address `targetAddress` on chain `targetChain`
    // with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
    //
    // Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
    // `targetAddress` must implement the IWormholeReceiver interface
    //
    // This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
    //
    // @param targetChain in Wormhole Chain ID format
    // @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    // @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    // @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    // @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    //        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
    // @param vaaKeys Additional VAAs to pass in as parameter in call to `targetAddress`
    // @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
    // @param refundAddress The address on `refundChain` to deliver any refund to
    // @return sequence sequence number of published VAA containing delivery instructions
    ///wormholeRelayer.sendVaasToEvm
    function sendVaasToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256,
        uint256,
        VaaKey[] memory,
        uint16,
        address
    ) external payable returns (uint64 sequence) {
        if (mode == Mode.WrongChainId) {
            targetChain = 0;
        }

        bytes[] memory additionalVaas = new bytes[](1);

        if (mode == Mode.WrongNumTokens) {
            additionalVaas = new bytes[](2);
        }

        IBridgeRelayer(targetAddress).receiveWormholeMessages(payload, additionalVaas,
            bytes32(uint256(uint160(msg.sender))), targetChain, bytes32(nonce));

        if (mode != Mode.WrongDeliveryHash) {
            nonce++;
        }
        sequence = 0;
    }

    function bridgeContracts(uint16) external view returns (bytes32) {
        return bytes32(uint256(uint160(wormholeTargetDispenserL2)));
    }

    function parseVM(bytes memory) external view returns (VM memory vm) {
        vm.emitterAddress = bytes32(uint256(uint160(wormholeTargetDispenserL2)));
    }

    function parseTransferWithPayload(bytes memory) external view returns (TransferWithPayload memory transfer) {
        transfer.tokenAddress = bytes32(uint256(uint160(token)));
        transfer.tokenChain = 1;
        transfer.to = bytes32(uint256(uint160(wormholeTargetDispenserL2)));
        transfer.toChain = 1;

        if (mode == Mode.WrongChainId) {
            transfer.tokenChain = 0;
            transfer.toChain = 0;
        }
        if (mode == Mode.WrongToken && wrongToken != address(0)) {
            transfer.tokenAddress = bytes32(uint256(uint160(wrongToken)));
        }
    }

    function completeTransferWithPayload(bytes memory) external pure returns (bytes memory) {
        return "0x";
    }

    // Source: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/b9e129e65d34827d92fceeed8c87d3ecdfc801d0/src/interfaces/IWormholeRelayer.sol#L122
    // @notice Publishes an instruction for the default delivery provider
    // to relay a payload to the address `targetAddress` on chain `targetChain`
    // with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
    //
    // Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
    // `targetAddress` must implement the IWormholeReceiver interface
    //
    // This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
    //
    // @param targetChain in Wormhole Chain ID format
    // @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    // @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    // @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    // @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    //        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
    // @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
    // @param refundAddress The address on `refundChain` to deliver any refund to
    // @return sequence sequence number of published VAA containing delivery instructions
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256,
        uint256,
        uint16,
        address
    ) external payable returns (uint64 sequence) {
        if (mode == Mode.WrongChainId) {
            targetChain = 0;
        }

        IBridgeRelayer(targetAddress).receiveWormholeMessages(payload, new bytes[](0),
            bytes32(uint256(uint160(msg.sender))), targetChain, bytes32(nonce));

        if (mode != Mode.WrongDeliveryHash) {
            nonce++;
        }
        sequence = 0;
    }
}
