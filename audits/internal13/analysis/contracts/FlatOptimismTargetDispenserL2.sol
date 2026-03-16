// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// contracts/interfaces/IBridgeErrors.sol

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
    /// @param batchHash Reference batch hash.
    error TargetAmountNotQueued(address target, uint256 amount, bytes32 batchHash);

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

// contracts/staking/DefaultTargetDispenserL2.sol

// Staking interface
interface IStaking {
    /// @dev Deposits OLAS tokens to the staking contract.
    /// @param amount OLAS amount.
    function deposit(uint256 amount) external;
}

// Staking factory interface
interface IStakingFactory {
    /// @dev Verifies staking proxy instance and gets emissions amount.
    /// @param instance Staking proxy instance.
    /// @return amount Emissions amount.
    function verifyInstanceAndGetEmissionsAmount(address instance) external view returns (uint256 amount);
}

// Necessary ERC20 token interface
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

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title DefaultTargetDispenserL2 - Smart contract for processing tokens and data received on L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract DefaultTargetDispenserL2 is IBridgeErrors {
    event OwnerUpdated(address indexed owner);
    event FundsReceived(address indexed sender, uint256 value);
    event StakingTargetDeposited(address indexed target, uint256 amount, bytes32 indexed batchHash);
    event AmountWithheld(address indexed target, uint256 amount);
    event StakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount,
        bytes32 indexed batchHash, uint256 olasBalance, uint256 paused);
    event StakingMaintenanceDataProcessed(bytes data);
    event MessagePosted(uint256 indexed sequence, address indexed messageSender, uint256 amount,
        bytes32 indexed batchHash);
    event MessageReceived(address indexed sender, uint256 chainId, bytes data);
    event WithheldAmountUpdated(uint256 amount);
    event Drain(address indexed owner, uint256 amount);
    event TargetDispenserPaused();
    event TargetDispenserUnpaused();
    event Migrated(address indexed sender, address indexed newL2TargetDispenser, uint256 amount);
    event LeftoversRefunded(address indexed sender, uint256 leftovers);

    // receiveMessage selector (Ethereum chain)
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // Default min gas limit for sending a message to L1
    // This is safe as the value is practically bigger than observed ones on numerous chains
    uint256 public constant MIN_GAS_LIMIT = 300_000;
    // Max gas limit for sending a message to L1
    // Several bridges consider this value as a maximum gas limit
    uint256 public constant MAX_GAS_LIMIT = 2_000_000;
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

    // Processed batch hashes
    mapping(bytes32 => bool) public processedHashes;
    // Queued hashes of (target, amount, batchHash)
    mapping(bytes32 => bool) public queuedHashes;

    /// @dev DefaultTargetDispenserL2 constructor.
    /// @param _olas OLAS token address on L2.
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
    /// @param updateWithheldAmount True, if withheld amount update is required.
    function _processData(bytes memory data, bool updateWithheldAmount) internal returns (uint256 totalAmount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Decode received data
        (address[] memory targets, uint256[] memory amounts, bytes32 batchHash) =
            abi.decode(data, (address[], uint256[], bytes32));

        // Check that the batch hash has not yet being processed
        // Possible scenario: bridge failed to deliver from L1 to L2, maintenance function is called by the DAO,
        // and the bridge somehow re-delivers the same message that has already been processed
        if (processedHashes[batchHash]) {
            revert AlreadyDelivered(batchHash);
        }
        processedHashes[batchHash] = true;

        uint256 localWithheldAmount = 0;
        uint256 localPaused = paused;

        // Traverse all the targets
        // Note that staking target addresses are unique, guaranteed by the L1 dispenser logic
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = amounts[i];

            // Check the target validity address and staking parameters, and get emissions amount
            // This is a low level call since it must never revert
            bytes memory verifyData = abi.encodeCall(IStakingFactory.verifyInstanceAndGetEmissionsAmount, target);
            (bool success, bytes memory returnData) = stakingFactory.call(verifyData);

            uint256 limitAmount;
            // If the function call was successful, check the return value
            if (success && returnData.length == 32) {
                limitAmount = abi.decode(returnData, (uint256));
            }

            // If the limit amount is zero, withhold OLAS amount and continue
            if (limitAmount == 0) {
                // Since the updateWithheldAmount is requested, no additional withheldAmount must be accounted for
                // to avoid double accounting as there was no funds deposited.
                if (!updateWithheldAmount) {
                    // Withhold OLAS for further usage
                    localWithheldAmount += amount;
                    emit AmountWithheld(target, amount);
                }

                // Proceed to the next target
                continue;
            }

            // Check the amount limit and adjust, if necessary
            if (amount > limitAmount) {
                // Since the updateWithheldAmount is requested, no additional withheldAmount must be accounted for
                // to avoid double accounting as there was no funds deposited.
                if (!updateWithheldAmount) {
                    // Withhold OLAS for further usage
                    uint256 targetWithheldAmount = amount - limitAmount;
                    localWithheldAmount += targetWithheldAmount;

                    emit AmountWithheld(target, targetWithheldAmount);
                }

                amount = limitAmount;
            }

            // Update total to-be-deposited amount
            totalAmount += amount;

            uint256 olasBalance = IToken(olas).balanceOf(address(this));
            // Check the OLAS balance and the contract being unpaused
            if (olasBalance >= amount && localPaused == 1) {
                // Approve and transfer OLAS to the service staking target
                IToken(olas).approve(target, amount);
                IStaking(target).deposit(amount);

                emit StakingTargetDeposited(target, amount, batchHash);
            } else {
                // Hash of target + amount + batchHash + current target dispenser address (migration-proof)
                bytes32 queueHash = keccak256(abi.encode(target, amount, batchHash, block.chainid, address(this)));
                // Queue the hash for further redeem
                queuedHashes[queueHash] = true;

                emit StakingRequestQueued(queueHash, target, amount, batchHash, olasBalance, localPaused);
            }
        }

        // Adjust withheld amount, if at least one target has not passed the validity check
        if (localWithheldAmount > 0) {
            withheldAmount += localWithheldAmount;
        }

        _locked = 1;
    }

    /// @dev Sends message to L1 to sync the withheld amount.
    /// @param amount Amount to sync.
    /// @param bridgePayload Payload data for the bridge relayer.
    /// @param batchHash Unique batch hash for each message transfer.
    /// @return sequence Unique message sequence (if applicable) or the batch hash converted to number.
    /// @return leftovers Native token leftovers from unused msg.value.
    function _sendMessage(
        uint256 amount,
        bytes memory bridgePayload,
        bytes32 batchHash
    ) internal virtual returns (uint256 sequence, uint256 leftovers);

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
        _processData(data, false);
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

    /// @dev Redeems queued staking incentive.
    /// @param target Staking target address.
    /// @param amount Staking incentive amount.
    /// @param batchHash Batch hash.
    function redeem(address target, uint256 amount, bytes32 batchHash) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        // Hash of target + amount + batchHash + chainId + current target dispenser address (migration-proof)
        bytes32 queueHash = keccak256(abi.encode(target, amount, batchHash, block.chainid, address(this)));
        bool queued = queuedHashes[queueHash];
        // Check if the target and amount are queued
        if (!queued) {
            revert TargetAmountNotQueued(target, amount, batchHash);
        }

        // Get the current contract OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        if (olasBalance >= amount) {
            // Approve and transfer OLAS to the service staking target
            IToken(olas).approve(target, amount);
            IStaking(target).deposit(amount);

            emit StakingTargetDeposited(target, amount, batchHash);

            // Remove processed queued nonce
            queuedHashes[queueHash] = false;
        } else {
            // OLAS balance is not enough for redeem
            revert InsufficientBalance(olasBalance, amount);
        }

        _locked = 1;
    }

    /// @dev Processes the data manually provided by the DAO in order to restore the data that was not delivered from L1.
    /// @notice All the staking target addresses encoded in the data must follow the undelivered ones, and thus be unique.
    ///         The data payload here must correspond to the exact data failed to be delivered (targets, incentives, batch).
    ///         Here are possible bridge failure scenarios and the way to act via the DAO vote:
    ///         - Both token and message delivery fails: re-send OLAS to the contract (separate vote), call this function;
    ///         - Token transfer succeeds, message fails: call this function;
    ///         - Token transfer fails, message succeeds: re-send OLAS to the contract (separate vote).
    /// @param data Bytes message data that was not delivered from L1.
    /// @param updateWithheldAmount True, if withheld amount update is required (must be used if there is no bridge issue).
    function processDataMaintenance(bytes memory data, bool updateWithheldAmount) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Process the data and calculate deposited amounts
        uint256 totalAmount = _processData(data, updateWithheldAmount);

        // Update withheld amount
        if (updateWithheldAmount) {
            uint256 localWithheldAmount = withheldAmount;

            // Check for overflow
            if (totalAmount > localWithheldAmount) {
                revert Overflow(totalAmount, localWithheldAmount);
            }

            // Update withheld amount
            localWithheldAmount -= totalAmount;
            withheldAmount = localWithheldAmount;

            emit WithheldAmountUpdated(localWithheldAmount);
        }

        emit StakingMaintenanceDataProcessed(data);
    }

    /// @dev Syncs withheld token amount with L1.
    /// @param bridgePayload Payload data for the bridge relayer.
    function syncWithheldAmount(bytes memory bridgePayload) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        // Get withheld amount
        uint256 amount = withheldAmount;

        // Get bridging decimals
        uint256 bridgingDecimals = getBridgingDecimals();
        // Normalized amount is equal to the withheld amount by default
        uint256 normalizedAmount = amount;
        // Normalize withheld amount
        if (bridgingDecimals < 18) {
            normalizedAmount = amount / (10 ** (18 - bridgingDecimals));
            normalizedAmount *= 10 ** (18 - bridgingDecimals);
        }

        // Check the normalized withheld amount to be greater than zero
        if (normalizedAmount == 0) {
            revert ZeroValue();
        }

        // Adjust the actual withheld amount
        // Pure amount is always bigger or equal than the normalized one
        withheldAmount = amount - normalizedAmount;

        // Get the batch hash
        uint256 batchNonce = stakingBatchNonce;
        bytes32 batchHash = keccak256(abi.encode(batchNonce, block.chainid, address(this)));

        // Send a message to sync the normalized withheld amount
        (uint256 sequence, uint256 leftovers) = _sendMessage(normalizedAmount, bridgePayload, batchHash);

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // If the call fails, ignore to avoid the attack that would prevent this function from executing
            // All the undelivered funds can be drained
            // solhint-disable-next-line avoid-low-level-calls
            msg.sender.call{value: leftovers}("");

            emit LeftoversRefunded(msg.sender, leftovers);
        }

        stakingBatchNonce = batchNonce + 1;

        emit MessagePosted(sequence, msg.sender, normalizedAmount, batchHash);

        _locked = 1;
    }

    /// @dev Updates withheld amount manually by the DAO in order to:
    ///         [1] Account for not recorded `processDataMaintenance()` amounts;
    ///         [2] Withheld amount update after balance migration to a new contract.
    /// @notice The amount here must correspond to:
    ///         [1] The exact withheldAmount minus the accumulation of all the previous
    ///             unique amounts deposited via `processDataMaintenance()` function execution;
    ///         [2] Final OLAS balance of this contract address.
    /// @param amount Updated withheld amount.
    function updateWithheldAmountMaintenance(uint256 amount) external {
        // Check the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        withheldAmount = amount;

        emit WithheldAmountUpdated(amount);
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

    /// @dev Drains contract native funds.
    /// @notice For cross-bridge leftovers and incorrectly sent funds.
    /// @return amount Drained amount to the owner address.
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

    /// @dev Migrates funds to a new specified L2 target dispenser contract address.
    /// @notice The contract must be paused to prevent other interactions.
    ///         The owner is be zeroed, the contract becomes paused and in the reentrancy state for good.
    ///         No further write interaction with the contract is going to be possible.
    ///         If the withheld amount is nonzero, it is regulated by the DAO directly on the L1 side.
    ///         If there are outstanding queued requests, they are processed by the DAO directly on the L2 side.
    function migrate(address newL2TargetDispenser) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the owner address
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that the contract is paused
        if (paused == 1) {
            revert Unpaused();
        }

        // Check that the migration address is a contract
        if (newL2TargetDispenser.code.length == 0) {
            revert WrongAccount(newL2TargetDispenser);
        }

        // Check that the new address is not the current one
        if (newL2TargetDispenser == address(this)) {
            revert WrongAccount(address(this));
        }

        // Get OLAS token amount
        uint256 amount = IToken(olas).balanceOf(address(this));
        // Transfer amount to the new L2 target dispenser
        if (amount > 0) {
            bool success = IToken(olas).transfer(newL2TargetDispenser, amount);
            if (!success) {
                revert TransferFailed(olas, address(this), newL2TargetDispenser, amount);
            }
        }

        // Zero the owner
        owner = address(0);

        emit Migrated(msg.sender, newL2TargetDispenser, amount);

        // _locked is now set to 2 for good
    }

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @return Number of supported decimals.
    function getBridgingDecimals() public pure virtual returns (uint256) {
        return 18;
    }

    /// @dev Receives native network token.
    receive() external payable {
        // Disable receiving native funds after the contract has been migrated
        if (owner == address(0)) {
            revert TransferFailed(address(0), msg.sender, address(this), msg.value);
        }

        emit FundsReceived(msg.sender, msg.value);
    }
}

