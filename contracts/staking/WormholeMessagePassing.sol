// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IWormhole {
    function quoteEVMDeliveryPrice() external;
    function sendPayloadToEvm() external payable;
}

abstract contract WormholeMessagePassing {
    uint256 public constant GAS_LIMIT = 2_000_000;
    address public immutable l1Dispenser;
    address public immutable l2TargetDispenser;
    address public immutable wormholeRelayer;
    uint256 public immutable wormholeTargetChainId;
    uint256 public immutable targetChainId;

    // Map for wormhole delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    constructor(address _l1Dispenser, address _l2TargetDispenser, address _wormholeRelayer, uint256 _wormholeTargetChainId) {
        if (_l1Dispenser == address(0) || _l2TargetDispenser == address(0) || _wormholeRelayer == address(0)) {
            revert();
        }

        if (_wormholeTargetChainId == 0) {
            revert();
        }

        l1Dispenser = _l1Dispenser;
        l2TargetDispenser = _l2TargetDispenser;
        wormholeRelayer = _wormholeRelayer;
        wormholeTargetChainId = _wormholeTargetChainId;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(
        address[] memory targets,
        uint256[] memory amounts
    ) internal payable {
        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(wormholeTargetChainId, 0, GAS_LIMIT);

        // Send the message
        IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(
            wormholeTargetChainId,
            l2TargetDispenser,
            abi.encode(targets, amounts),
            0,
            GAS_LIMIT
        );
    }

    /// @dev Processes a message received from L1 Wormhole Relayer contract.
    /// @notice The sender must be the source processor address.
    /// @param data Bytes message sent from L1 Wormhole Relayer contract.
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
        // Check L1 Wormhole Relayer address
        if (msg.sender != wormholeRelayer) {
            revert TargetRelayerOnly(msg.sender, wormholeRelayer);
        }

        if (sourceChain != wormholeTargetChainId) {
            revert();
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        address sourceSender = address(uint160(uint256(sourceAddress)));
        if (l2TargetDispenser != sourceSender) {
            revert WrongSourceProcessor(l2TargetDispenser, sourceSender);
        }

        // Process the data
        (uint256 amount) = abi.decode(data, (uint256));

        IDispenser(l1Dispenser).syncWithheldAmount(targetChainId, amount);
    }
}