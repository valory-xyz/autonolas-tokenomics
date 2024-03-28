// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IServiceStakingFactory {
    function mapInstanceImplementations(address instance) external view returns (address);
}

interface IServiceStaking {
    function rewardsPerSecond() external view returns (uint256);
}

interface IWormhole {
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    function sendPayloadToEvm(
        // Chain ID in Wormhole format
        uint16 targetChain,
        // Contract Address on target chain we're sending a message to
        address targetAddress,
        // The payload, encoded as bytes
        bytes memory payload,
        // How much value to attach to the delivery transaction
        uint256 receiverValue,
        // The gas limit to set on the delivery transaction
        uint256 gasLimit
    ) external payable returns (
        // Unique, incrementing ID, used to identify a message
        uint64 sequence
    );
}

contract TargetDispenserL2 {
    event ServiceStakingTargetDeposited(address indexed target, uint256 amount);
    event ServiceStakingAmountWithheld(address indexed target, uint256 amount);
    event ServiceStakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount, uint256 localNonce);
    event ServiceStakingParametersUpdated(uint256 rewardsPerSecondLimit);
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);
    event WithheldAmountSynced(uint256 indexed sequence, uint256 amount);

    // Gas limit for sending a message to L1
    uint256 public constant GAS_LIMIT = 100_000;
    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source processor chain Id
    uint16 public immutable sourceChainId;
    // Proxy factory address
    address public immutable proxyFactory;
    // OLAS address
    address public immutable olas;
    // Owner address (Timelock or bridge mediator)
    address public immutable owner;
    // Source processor address on L1 that is authorized to propagate the transaction execution across the bridge
    bytes32 public immutable sourceProcessor;
    // Amount of OLAS withheld due to service staking target invalidity
    uint256 public withheldAmount;
    // rewardsPerSecondLimit
    uint256 public rewardsPerSecondLimit;
    // Reentrancy lock
    uint8 internal _locked;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;
    // Nonces to sync with L2
    mapping(address => uint256) public stakingContractNonces;
    // Queueing hashes of (target, amount, nonce)
    mapping(bytes32 => bool) public stakingQueueingNonces;

    constructor(address _proxyFactory, address _owner, address _sourceProcessor) {
        if (_proxyFactory == address(0) || _owner == address(0) || _sourceProcessor == address(0)) {
            revert();
        }

        proxyFactory = _proxyFactory;
        owner = _owner;
        sourceProcessor = _sourceProcessor;
        _locked = 1;
    }

    // TODO Provide a factory and OLAS amount verification, address checking, etc.
    function _checkServiceStakingTarget(address target) internal view returns (bool) {
        // Check for the proxy instance address
        address implementation = IServiceStakingFactory(proxyFactory).mapInstanceImplementations(target);
        if (implementation == address(0)) {
            return false;
        }

        // Check for the staking parameters
        uint256 rewardsPerSecond = IServiceStaking(target).rewardsPerSecond();
        if (rewardsPerSecond > rewardsPerSecondLimit) {
            return false;
        }

        return true;
    }

    // Process the data
    function _processData(bytes memory data) internal {
        (address target, uint256 amount, uint256 transferNonce) = abi.decode(data, (address, uint256, uint256));

        uint256 localNonce = stakingContractNonces[target];
        if (localNonce == transferNonce) {
            if (IOLAS(olas).balanceOf(address(this)) >= amount) {

                // Check the target validity address and staking parameters
                bool isValid = _checkServiceStakingTarget(target);

                if (isValid) {
                    // Approve and transfer OLAS to the service staking target
                    IOLAS(olas).approve(target, amount);
                    IServiceStaking(target).deposit(amount);
                    emit ServiceStakingTargetDeposited(target, amount);

                } else {
                    // Withhold OLAS for further usage
                    withheldAmount += amount;
                    emit ServiceStakingAmountWithheld(target, amount);
                }
                stakingContractNonces[target] = localNonce + 1;
            } else {
                // Hash of target + amount + local nonce
                bytes32 queueHash = keccak256(abi.encode(target, amount, localNonce));
                stakingQueueingNonces[queueHash] = true;
                emit ServiceStakingRequestQueued(queueHash, target, amount, localNonce);
            }
        } else {
            // Hash of target + amount + transfer nonce
            bytes32 queueHash = keccak256(abi.encode(target, amount, transferNonce));
            stakingQueueingNonces[queueHash] = true;
            emit ServiceStakingRequestQueued(queueHash, target, amount, transferNonce);
        }
    }

    function withdraw(address target, uint256 amount, uint256 transferNonce) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        uint256 localNonce = stakingContractNonces[target];
        bytes32 queueHash = keccak256(abi.encode(target, amount, transferNonce));
        bool queued = stakingQueueingNonces[queueHash];
        if (!queued) {
            revert();
        }

        if (localNonce == transferNonce) {
            if (IOLAS(olas).balanceOf(address(this)) >= amount) {
                // Check the target validity address and staking parameters
                bool isValid = _checkServiceStakingTarget(target);

                if (isValid) {
                    // Approve and transfer OLAS to the service staking target
                    IOLAS(olas).approve(target, amount);
                    IServiceStaking(target).deposit(amount);
                    emit ServiceStakingTargetDeposited(target, amount);
                } else {
                    // Withhold OLAS for further usage
                    withheldAmount += amount;
                    emit ServiceStakingAmountWithheld(target, amount);
                }
                stakingContractNonces[target] = localNonce + 1;
                stakingQueueingNonces[queueHash] = false;
            } else {
                revert();
            }
        }

        _locked = 1;
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
    function syncWithheldTokens(address refunder) external payable {
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

        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(sourceChain, 0, GAS_LIMIT);

        // Send the message
        uint256 sequence = IWormhole(wormholeRelayer).sendPayloadToEvm{value: msg.value}(
            sourceChainId,
            sourceProcessor,
            abi.encode(amount),
            0,
            GAS_LIMIT
        );

        emit WithheldAmountSynced(sequence, amount);

        _locked = 1;
    }

    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address.
    /// @param data Bytes message sent from L2 Wormhole Relayer contract.
    /// @param sourceAddress The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChain The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external {
        // Check L2 Wormhole Relayer address
        if (msg.sender != wormholeRelayer) {
            revert TargetRelayerOnly(msg.sender, wormholeRelayer);
        }

        // Check the source chain Id
        if (sourceChain != sourceGovernorChainId) {
            revert WrongSourceChainId(sourceChain, sourceGovernorChainId);
        }

        // Check for the source processor address
        bytes32 processor = sourceProcessor;
        if (processor != sourceAddress) {
            revert SourceGovernorOnly32(sourceAddress, processor);
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        // Process the data
        _processData(data);

        // Emit received message
        emit MessageReceived(processor, data, deliveryHash, sourceChain);
    }

    // TODO: implement wormhole function that receives ERC20 with payload as well?
    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}

    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
    }

    receive() external payable {}
}