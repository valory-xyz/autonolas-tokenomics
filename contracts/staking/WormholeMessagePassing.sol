// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IWormhole {
    function quoteEVMDeliveryPrice() external;
    function sendPayloadToEvm() external payable;
}

contract WormholeMessagePassing {
    uint256 public constant GAS_LIMIT = 2_000_000;
    address public immutable l2TargetDispenser;
    address public immutable wormholeRelayer;
    uint256 public immutable wormholeTargetChain;

    constructor(address _l2TargetDispenser, address _wormholeRelayer, uint256 _wormholeTargetChain) {
        if (l2TargetDispenser == address(0) || _wormholeRelayer == address(0)) {
            revert();
        }

        if (_wormholeTargetChain == 0) {
            revert();
        }

        l2TargetDispenser = _l2TargetDispenser;
        wormholeRelayer = _wormholeRelayer;
        wormholeTargetChain = _wormholeTargetChain;
    }

    // TODO: We need to send to the target dispenser and supply with the staking contract target message?
    function _sendMessage(address target, uint256 amount, uint256 transferNonce) internal payable {
        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);

        // Send the message
        IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(
            wormholeTargetChain,
            l2TargetDispenser,
            abi.encode(target, amount, transferNonce),
            0,
            GAS_LIMIT
        );
    }
}