// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: Apache-2.0 AND MIT
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


// File lib/fx-portal/contracts/FxRoot.sol
interface IStateSender {
    function syncState(address receiver, bytes calldata data) external;
}

interface IFxStateSender {
    function sendMessageToChild(address _receiver, bytes calldata _data) external;
}

/**
 * @title FxRoot root contract for fx-portal
 */
contract FxRoot is IFxStateSender {
    IStateSender public stateSender;
    address public fxChild;

    constructor(address _stateSender) {
        stateSender = IStateSender(_stateSender);
    }

    function setFxChild(address _fxChild) public {
        require(fxChild == address(0x0));
        fxChild = _fxChild;
    }

    // @custom:security non-reentrant
    function sendMessageToChild(address _receiver, bytes calldata _data) public override {
        bytes memory data = abi.encode(msg.sender, _receiver, _data);
        stateSender.syncState(fxChild, data);
    }
}


// File lib/fx-portal/contracts/lib/RLPReader.sol
library RLPReader {
    uint8 constant STRING_SHORT_START = 0x80;
    uint8 constant STRING_LONG_START = 0xb8;
    uint8 constant LIST_SHORT_START = 0xc0;
    uint8 constant LIST_LONG_START = 0xf8;
    uint8 constant WORD_SIZE = 32;

    struct RLPItem {
        uint256 len;
        uint256 memPtr;
    }

    struct Iterator {
        RLPItem item; // Item that's being iterated over.
        uint256 nextPtr; // Position of the next item in the list.
    }

    /*
     * @dev Returns the next element in the iteration. Reverts if it has not next element.
     * @param self The iterator.
     * @return The next element in the iteration.
     */
    function next(Iterator memory self) internal pure returns (RLPItem memory) {
        require(hasNext(self));

        uint256 ptr = self.nextPtr;
        uint256 itemLength = _itemLength(ptr);
        self.nextPtr = ptr + itemLength;

        return RLPItem(itemLength, ptr);
    }

    /*
     * @dev Returns true if the iteration has more elements.
     * @param self The iterator.
     * @return true if the iteration has more elements.
     */
    function hasNext(Iterator memory self) internal pure returns (bool) {
        RLPItem memory item = self.item;
        return self.nextPtr < item.memPtr + item.len;
    }

    /*
     * @param item RLP encoded bytes
     */
    function toRlpItem(bytes memory item) internal pure returns (RLPItem memory) {
        uint256 memPtr;
        assembly {
            memPtr := add(item, 0x20)
        }

        return RLPItem(item.length, memPtr);
    }

    /*
     * @dev Create an iterator. Reverts if item is not a list.
     * @param self The RLP item.
     * @return An 'Iterator' over the item.
     */
    function iterator(RLPItem memory self) internal pure returns (Iterator memory) {
        require(isList(self));

        uint256 ptr = self.memPtr + _payloadOffset(self.memPtr);
        return Iterator(self, ptr);
    }

    /*
     * @param the RLP item.
     */
    function rlpLen(RLPItem memory item) internal pure returns (uint256) {
        return item.len;
    }

    /*
     * @param the RLP item.
     * @return (memPtr, len) pair: location of the item's payload in memory.
     */
    function payloadLocation(RLPItem memory item) internal pure returns (uint256, uint256) {
        uint256 offset = _payloadOffset(item.memPtr);
        uint256 memPtr = item.memPtr + offset;
        uint256 len = item.len - offset; // data length
        return (memPtr, len);
    }

    /*
     * @param the RLP item.
     */
    function payloadLen(RLPItem memory item) internal pure returns (uint256) {
        (, uint256 len) = payloadLocation(item);
        return len;
    }

    /*
     * @param the RLP item containing the encoded list.
     */
    function toList(RLPItem memory item) internal pure returns (RLPItem[] memory) {
        require(isList(item));

        uint256 items = numItems(item);
        RLPItem[] memory result = new RLPItem[](items);

        uint256 memPtr = item.memPtr + _payloadOffset(item.memPtr);
        uint256 dataLen;
        for (uint256 i = 0; i < items; i++) {
            dataLen = _itemLength(memPtr);
            result[i] = RLPItem(dataLen, memPtr);
            memPtr = memPtr + dataLen;
        }

        return result;
    }

    // @return indicator whether encoded payload is a list. negate this function call for isData.
    function isList(RLPItem memory item) internal pure returns (bool) {
        if (item.len == 0) return false;

        uint8 byte0;
        uint256 memPtr = item.memPtr;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < LIST_SHORT_START) return false;
        return true;
    }

    /*
     * @dev A cheaper version of keccak256(toRlpBytes(item)) that avoids copying memory.
     * @return keccak256 hash of RLP encoded bytes.
     */
    function rlpBytesKeccak256(RLPItem memory item) internal pure returns (bytes32) {
        uint256 ptr = item.memPtr;
        uint256 len = item.len;
        bytes32 result;
        assembly {
            result := keccak256(ptr, len)
        }
        return result;
    }

    /*
     * @dev A cheaper version of keccak256(toBytes(item)) that avoids copying memory.
     * @return keccak256 hash of the item payload.
     */
    function payloadKeccak256(RLPItem memory item) internal pure returns (bytes32) {
        (uint256 memPtr, uint256 len) = payloadLocation(item);
        bytes32 result;
        assembly {
            result := keccak256(memPtr, len)
        }
        return result;
    }

    /** RLPItem conversions into data types **/

    // @returns raw rlp encoding in bytes
    function toRlpBytes(RLPItem memory item) internal pure returns (bytes memory) {
        bytes memory result = new bytes(item.len);
        if (result.length == 0) return result;

        uint256 ptr;
        assembly {
            ptr := add(0x20, result)
        }

        copy(item.memPtr, ptr, item.len);
        return result;
    }

    // any non-zero byte except "0x80" is considered true
    function toBoolean(RLPItem memory item) internal pure returns (bool) {
        require(item.len == 1);
        uint256 result;
        uint256 memPtr = item.memPtr;
        assembly {
            result := byte(0, mload(memPtr))
        }

        // SEE Github Issue #5.
        // Summary: Most commonly used RLP libraries (i.e Geth) will encode
        // "0" as "0x80" instead of as "0". We handle this edge case explicitly
        // here.
        if (result == 0 || result == STRING_SHORT_START) {
            return false;
        } else {
            return true;
        }
    }

    function toAddress(RLPItem memory item) internal pure returns (address) {
        // 1 byte for the length prefix
        require(item.len == 21);

        return address(uint160(toUint(item)));
    }

    function toUint(RLPItem memory item) internal pure returns (uint256) {
        require(item.len > 0 && item.len <= 33);

        (uint256 memPtr, uint256 len) = payloadLocation(item);

        uint256 result;
        assembly {
            result := mload(memPtr)

            // shift to the correct location if neccesary
            if lt(len, 32) {
                result := div(result, exp(256, sub(32, len)))
            }
        }

        return result;
    }

    // enforces 32 byte length
    function toUintStrict(RLPItem memory item) internal pure returns (uint256) {
        // one byte prefix
        require(item.len == 33);

        uint256 result;
        uint256 memPtr = item.memPtr + 1;
        assembly {
            result := mload(memPtr)
        }

        return result;
    }

    function toBytes(RLPItem memory item) internal pure returns (bytes memory) {
        require(item.len > 0);

        (uint256 memPtr, uint256 len) = payloadLocation(item);
        bytes memory result = new bytes(len);

        uint256 destPtr;
        assembly {
            destPtr := add(0x20, result)
        }

        copy(memPtr, destPtr, len);
        return result;
    }

    /*
     * Private Helpers
     */

    // @return number of payload items inside an encoded list.
    function numItems(RLPItem memory item) private pure returns (uint256) {
        if (item.len == 0) return 0;

        uint256 count = 0;
        uint256 currPtr = item.memPtr + _payloadOffset(item.memPtr);
        uint256 endPtr = item.memPtr + item.len;
        while (currPtr < endPtr) {
            currPtr = currPtr + _itemLength(currPtr); // skip over an item
            count++;
        }

        return count;
    }

    // @return entire rlp item byte length
    function _itemLength(uint256 memPtr) private pure returns (uint256) {
        uint256 itemLen;
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < STRING_SHORT_START) {
            itemLen = 1;
        } else if (byte0 < STRING_LONG_START) {
            itemLen = byte0 - STRING_SHORT_START + 1;
        } else if (byte0 < LIST_SHORT_START) {
            assembly {
                let byteLen := sub(byte0, 0xb7) // # of bytes the actual length is
                memPtr := add(memPtr, 1) // skip over the first byte

                /* 32 byte word size */
                let dataLen := div(mload(memPtr), exp(256, sub(32, byteLen))) // right shifting to get the len
                itemLen := add(dataLen, add(byteLen, 1))
            }
        } else if (byte0 < LIST_LONG_START) {
            itemLen = byte0 - LIST_SHORT_START + 1;
        } else {
            assembly {
                let byteLen := sub(byte0, 0xf7)
                memPtr := add(memPtr, 1)

                let dataLen := div(mload(memPtr), exp(256, sub(32, byteLen))) // right shifting to the correct length
                itemLen := add(dataLen, add(byteLen, 1))
            }
        }

        return itemLen;
    }

    // @return number of bytes until the data
    function _payloadOffset(uint256 memPtr) private pure returns (uint256) {
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < STRING_SHORT_START) {
            return 0;
        } else if (byte0 < STRING_LONG_START || (byte0 >= LIST_SHORT_START && byte0 < LIST_LONG_START)) {
            return 1;
        } else if (byte0 < LIST_SHORT_START) {
            // being explicit
            return byte0 - (STRING_LONG_START - 1) + 1;
        } else {
            return byte0 - (LIST_LONG_START - 1) + 1;
        }
    }

    /*
     * @param src Pointer to source
     * @param dest Pointer to destination
     * @param len Amount of memory to copy from the source
     */
    function copy(uint256 src, uint256 dest, uint256 len) private pure {
        if (len == 0) return;

        // copy as many word sizes as possible
        for (; len >= WORD_SIZE; len -= WORD_SIZE) {
            assembly {
                mstore(dest, mload(src))
            }

            src += WORD_SIZE;
            dest += WORD_SIZE;
        }

        if (len > 0) {
            // left over bytes. Mask is used to remove unwanted bytes from the word
            uint256 mask = 256 ** (WORD_SIZE - len) - 1;
            assembly {
                let srcpart := and(mload(src), not(mask)) // zero out src
                let destpart := and(mload(dest), mask) // retrieve the bytes
                mstore(dest, or(destpart, srcpart))
            }
        }
    }
}


