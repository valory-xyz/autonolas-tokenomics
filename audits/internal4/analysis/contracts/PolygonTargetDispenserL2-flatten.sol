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


// File contracts/staking/DefaultTargetDispenserL2.sol
interface IStaking {
    function deposit(uint256 amount) external;
}

interface IStakingFactory {
    function verifyInstance(address instance) external view returns (bool);
}

interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title DefaultTargetDispenserL2 - Smart contract for processing tokens and data received on L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract DefaultTargetDispenserL2 is IBridgeErrors {
    event OwnerUpdated(address indexed owner);
    event FundsReceived(address indexed sender, uint256 value);
    event StakingTargetDeposited(address indexed target, uint256 amount);
    event StakingAmountWithheld(address indexed target, uint256 amount);
    event StakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount,
        uint256 batchNonce, uint256 paused);
    event MessagePosted(uint256 indexed sequence, address indexed messageSender, address indexed l1Processor,
        uint256 amount);
    event MessageReceived(address indexed sender, uint256 chainId, bytes data);
    event WithheldAmountSynced(address indexed sender, uint256 amount);
    event Drain(address indexed owner, uint256 amount);
    event TargetDispenserPaused();
    event TargetDispenserUnpaused();

    // receiveMessage selector (Ethereum chain)
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // Gas limit for sending a message to L1
    // This is safe as the value is approximately 3 times bigger than observed ones on numerous chains
    uint256 public constant GAS_LIMIT = 300_000;
    // OLAS address
    address public immutable olas;
    // Staking proxy factory address
    address public immutable stakingFactory;
    // L2 Relayer address that receives the message across the bridge from the source L1 network
    address public immutable l2MessageRelayer;
    // Deposit processor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public immutable l1DepositProcessor;
    // Deposit processor chain Id
    uint256 public immutable l1SourceChainId;
    // Amount of OLAS withheld due to service staking target invalidity
    uint256 public withheldAmount;
    // Nonce for each staking batch
    uint256 public stakingBatchNonce;
    // Owner address (Timelock or bridge mediator)
    address public owner;
    // Pause switcher
    uint8 public paused;
    // Reentrancy lock
    uint8 internal _locked;

    // Queueing hashes of (target, amount, stakingBatchNonce)
    mapping(bytes32 => bool) public stakingQueueingNonces;

    /// @dev DefaultTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _stakingFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address.
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _stakingFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) {
        // Check for zero addresses
        if (_olas == address(0) || _stakingFactory == address(0) || _l2MessageRelayer == address(0)
            || _l1DepositProcessor == address(0)) {
            revert ZeroAddress();
        }

        // Check for a zero value
        if (_l1SourceChainId == 0) {
            revert ZeroValue();
        }

        // Check for overflow value
        if (_l1SourceChainId > MAX_CHAIN_ID) {
            revert Overflow(_l1SourceChainId, MAX_CHAIN_ID);
        }

        // Immutable parameters assignment
        olas = _olas;
        stakingFactory = _stakingFactory;
        l2MessageRelayer = _l2MessageRelayer;
        l1DepositProcessor = _l1DepositProcessor;
        l1SourceChainId = _l1SourceChainId;

        // State variables assignment
        owner = msg.sender;
        paused = 1;
        _locked = 1;
    }

    /// @dev Processes the data received from L1.
    /// @param data Bytes message data sent from L1.
    function _processData(bytes memory data) internal {
        // Decode received data
        (address[] memory targets, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

        uint256 batchNonce = stakingBatchNonce;
        uint256 localWithheldAmount = 0;
        uint256 localPaused = paused;

        // Traverse all the targets
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = amounts[i];

            // Check the target validity address and staking parameters
            // This is a low level call since it must never revert
            (bool success, bytes memory returnData) = stakingFactory.call(abi.encodeWithSelector(
                IStakingFactory.verifyInstance.selector, target));

            // If the function call was successful, check the return value
            if (success) {
                success = abi.decode(returnData, (bool));
            }

            // If verification failed, withhold OLAS amount and continue
            if (!success) {
                // Withhold OLAS for further usage
                localWithheldAmount += amount;
                emit StakingAmountWithheld(target, amount);

                // Proceed to the next target
                continue;
            }

            // Check the OLAS balance and the contract being unpaused
            if (IToken(olas).balanceOf(address(this)) >= amount && localPaused == 1) {
                // Approve and transfer OLAS to the service staking target
                IToken(olas).approve(target, amount);
                IStaking(target).deposit(amount);

                emit StakingTargetDeposited(target, amount);
            } else {
                // Hash of target + amount + batchNonce
                bytes32 queueHash = keccak256(abi.encode(target, amount, batchNonce));
                // Queue the hash for further redeem
                stakingQueueingNonces[queueHash] = true;

                emit StakingRequestQueued(queueHash, target, amount, batchNonce, localPaused);
            }
        }
        // Increase the staking batch nonce
        stakingBatchNonce = batchNonce + 1;

        // Adjust withheld amount, if at least one target has not passed the validity check
        if (localWithheldAmount > 0) {
            withheldAmount += localWithheldAmount;
        }
    }

    /// @dev Sends message to L1 to sync the withheld amount.
    /// @param amount Amount to sync.
    /// @param bridgePayload Payload data for the bridge relayer.
    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal virtual;

    /// @dev Receives a message from L1.
    /// @param messageRelayer L2 bridge message relayer address.
    /// @param sourceProcessor L1 deposit processor address.
    /// @param data Bytes message data sent from L1.
    function _receiveMessage(
        address messageRelayer,
        address sourceProcessor,
        bytes memory data
    ) internal virtual {
        // Check L2 message relayer address
        if (messageRelayer != l2MessageRelayer) {
            revert TargetRelayerOnly(messageRelayer, l2MessageRelayer);
        }

        // Check L1 deposit processor address
        if (sourceProcessor != l1DepositProcessor) {
            revert WrongMessageSender(sourceProcessor, l1DepositProcessor);
        }

        emit MessageReceived(l1DepositProcessor, l1SourceChainId, data);

        // Process the data
        _processData(data);
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    function redeem(address target, uint256 amount, uint256 batchNonce) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        // Hash of target + amount + batchNonce
        bytes32 queueHash = keccak256(abi.encode(target, amount, batchNonce));
        bool queued = stakingQueueingNonces[queueHash];
        // Check if the target and amount are queued
        if (!queued) {
            revert TargetAmountNotQueued(target, amount, batchNonce);
        }

        // Get the current contract OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        if (olasBalance >= amount) {
            // Approve and transfer OLAS to the service staking target
            IToken(olas).approve(target, amount);
            IStaking(target).deposit(amount);

            emit StakingTargetDeposited(target, amount);

            // Remove processed queued nonce
            stakingQueueingNonces[queueHash] = false;
        } else {
            // OLAS balance is not enough for redeem
            revert InsufficientBalance(olasBalance, amount);
        }

        _locked = 1;
    }

    /// @dev Processes the data manually provided by the DAO in order to restore the data that was not delivered from L1.
    /// @notice Here are possible bridge failure scenarios and the way to act via the DAO vote:
    ///         - Both token and message delivery fails: re-send OLAS to the contract (separate vote), call this function;
    ///         - Token transfer succeeds, message fails: call this function;
    ///         - Token transfer fails, message succeeds: re-send OLAS to the contract (separate vote).
    /// @param data Bytes message data that was not delivered from L1.
    function processDataMaintenance(bytes memory data) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Process the data
        _processData(data);
    }

    /// @dev Syncs withheld token amount with L1.
    /// @param bridgePayload Payload data for the bridge relayer.
    function syncWithheldTokens(bytes memory bridgePayload) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        // Check the withheld amount to be greater than zero
        uint256 amount = withheldAmount;
        if (amount == 0) {
            revert ZeroValue();
        }

        // Zero the withheld amount
        withheldAmount = 0;

        // Send a message to sync the withheld amount
        _sendMessage(amount, bridgePayload);

        emit WithheldAmountSynced(msg.sender, amount);

        _locked = 1;
    }

    /// @dev Pause the contract.
    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit TargetDispenserPaused();
    }

    /// @dev Unpause the contract
    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit TargetDispenserUnpaused();
    }

    // TODO: shall we send all to the owner or another address?
    /// @dev Drains contract native funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the owner address
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Drain the slashed funds
        amount = address(this).balance;
        if (amount == 0) {
            revert ZeroValue();
        }

        // Send funds to the owner
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed(address(0), address(this), msg.sender, amount);
        }

        emit Drain(msg.sender, amount);

        _locked = 1;
    }

    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}


