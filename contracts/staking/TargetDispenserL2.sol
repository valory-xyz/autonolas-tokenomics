// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IServiceStakingFactory {
    function mapInstanceImplementations(address instance) external view returns (address);
}

interface IServiceStaking {
    function rewardsPerSecond() external view returns (uint256);
}

contract TargetDispenserL2 {
    event ServiceStakingTargetDeposited(address indexed target, uint256 amount);
    event ServiceStakingRefundedToOwner(address indexed owner, address indexed target, uint256 amount);
    event ServiceStakingRequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount, uint256 localNonce);
    event ServiceStakingParametersUpdated(uint256 rewardsPerSecondLimit);
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source processor chain Id
    uint16 public immutable sourceGovernorChainId;
    // Proxy factory address
    address public immutable proxyFactory;
    // OLAS address
    address public immutable olas;
    // Owner address (Timelock or bridge mediator)
    address public immutable owner;
    // Source processor address on L1 that is authorized to propagate the transaction execution across the bridge
    bytes32 public immutable sourceProcessor;
    // rewardsPerSecondLimit
    uint256 public rewardsPerSecondLimit;
    // Reentrancy lock
    uint8 internal _locked;

    // Map of delivered hashes
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
                    // Send the amount to the owner address (Timelock or bridge mediator)
                    IOLAS(olas).transfer(owner, amount);
                    emit ServiceStakingRefundedToOwner(owner, target, amount);
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
                    // Send the amount to the owner address (Timelock or bridge mediator)
                    IOLAS(olas).transfer(owner, amount);
                    emit ServiceStakingRefundedToOwner(owner, target, amount);
                }
                stakingContractNonces[target] = localNonce + 1;
                stakingQueueingNonces[queueHash] = false;
            } else {
                revert();
            }
        }

        _locked = 1;
    }

    function setServiceStakingLimits(uint256 rewardsPerSecondLimitParam) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        rewardsPerSecondLimit = rewardsPerSecondLimitParam;

        emit ServiceStakingParametersUpdated(rewardsPerSecondLimitParam);
    }

    // TODO function drain() - no need as we send to the owner directly?

    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address (Timelock).
    /// @param data Bytes message sent from L2 Wormhole Relayer contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
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
}