// File lib/fx-portal/contracts/lib/ExitPayloadReader.sol
library ExitPayloadReader {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    uint8 constant WORD_SIZE = 32;

    struct ExitPayload {
        RLPReader.RLPItem[] data;
    }

    struct Receipt {
        RLPReader.RLPItem[] data;
        bytes raw;
        uint256 logIndex;
    }

    struct Log {
        RLPReader.RLPItem data;
        RLPReader.RLPItem[] list;
    }

    struct LogTopics {
        RLPReader.RLPItem[] data;
    }

    // copy paste of private copy() from RLPReader to avoid changing of existing contracts
    function copy(uint256 src, uint256 dest, uint256 len) private pure {
        if (len == 0) return;

        // copy as many word sizes as possible
        for (; len >= WORD_SIZE; len -= WORD_SIZE) {
            assembly {
                mstore(dest, mload(src))
            }

            src += WORD_SIZE;
            dest += WORD_SIZE;
        }

        if (len == 0) return;

        // left over bytes. Mask is used to remove unwanted bytes from the word
        uint256 mask = 256 ** (WORD_SIZE - len) - 1;
        assembly {
            let srcpart := and(mload(src), not(mask)) // zero out src
            let destpart := and(mload(dest), mask) // retrieve the bytes
            mstore(dest, or(destpart, srcpart))
        }
    }

    function toExitPayload(bytes memory data) internal pure returns (ExitPayload memory) {
        RLPReader.RLPItem[] memory payloadData = data.toRlpItem().toList();

        return ExitPayload(payloadData);
    }

    function getHeaderNumber(ExitPayload memory payload) internal pure returns (uint256) {
        return payload.data[0].toUint();
    }

    function getBlockProof(ExitPayload memory payload) internal pure returns (bytes memory) {
        return payload.data[1].toBytes();
    }

    function getBlockNumber(ExitPayload memory payload) internal pure returns (uint256) {
        return payload.data[2].toUint();
    }

    function getBlockTime(ExitPayload memory payload) internal pure returns (uint256) {
        return payload.data[3].toUint();
    }

    function getTxRoot(ExitPayload memory payload) internal pure returns (bytes32) {
        return bytes32(payload.data[4].toUint());
    }

    function getReceiptRoot(ExitPayload memory payload) internal pure returns (bytes32) {
        return bytes32(payload.data[5].toUint());
    }

    function getReceipt(ExitPayload memory payload) internal pure returns (Receipt memory receipt) {
        receipt.raw = payload.data[6].toBytes();
        RLPReader.RLPItem memory receiptItem = receipt.raw.toRlpItem();

        if (receiptItem.isList()) {
            // legacy tx
            receipt.data = receiptItem.toList();
        } else {
            // pop first byte before parsing receipt
            bytes memory typedBytes = receipt.raw;
            bytes memory result = new bytes(typedBytes.length - 1);
            uint256 srcPtr;
            uint256 destPtr;
            assembly {
                srcPtr := add(33, typedBytes)
                destPtr := add(0x20, result)
            }

            copy(srcPtr, destPtr, result.length);
            receipt.data = result.toRlpItem().toList();
        }

        receipt.logIndex = getReceiptLogIndex(payload);
        return receipt;
    }

    function getReceiptProof(ExitPayload memory payload) internal pure returns (bytes memory) {
        return payload.data[7].toBytes();
    }

    function getBranchMaskAsBytes(ExitPayload memory payload) internal pure returns (bytes memory) {
        return payload.data[8].toBytes();
    }

    function getBranchMaskAsUint(ExitPayload memory payload) internal pure returns (uint256) {
        return payload.data[8].toUint();
    }

    function getReceiptLogIndex(ExitPayload memory payload) internal pure returns (uint256) {
        return payload.data[9].toUint();
    }

    // Receipt methods
    function toBytes(Receipt memory receipt) internal pure returns (bytes memory) {
        return receipt.raw;
    }

    function getLog(Receipt memory receipt) internal pure returns (Log memory) {
        RLPReader.RLPItem memory logData = receipt.data[3].toList()[receipt.logIndex];
        return Log(logData, logData.toList());
    }

    // Log methods
    function getEmitter(Log memory log) internal pure returns (address) {
        return RLPReader.toAddress(log.list[0]);
    }

    function getTopics(Log memory log) internal pure returns (LogTopics memory) {
        return LogTopics(log.list[1].toList());
    }

    function getData(Log memory log) internal pure returns (bytes memory) {
        return log.list[2].toBytes();
    }

    function toRlpBytes(Log memory log) internal pure returns (bytes memory) {
        return log.data.toRlpBytes();
    }

    // LogTopics methods
    function getField(LogTopics memory topics, uint256 index) internal pure returns (RLPReader.RLPItem memory) {
        return topics.data[index];
    }
}