// File fx-portal/contracts/tunnel/FxBaseChildTunnel.sol@v1.0.3
// IFxMessageProcessor represents interface to process message
interface IFxMessageProcessor {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external;
}

/**
* @notice Mock child tunnel contract to receive and send message from L2
*/
abstract contract FxBaseChildTunnel is IFxMessageProcessor{
    // MessageTunnel on L1 will get data from this event
    event MessageSent(bytes message);

    // fx child
    address public fxChild;

    // fx root tunnel
    address public fxRootTunnel;

    constructor(address _fxChild) {
        fxChild = _fxChild;
    }

    // Sender must be fxRootTunnel in case of ERC20 tunnel
    modifier validateSender(address sender) {
        require(sender == fxRootTunnel, "FxBaseChildTunnel: INVALID_SENDER_FROM_ROOT");
        _;
    }

    // set fxRootTunnel if not set already
    function setFxRootTunnel(address _fxRootTunnel) external {
        require(fxRootTunnel == address(0x0), "FxBaseChildTunnel: ROOT_TUNNEL_ALREADY_SET");
        fxRootTunnel = _fxRootTunnel;
    }

    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external override {
        require(msg.sender == fxChild, "FxBaseChildTunnel: INVALID_SENDER");
        _processMessageFromRoot(stateId, rootMessageSender, data);
    }

    /**
     * @notice Emit message that can be received on Root Tunnel
     * @dev Call the internal function when need to emit message
     * @param message bytes message that will be sent to Root Tunnel
     * some message examples -
     *   abi.encode(tokenId);
     *   abi.encode(tokenId, tokenMetadata);
     *   abi.encode(messageType, messageData);
     */
    function _sendMessageToRoot(bytes memory message) internal {
        emit MessageSent(message);
    }

    /**
     * @notice Process message received from Root Tunnel
     * @dev function needs to be implemented to handle message as per requirement
     * This is called by onStateReceive function.
     * Since it is called via a system call, any event will not be emitted during its execution.
     * @param stateId unique state id
     * @param sender root message sender
     * @param message bytes message that was sent from Root Tunnel
     */
    function _processMessageFromRoot(uint256 stateId, address sender, bytes memory message) virtual internal;
}


