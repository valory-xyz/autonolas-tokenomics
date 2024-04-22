// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IToken.sol";

interface IServiceStakingFactory {
    function verifyInstance(address instance) external view returns (bool);
}

interface IServiceStaking {
    function deposit(uint256 amount) external;
}

error TargetRelayerOnly(address messageSender, address l2MessageRelayer);
error WrongSourceChainId(uint256 sourceChainId, uint256 l1SourceChainId);
error DepositProcessorOnly(address sourceProcessor, address l1DepositProcessor);
error ReentrancyGuard();
error OwnerOnly(address sender, address owner);
error ZeroAddress();
error ZeroValue();

abstract contract DefaultTargetDispenserL2 {
    event FundsReceived(address indexed sender, uint256 value);
    event ServiceStakingTargetDeposited(address indexed target, uint256 amount);
    event ServiceStakingAmountWithheld(address indexed target, uint256 amount);
    event ServiceStakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount, uint256 batchNonce);
    event MessageSent(uint256 indexed sequence, address indexed messageSender, address indexed l1Processor, uint256 amount);
    event MessageReceived(address indexed sender, uint256 chainId, bytes data);
    event WithheldAmountSynced(address indexed sender, uint256 amount);
    event Drain(address indexed owner, uint256 amount);
    event Paused();
    event Unpaused();

    // receiveMessage selector (Ethereum chain)
    bytes4 public constant RECEIVE_MESSAGE = bytes4(keccak256(bytes("receiveMessage(bytes)")));
    // Gas limit for sending a message to L1
    uint256 public constant GAS_LIMIT = 300_000;
    // OLAS address
    address public immutable olas;
    // Proxy factory address
    address public immutable proxyFactory;
    // Owner address (Timelock or bridge mediator)
    address public immutable owner;
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
    // Pause switcher
    uint8 public paused;
    // Reentrancy lock
    uint8 internal _locked;

    // Queueing hashes of (target, amount, stakingBatchNonce)
    mapping(bytes32 => bool) public stakingQueueingNonces;

    constructor(
        address _olas,
        address _proxyFactory,
        address _owner,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) {
        if (_olas == address(0) || _proxyFactory == address(0) || _owner == address(0) ||
            _l2MessageRelayer == address(0) || _l1DepositProcessor == address(0)) {
            revert();
        }

        if (_l1SourceChainId == 0) {
            revert();
        }

        olas = _olas;
        proxyFactory = _proxyFactory;
        owner = _owner;
        l2MessageRelayer = _l2MessageRelayer;
        l1DepositProcessor = _l1DepositProcessor;
        l1SourceChainId = _l1SourceChainId;
        paused = 1;
        _locked = 1;
    }

    // Process the data
    function _processData(bytes memory data) internal {
        (address[] memory targets, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

        uint256 batchNonce = stakingBatchNonce;
        uint256 withheld = 0;
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = amounts[i];

            // Check the target validity address and staking parameters
            // This is a low level call since it must never revert
            (bool success, bytes memory returnData) = proxyFactory.call(abi.encodeWithSelector(
                IServiceStakingFactory.verifyInstance.selector, target));

            // If the function call was successful, check the return value
            if (success) {
                success = abi.decode(returnData, (bool));
            }

            // If verification failed, withhold OLAS amount and continue
            if (!success) {
                // Withhold OLAS for further usage
                withheld += amount;
                emit ServiceStakingAmountWithheld(target, amount);

                continue;
            }

            // TODO Shall we account for paused here and just queue, if paused?
            if (IToken(olas).balanceOf(address(this)) >= amount) {
                    // Approve and transfer OLAS to the service staking target
                    IToken(olas).approve(target, amount);
                    IServiceStaking(target).deposit(amount);
                    emit ServiceStakingTargetDeposited(target, amount);
            } else {
                // Hash of target + amount + batchNonce
                bytes32 queueHash = keccak256(abi.encode(target, amount, batchNonce));
                stakingQueueingNonces[queueHash] = true;
                emit ServiceStakingRequestQueued(queueHash, target, amount, batchNonce);
            }
        }
        stakingBatchNonce = batchNonce + 1;

        // Adjust withheld amount, if needed
        if (withheld > 0) {
            withheldAmount += withheld;
        }
    }

    function _sendMessage(uint256 amount, bytes memory bridgePayload) internal virtual;

    function _receiveMessage(
        address messageSender,
        address sourceProcessor,
        uint256 sourceChainId,
        bytes memory data
    ) internal virtual {
        // Check L2 Relayer address
        if (messageSender != l2MessageRelayer) {
            revert TargetRelayerOnly(messageSender, l2MessageRelayer);
        }

        // Check for the deposit processor address
        if (sourceProcessor != l1DepositProcessor) {
            revert DepositProcessorOnly(sourceProcessor, l1DepositProcessor);
        }

        // Check the source chain Id
        if (sourceChainId != l1SourceChainId) {
            revert WrongSourceChainId(sourceChainId, l1SourceChainId);
        }

        // Emit received message
        emit MessageReceived(l1DepositProcessor, l1SourceChainId, data);

        // Process the data
        _processData(data);
    }

    function redeem(address target, uint256 amount, uint256 batchNonce) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        if (paused == 2) {
            revert();
        }
        
        bytes32 queueHash = keccak256(abi.encode(target, amount, batchNonce));
        bool queued = stakingQueueingNonces[queueHash];
        if (!queued) {
            revert();
        }

        if (IToken(olas).balanceOf(address(this)) >= amount) {
            // Approve and transfer OLAS to the service staking target
            IToken(olas).approve(target, amount);
            IServiceStaking(target).deposit(amount);
            emit ServiceStakingTargetDeposited(target, amount);

            // Remove processed queued nonce
            stakingQueueingNonces[queueHash] = false;
        } else {
            revert();
        }

        _locked = 1;
    }

    // 1. token fails, message fails: re-send OLAS to the contract (separate vote), call processDataMaintenance
    // 2. token succeeds, message fails: call processDataMaintenance
    // 3. token fails, message succeeds: re-send OLAS to the contract (separate vote)
    // 4. message from L2 to L1 fails: call L1 syncMaintenance

    function processDataMaintenance(bytes memory data) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        _processData(data);
    }

    // TODO Finalize with the refundAccount (different ABI), if zero address - refundAccount is msg.sender
    function syncWithheldTokens(bytes memory bridgePayload) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 amount = withheldAmount;
        // TODO Check for a minimum withheld amount like 100 OLAS?
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

    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit Paused();
    }

    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit Unpaused();
    }

    /// @dev Drains contract native funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the drainer address
        if (msg.sender != owner) {
            revert ();
        }

        // Drain the slashed funds
        amount = address(this).balance;
        if (amount == 0) {
            revert();
        }

        // Send funds to the owner
        (bool result, ) = msg.sender.call{value: amount}("");
        if (!result) {
            revert ();//TransferFailed(address(0), address(this), msg.sender, amount);
        }
        emit Drain(msg.sender, amount);

        _locked = 1;
    }

    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}