// File lib/fx-portal/contracts/lib/Merkle.sol
library Merkle {
    function checkMembership(
        bytes32 leaf,
        uint256 index,
        bytes32 rootHash,
        bytes memory proof
    ) internal pure returns (bool) {
        require(proof.length % 32 == 0, "Invalid proof length");
        uint256 proofHeight = proof.length / 32;
        // Proof of size n means, height of the tree is n+1.
        // In a tree of height n+1, max #leafs possible is 2 ^ n
        require(index < 2 ** proofHeight, "Leaf index is too big");

        bytes32 proofElement;
        bytes32 computedHash = leaf;
        for (uint256 i = 32; i <= proof.length; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }

            if (index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            index = index / 2;
        }
        return computedHash == rootHash;
    }
}


// File lib/fx-portal/contracts/lib/MerklePatriciaProof.sol
library MerklePatriciaProof {
    /*
     * @dev Verifies a merkle patricia proof.
     * @param value The terminating value in the trie.
     * @param encodedPath The path in the trie leading to value.
     * @param rlpParentNodes The rlp encoded stack of nodes.
     * @param root The root hash of the trie.
     * @return The boolean validity of the proof.
     */
    function verify(
        bytes memory value,
        bytes memory encodedPath,
        bytes memory rlpParentNodes,
        bytes32 root
    ) internal pure returns (bool) {
        RLPReader.RLPItem memory item = RLPReader.toRlpItem(rlpParentNodes);
        RLPReader.RLPItem[] memory parentNodes = RLPReader.toList(item);

        bytes memory currentNode;
        RLPReader.RLPItem[] memory currentNodeList;

        bytes32 nodeKey = root;
        uint256 pathPtr = 0;

        bytes memory path = _getNibbleArray(encodedPath);
        if (path.length == 0) {
            return false;
        }

        for (uint256 i = 0; i < parentNodes.length; i++) {
            if (pathPtr > path.length) {
                return false;
            }

            currentNode = RLPReader.toRlpBytes(parentNodes[i]);
            if (nodeKey != keccak256(currentNode)) {
                return false;
            }
            currentNodeList = RLPReader.toList(parentNodes[i]);

            if (currentNodeList.length == 17) {
                if (pathPtr == path.length) {
                    if (keccak256(RLPReader.toBytes(currentNodeList[16])) == keccak256(value)) {
                        return true;
                    } else {
                        return false;
                    }
                }

                uint8 nextPathNibble = uint8(path[pathPtr]);
                if (nextPathNibble > 16) {
                    return false;
                }
                nodeKey = bytes32(RLPReader.toUintStrict(currentNodeList[nextPathNibble]));
                pathPtr += 1;
            } else if (currentNodeList.length == 2) {
                uint256 traversed = _nibblesToTraverse(RLPReader.toBytes(currentNodeList[0]), path, pathPtr);
                if (pathPtr + traversed == path.length) {
                    //leaf node
                    if (keccak256(RLPReader.toBytes(currentNodeList[1])) == keccak256(value)) {
                        return true;
                    } else {
                        return false;
                    }
                }

                //extension node
                if (traversed == 0) {
                    return false;
                }

                pathPtr += traversed;
                nodeKey = bytes32(RLPReader.toUintStrict(currentNodeList[1]));
            } else {
                return false;
            }
        }
    }

    function _nibblesToTraverse(
        bytes memory encodedPartialPath,
        bytes memory path,
        uint256 pathPtr
    ) private pure returns (uint256) {
        uint256 len = 0;
        // encodedPartialPath has elements that are each two hex characters (1 byte), but partialPath
        // and slicedPath have elements that are each one hex character (1 nibble)
        bytes memory partialPath = _getNibbleArray(encodedPartialPath);
        bytes memory slicedPath = new bytes(partialPath.length);

        // pathPtr counts nibbles in path
        // partialPath.length is a number of nibbles
        for (uint256 i = pathPtr; i < pathPtr + partialPath.length; i++) {
            bytes1 pathNibble = path[i];
            slicedPath[i - pathPtr] = pathNibble;
        }

        if (keccak256(partialPath) == keccak256(slicedPath)) {
            len = partialPath.length;
        } else {
            len = 0;
        }
        return len;
    }

    // bytes b must be hp encoded
    function _getNibbleArray(bytes memory b) internal pure returns (bytes memory) {
        bytes memory nibbles = "";
        if (b.length > 0) {
            uint8 offset;
            uint8 hpNibble = uint8(_getNthNibbleOfBytes(0, b));
            if (hpNibble == 1 || hpNibble == 3) {
                nibbles = new bytes(b.length * 2 - 1);
                bytes1 oddNibble = _getNthNibbleOfBytes(1, b);
                nibbles[0] = oddNibble;
                offset = 1;
            } else {
                nibbles = new bytes(b.length * 2 - 2);
                offset = 0;
            }

            for (uint256 i = offset; i < nibbles.length; i++) {
                nibbles[i] = _getNthNibbleOfBytes(i - offset + 2, b);
            }
        }
        return nibbles;
    }

    function _getNthNibbleOfBytes(uint256 n, bytes memory str) private pure returns (bytes1) {
        return bytes1(n % 2 == 0 ? uint8(str[n / 2]) / 0x10 : uint8(str[n / 2]) % 0x10);
    }
}


