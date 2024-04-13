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
error SourceProcessorOnly(address sourceProcessor, address l1SourceProcessor);
error ReentrancyGuard();
error OwnerOnly(address sender, address owner);
error ZeroValue();

abstract contract DefaultTargetDispenserL2 {
    event ServiceStakingTargetDeposited(address indexed target, uint256 amount);
    event ServiceStakingAmountWithheld(address indexed target, uint256 amount);
    event ServiceStakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount, uint256 batchNonce);
    event ServiceStakingParametersUpdated(uint256 rewardsPerSecondLimit);
    event MessageSent(uint256 indexed sequence, address indexed messageSender, uint256 amount);
    event MessageReceived(address indexed messageSender, uint256 chainId, bytes data);
    event WithheldAmountSynced(address indexed sender, uint256 amount);
    event Paused();
    event Unpaused();

    // Gas limit for sending a message to L1
    uint256 public constant GAS_LIMIT = 100_000;
    // OLAS address
    address public immutable olas;
    // Proxy factory address
    address public immutable proxyFactory;
    // Owner address (Timelock or bridge mediator)
    address public immutable owner;
    // L2 Relayer address that receives the message across the bridge from the source L1 network
    address public immutable l2MessageRelayer;
    // Source processor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public immutable l1SourceProcessor;
    // Source processor chain Id
    uint256 public immutable l1SourceChainId;
    // Amount of OLAS withheld due to service staking target invalidity
    uint256 public withheldAmount;
    // Nonce for each staking batch
    uint256 public stakingBatchNonce;
    // rewardsPerSecondLimit
    uint256 public rewardsPerSecondLimit;
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
        address _l1SourceProcessor,
        uint256 _l1SourceChainId
    ) {
        if (_olas == address(0) || _proxyFactory == address(0) || _owner == address(0) ||
            _l2MessageRelayer == address(0) || _l1SourceProcessor == address(0)) {
            revert();
        }

        if (_l1SourceChainId == 0) {
            revert();
        }

        proxyFactory = _proxyFactory;
        owner = _owner;
        l2MessageRelayer = _l2MessageRelayer;
        l1SourceProcessor = _l1SourceProcessor;
        l1SourceChainId = _l1SourceChainId;
        paused = 1;
        _locked = 1;
    }

    // Process the data
    function _processData(bytes memory data) internal {
        (address[] memory targets, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

        uint256 batchNonce = stakingBatchNonce;
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = amounts[i];
            // TODO Shall we account for paused here and just queue, if paused?
            if (IToken(olas).balanceOf(address(this)) >= amount) {

                // Check the target validity address and staking parameters
                bool isValid = IServiceStakingFactory(proxyFactory).verifyInstance(target);

                if (isValid) {
                    // Approve and transfer OLAS to the service staking target
                    IToken(olas).approve(target, amount);
                    IServiceStaking(target).deposit(amount);
                    emit ServiceStakingTargetDeposited(target, amount);

                } else {
                    // Withhold OLAS for further usage
                    withheldAmount += amount;
                    emit ServiceStakingAmountWithheld(target, amount);
                }
            } else {
                // Hash of target + amount + batchNonce
                bytes32 queueHash = keccak256(abi.encode(target, amount, batchNonce));
                stakingQueueingNonces[queueHash] = true;
                emit ServiceStakingRequestQueued(queueHash, target, amount, batchNonce);
            }
        }
        stakingBatchNonce = batchNonce + 1;
    }

    function _sendMessage(uint256 amount, address refundAccount) internal virtual;

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

        // Check the source chain Id
        if (sourceChainId != l1SourceChainId) {
            revert WrongSourceChainId(sourceChainId, l1SourceChainId);
        }

        // Check for the source processor address
        if (sourceProcessor != l1SourceProcessor) {
            revert SourceProcessorOnly(sourceProcessor, l1SourceProcessor);
        }

        // Process the data
        _processData(data);

        // Emit received message
        emit MessageReceived(l1SourceProcessor, l1SourceChainId, data);
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
            // Check the target validity address and staking parameters
            bool isValid = IServiceStakingFactory(proxyFactory).verifyInstance(target);

            if (isValid) {
                // Approve and transfer OLAS to the service staking target
                IToken(olas).approve(target, amount);
                IServiceStaking(target).deposit(amount);
                emit ServiceStakingTargetDeposited(target, amount);
            } else {
                // Withhold OLAS for further usage
                withheldAmount += amount;
                emit ServiceStakingAmountWithheld(target, amount);
            }
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

    function setServiceStakingLimits(uint256 rewardsPerSecondLimitParam) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        rewardsPerSecondLimit = rewardsPerSecondLimitParam;

        emit ServiceStakingParametersUpdated(rewardsPerSecondLimitParam);
    }

    // TODO Finalize with the refunder (different ABI), if zero address - refunder is msg.sender
    function syncWithheldTokens(address refundAccount) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 amount = withheldAmount;
        if (amount == 0) {
            revert ZeroValue();
        }

        // Zero the withheld amount
        withheldAmount = 0;

        // Send a message to sync the withheld amount
        _sendMessage(amount, refundAccount);

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

    receive() external payable {}
}