// File contracts/staking/PolygonTargetDispenserL2.sol
/// @title PolygonTargetDispenserL2 - Smart contract for processing tokens and data received on Polygon L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract PolygonTargetDispenserL2 is DefaultTargetDispenserL2, FxBaseChildTunnel {
    /// @dev PolygonTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (fxChild).
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
        FxBaseChildTunnel(_l2MessageRelayer)
    {}

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(uint256 amount, bytes memory) internal override {
        // Assemble AMB data payload
        bytes memory data = abi.encode(amount);

        // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L50
        // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
        // Send message to L1
        _sendMessageToRoot(data);

        emit MessagePosted(0, msg.sender, l1DepositProcessor, amount);
    }

    // Source: https://github.com/0xPolygon/fx-portal/blob/731959279a77b0779f8a1eccdaea710e0babee19/contracts/tunnel/FxBaseChildTunnel.sol#L63
    // Doc: https://docs.polygon.technology/pos/how-to/bridging/l1-l2-communication/state-transfer/#child-tunnel-contract
    /// @dev Processes message received from L1 Root Tunnel.
    /// @notice Function needs to be implemented to handle message as per requirement.
    ///      This is called by onStateReceive function.
    ///      Since it is called via a system call, any event will not be emitted during its execution.
    /// @param sender Root message sender.
    /// @param data Bytes message that was sent from L1 Root Tunnel.
    function _processMessageFromRoot(uint256, address sender, bytes memory data) internal override {
        // Process the data
        _receiveMessage(l2MessageRelayer, sender, data);
    }
}