// File lib/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol
contract ICheckpointManager {
    struct HeaderBlock {
        bytes32 root;
        uint256 start;
        uint256 end;
        uint256 createdAt;
        address proposer;
    }

    /**
     * @notice mapping of checkpoint header numbers to block details
     * @dev These checkpoints are submited by plasma contracts
     */
    mapping(uint256 => HeaderBlock) public headerBlocks;
}

abstract contract FxBaseRootTunnel {
    using RLPReader for RLPReader.RLPItem;
    using Merkle for bytes32;
    using ExitPayloadReader for bytes;
    using ExitPayloadReader for ExitPayloadReader.ExitPayload;
    using ExitPayloadReader for ExitPayloadReader.Log;
    using ExitPayloadReader for ExitPayloadReader.LogTopics;
    using ExitPayloadReader for ExitPayloadReader.Receipt;

    // keccak256(MessageSent(bytes))
    bytes32 public constant SEND_MESSAGE_EVENT_SIG = 0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036;

    // state sender contract
    IFxStateSender public fxRoot;
    // root chain manager
    ICheckpointManager public checkpointManager;
    // child tunnel contract which receives and sends messages
    address public fxChildTunnel;

    // storage to avoid duplicate exits
    mapping(bytes32 => bool) public processedExits;

    constructor(address _checkpointManager, address _fxRoot) {
        checkpointManager = ICheckpointManager(_checkpointManager);
        fxRoot = IFxStateSender(_fxRoot);
    }

    // set fxChildTunnel if not set already
    function setFxChildTunnel(address _fxChildTunnel) public virtual {
        require(fxChildTunnel == address(0x0), "FxBaseRootTunnel: CHILD_TUNNEL_ALREADY_SET");
        fxChildTunnel = _fxChildTunnel;
    }

    /**
     * @notice Send bytes message to Child Tunnel
     * @param message bytes message that will be sent to Child Tunnel
     * some message examples -
     *   abi.encode(tokenId);
     *   abi.encode(tokenId, tokenMetadata);
     *   abi.encode(messageType, messageData);
     * @custom:security non-reentrant
     */
    function _sendMessageToChild(bytes memory message) internal {
        fxRoot.sendMessageToChild(fxChildTunnel, message);
    }

    function _validateAndExtractMessage(bytes memory inputData) internal returns (bytes memory) {
        ExitPayloadReader.ExitPayload memory payload = inputData.toExitPayload();

        bytes memory branchMaskBytes = payload.getBranchMaskAsBytes();
        uint256 blockNumber = payload.getBlockNumber();
        // checking if exit has already been processed
        // unique exit is identified using hash of (blockNumber, branchMask, receiptLogIndex)
        bytes32 exitHash = keccak256(
            abi.encodePacked(
                blockNumber,
                // first 2 nibbles are dropped while generating nibble array
                // this allows branch masks that are valid but bypass exitHash check (changing first 2 nibbles only)
                // so converting to nibble array and then hashing it
                MerklePatriciaProof._getNibbleArray(branchMaskBytes),
                payload.getReceiptLogIndex()
            )
        );
        require(processedExits[exitHash] == false, "FxRootTunnel: EXIT_ALREADY_PROCESSED");
        processedExits[exitHash] = true;

        ExitPayloadReader.Receipt memory receipt = payload.getReceipt();
        ExitPayloadReader.Log memory log = receipt.getLog();

        // check child tunnel
        require(fxChildTunnel == log.getEmitter(), "FxRootTunnel: INVALID_FX_CHILD_TUNNEL");

        bytes32 receiptRoot = payload.getReceiptRoot();
        // verify receipt inclusion
        require(
            MerklePatriciaProof.verify(receipt.toBytes(), branchMaskBytes, payload.getReceiptProof(), receiptRoot),
            "FxRootTunnel: INVALID_RECEIPT_PROOF"
        );

        // verify checkpoint inclusion
        _checkBlockMembershipInCheckpoint(
            blockNumber,
            payload.getBlockTime(),
            payload.getTxRoot(),
            receiptRoot,
            payload.getHeaderNumber(),
            payload.getBlockProof()
        );

        ExitPayloadReader.LogTopics memory topics = log.getTopics();

        require(
            bytes32(topics.getField(0).toUint()) == SEND_MESSAGE_EVENT_SIG, // topic0 is event sig
            "FxRootTunnel: INVALID_SIGNATURE"
        );

        // received message data
        bytes memory message = abi.decode(log.getData(), (bytes)); // event decodes params again, so decoding bytes to get message
        return message;
    }

    function _checkBlockMembershipInCheckpoint(
        uint256 blockNumber,
        uint256 blockTime,
        bytes32 txRoot,
        bytes32 receiptRoot,
        uint256 headerNumber,
        bytes memory blockProof
    ) private view {
        (bytes32 headerRoot, uint256 startBlock, , uint256 createdAt, ) = checkpointManager.headerBlocks(headerNumber);

        require(
            keccak256(abi.encodePacked(blockNumber, blockTime, txRoot, receiptRoot)).checkMembership(
                blockNumber - startBlock,
                headerRoot,
                blockProof
            ),
            "FxRootTunnel: INVALID_HEADER"
        );
    }

    /**
     * @notice receive message from  L2 to L1, validated by proof
     * @dev This function verifies if the transaction actually happened on child chain
     *
     * @param inputData RLP encoded data of the reference tx containing following list of fields
     *  0 - headerNumber - Checkpoint header block number containing the reference tx
     *  1 - blockProof - Proof that the block header (in the child chain) is a leaf in the submitted merkle root
     *  2 - blockNumber - Block number containing the reference tx on child chain
     *  3 - blockTime - Reference tx block time
     *  4 - txRoot - Transactions root of block
     *  5 - receiptRoot - Receipts root of block
     *  6 - receipt - Receipt of the reference transaction
     *  7 - receiptProof - Merkle proof of the reference receipt
     *  8 - branchMask - 32 bits denoting the path of receipt in merkle tree
     *  9 - receiptLogIndex - Log Index to read from the receipt
     */
    function receiveMessage(bytes memory inputData) public virtual {
        bytes memory message = _validateAndExtractMessage(inputData);
        _processMessageFromChild(message);
    }

    /**
     * @notice Process message received from Child Tunnel
     * @dev function needs to be implemented to handle message as per requirement
     * This is called by receiveMessage function.
     * Since it is called via a system call, any event will not be emitted during its execution.
     * @param message bytes message that was sent from Child Tunnel
     */
    function _processMessageFromChild(bytes memory message) internal virtual;
}


// File contracts/staking/PolygonDepositProcessorL1.sol
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