// contracts/staking/OptimismTargetDispenserL2.sol

interface IBridge {
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

/// @title OptimismTargetDispenserL2 - Smart contract for processing tokens and data received on Optimism L2, and data sent back to L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract OptimismTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 32;

    /// @dev OptimismTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (L2CrossDomainMessengerProxy).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId) {}

    /// @inheritdoc DefaultTargetDispenserL2
    function _sendMessage(
        uint256 amount,
        bytes memory bridgePayload,
        bytes32 batchHash
    ) internal override returns (uint256 sequence, uint256 leftovers) {
        uint256 gasLimitMessage;

        // Check for the bridge payload length
        if (bridgePayload.length == BRIDGE_PAYLOAD_LENGTH) {
            // Decode bridge payload cutting it to required uint32 value
            gasLimitMessage = uint32(abi.decode(bridgePayload, (uint256)));

            // Check the gas limit value for the maximum recommended one
            if (gasLimitMessage > MAX_GAS_LIMIT) {
                gasLimitMessage = MAX_GAS_LIMIT;
            }
        }

        // Check the gas limit value for the minimum recommended one
        if (gasLimitMessage < MIN_GAS_LIMIT) {
            gasLimitMessage = MIN_GAS_LIMIT;
        }

        // Assemble data payload
        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount, batchHash));

        // Send the message to L1 deposit processor
        // Reference: https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l1-to-l2-transactions-1
        IBridge(l2MessageRelayer).sendMessage(l1DepositProcessor, data, uint32(gasLimitMessage));

        sequence = uint256(batchHash);

        leftovers = msg.value;
    }

    /// @dev Processes a message received from L1 deposit processor contract.
    /// @param data Bytes message data sent from L1.
    function receiveMessage(bytes memory data) external payable {
        // Check for the target dispenser address
        address l1Processor = IBridge(l2MessageRelayer).xDomainMessageSender();

        // Process the data
        _receiveMessage(msg.sender, l1Processor, data);
    }
}

